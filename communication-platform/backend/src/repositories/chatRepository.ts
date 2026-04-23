import { Pool } from "pg";
import { createId, getConversationId } from "../lib/id.js";
import { Conversation, Message } from "../types.js";

type ConversationRow = {
  id: string;
  conversation_type: "direct" | "group";
  group_name: string | null;
  last_message_at: string;
};

type MessageRow = {
  id: string;
  conversation_id: string;
  from_user_id: string;
  from_user_name: string;
  to_user_id: string;
  text: string;
  created_at: string;
  read: boolean;
};

type ParticipantRow = {
  conversation_id: string;
  user_id: string;
  user_name: string;
};

type SendMessageInput = {
  fromUserId: string;
  fromUserName: string;
  toUserId: string;
  text: string;
};

type SendMessageToConversationInput = {
  fromUserId: string;
  fromUserName: string;
  conversationId: string;
  text: string;
};

function toMessage(row: MessageRow): Message {
  return {
    id: row.id,
    conversationId: row.conversation_id,
    fromUserId: row.from_user_id,
    fromUserName: row.from_user_name,
    toUserId: row.to_user_id ?? undefined,
    text: row.text,
    createdAt: Number(row.created_at),
    read: row.read,
  };
}

export class ChatRepository {
  constructor(private readonly db: Pool) {}

  async listConversations(userId: string): Promise<Conversation[]> {
    // Only the conversations this user is actively part of. `last_read_at`
    // lets us compute unread counts without pulling every message into the
    // payload, which keeps the list endpoint cheap as history grows.
    const { rows: convRows } = await this.db.query<ConversationRow & { last_read_at: string }>(
      `
      SELECT c.id, c.conversation_type, c.group_name, c.last_message_at, cp.last_read_at
      FROM conversations c
      JOIN conversation_participants cp ON cp.conversation_id = c.id
      WHERE cp.user_id = $1
      ORDER BY c.last_message_at DESC
      `,
      [userId]
    );

    if (!convRows.length) return [];
    const ids = convRows.map((r) => r.id);
    const lastReadByConversation = new Map<string, number>();
    for (const row of convRows) {
      lastReadByConversation.set(row.id, Number(row.last_read_at));
    }
    return this.loadConversations(ids, { requesterUserId: userId, lastReadByConversation });
  }

  async listMessages(userA: string, userB: string): Promise<Message[]> {
    const id = getConversationId(userA, userB);
    return this.listMessagesByConversation(id, userA);
  }

  async sendMessage(input: SendMessageInput): Promise<{ message: Message; conversation: Conversation }> {
    const conversationId = getConversationId(input.fromUserId, input.toUserId);
    const now = Date.now();
    const messageId = createId("m");
    const client = await this.db.connect();
    try {
      await client.query("BEGIN");
      await client.query(
        `
        INSERT INTO conversations(id, last_message_at)
        VALUES($1, $2)
        ON CONFLICT(id) DO UPDATE SET last_message_at = EXCLUDED.last_message_at
        `,
        [conversationId, now]
      );

      await client.query(
        `
        INSERT INTO conversation_participants(conversation_id, user_id)
        VALUES ($1, $2), ($1, $3)
        ON CONFLICT DO NOTHING
        `,
        [conversationId, input.fromUserId, input.toUserId]
      );

      const { rows: msgRows } = await client.query<MessageRow>(
        `
        INSERT INTO messages(
          id, conversation_id, from_user_id, from_user_name, to_user_id, text, created_at, read
        )
        VALUES($1, $2, $3, $4, $5, $6, $7, FALSE)
        RETURNING id, conversation_id, from_user_id, from_user_name, to_user_id, text, created_at, read
        `,
        [messageId, conversationId, input.fromUserId, input.fromUserName, input.toUserId, input.text, now]
      );

      // Sending counts as reading: the sender should never see their own
      // message as unread.
      await client.query(
        `
        UPDATE conversation_participants
        SET last_read_at = GREATEST(last_read_at, $3)
        WHERE conversation_id = $1 AND user_id = $2
        `,
        [conversationId, input.fromUserId, now]
      );

      await client.query("COMMIT");
      const conversation = (await this.loadConversations(
        [conversationId],
        { requesterUserId: input.fromUserId, lastReadByConversation: new Map([[conversationId, now]]) }
      ))[0];
      return {
        message: toMessage(msgRows[0]),
        conversation,
      };
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }

  async createGroupConversation(
    creatorUserId: string,
    groupName: string,
    memberUserIds: string[]
  ): Promise<Conversation> {
    const conversationId = createId("g");
    const now = Date.now();
    const members = Array.from(new Set([creatorUserId, ...memberUserIds]));
    const client = await this.db.connect();
    try {
      await client.query("BEGIN");
      await client.query(
        `
        INSERT INTO conversations(id, conversation_type, group_name, last_message_at)
        VALUES($1, 'group', $2, $3)
        `,
        [conversationId, groupName, now]
      );
      for (const userId of members) {
        await client.query(
          `
          INSERT INTO conversation_participants(conversation_id, user_id)
          VALUES ($1, $2)
          ON CONFLICT DO NOTHING
          `,
          [conversationId, userId]
        );
      }
      await client.query("COMMIT");
      const conversation = (await this.loadConversations(
        [conversationId],
        { requesterUserId: creatorUserId, lastReadByConversation: new Map([[conversationId, now]]) }
      ))[0];
      return conversation;
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }

  async listMessagesByConversation(conversationId: string, requesterUserId: string): Promise<Message[]> {
    const membership = await this.db.query<{ user_id: string }>(
      `
      SELECT user_id
      FROM conversation_participants
      WHERE conversation_id = $1 AND user_id = $2
      `,
      [conversationId, requesterUserId]
    );
    if (!membership.rows[0]) return [];

    const { rows } = await this.db.query<MessageRow>(
      `
      SELECT id, conversation_id, from_user_id, from_user_name, to_user_id, text, created_at, read
      FROM messages
      WHERE conversation_id = $1
      ORDER BY created_at ASC
      `,
      [conversationId]
    );
    return rows.map(toMessage);
  }

  async sendMessageToConversation(
    input: SendMessageToConversationInput
  ): Promise<{ message: Message; conversation: Conversation }> {
    const client = await this.db.connect();
    const now = Date.now();
    const messageId = createId("m");
    try {
      await client.query("BEGIN");
      const membership = await client.query(
        `
        SELECT user_id
        FROM conversation_participants
        WHERE conversation_id = $1 AND user_id = $2
        `,
        [input.conversationId, input.fromUserId]
      );
      if (!membership.rows[0]) {
        throw new Error("User is not a member of this conversation");
      }

      const { rows: convRows } = await client.query<{ conversation_type: "direct" | "group"; participants: string[] }>(
        `
        SELECT
          c.conversation_type,
          ARRAY_AGG(cp.user_id) AS participants
        FROM conversations c
        JOIN conversation_participants cp ON cp.conversation_id = c.id
        WHERE c.id = $1
        GROUP BY c.conversation_type
        `,
        [input.conversationId]
      );
      if (!convRows[0]) throw new Error("Conversation not found");

      const convType = convRows[0].conversation_type;
      let toUserId: string | null = null;
      if (convType === "direct") {
        const other = convRows[0].participants.find((p) => p !== input.fromUserId);
        toUserId = other ?? null;
      }

      const { rows: msgRows } = await client.query<MessageRow>(
        `
        INSERT INTO messages(
          id, conversation_id, from_user_id, from_user_name, to_user_id, text, created_at, read
        )
        VALUES($1, $2, $3, $4, $5, $6, $7, FALSE)
        RETURNING id, conversation_id, from_user_id, from_user_name, to_user_id, text, created_at, read
        `,
        [messageId, input.conversationId, input.fromUserId, input.fromUserName, toUserId, input.text, now]
      );

      await client.query(
        `
        UPDATE conversations
        SET last_message_at = $2
        WHERE id = $1
        `,
        [input.conversationId, now]
      );

      // Same reasoning as in `sendMessage` above: bump the sender's read
      // cursor so they don't see their outgoing message as unread.
      await client.query(
        `
        UPDATE conversation_participants
        SET last_read_at = GREATEST(last_read_at, $3)
        WHERE conversation_id = $1 AND user_id = $2
        `,
        [input.conversationId, input.fromUserId, now]
      );

      await client.query("COMMIT");
      const conversation = (await this.loadConversations(
        [input.conversationId],
        { requesterUserId: input.fromUserId, lastReadByConversation: new Map([[input.conversationId, now]]) }
      ))[0];
      return { message: toMessage(msgRows[0]), conversation };
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }

  async getConversationParticipantIds(conversationId: string): Promise<string[]> {
    const { rows } = await this.db.query<{ user_id: string }>(
      `
      SELECT user_id
      FROM conversation_participants
      WHERE conversation_id = $1
      `,
      [conversationId]
    );
    return rows.map((r) => r.user_id);
  }

  async markConversationRead(conversationId: string, userId: string, readAt: number = Date.now()): Promise<void> {
    await this.db.query(
      `
      UPDATE conversation_participants
      SET last_read_at = GREATEST(last_read_at, $3)
      WHERE conversation_id = $1 AND user_id = $2
      `,
      [conversationId, userId, readAt]
    );
  }

  /**
   * Removes the user from a conversation. For direct chats we drop the
   * entire conversation so the other side isn't left in a ghost thread; for
   * groups we only remove the requester so the rest of the group survives.
   * Returns true if the caller was actually a participant.
   */
  async leaveConversation(conversationId: string, userId: string): Promise<boolean> {
    const { rows } = await this.db.query<{ conversation_type: "direct" | "group" }>(
      `
      SELECT c.conversation_type
      FROM conversations c
      JOIN conversation_participants cp ON cp.conversation_id = c.id
      WHERE c.id = $1 AND cp.user_id = $2
      `,
      [conversationId, userId]
    );
    if (!rows[0]) return false;

    if (rows[0].conversation_type === "direct") {
      await this.db.query("DELETE FROM conversations WHERE id = $1", [conversationId]);
    } else {
      await this.db.query(
        "DELETE FROM conversation_participants WHERE conversation_id = $1 AND user_id = $2",
        [conversationId, userId]
      );
    }
    return true;
  }

  private async loadConversations(
    ids: string[],
    options?: {
      requesterUserId: string;
      lastReadByConversation: Map<string, number>;
    }
  ): Promise<Conversation[]> {
    if (!ids.length) return [];

    const { rows: convRows } = await this.db.query<ConversationRow>(
      `
      SELECT id, conversation_type, group_name, last_message_at
      FROM conversations
      WHERE id = ANY($1::text[])
      ORDER BY last_message_at DESC
      `,
      [ids]
    );

    const { rows: participantRows } = await this.db.query<ParticipantRow>(
      `
      SELECT cp.conversation_id, cp.user_id, u.name AS user_name
      FROM conversation_participants cp
      JOIN users u ON u.id = cp.user_id
      WHERE cp.conversation_id = ANY($1::text[])
      `,
      [ids]
    );

    // For the list endpoint we only need the single most recent message per
    // conversation for the preview. DISTINCT ON is the cheapest way to get
    // that in Postgres without correlated subqueries.
    const { rows: lastMessageRows } = await this.db.query<MessageRow>(
      `
      SELECT DISTINCT ON (conversation_id)
        id, conversation_id, from_user_id, from_user_name, to_user_id, text, created_at, read
      FROM messages
      WHERE conversation_id = ANY($1::text[])
      ORDER BY conversation_id, created_at DESC
      `,
      [ids]
    );

    const participantsByConversation = new Map<string, ParticipantRow[]>();
    for (const row of participantRows) {
      const list = participantsByConversation.get(row.conversation_id) ?? [];
      list.push(row);
      participantsByConversation.set(row.conversation_id, list);
    }

    const lastMessageByConversation = new Map<string, Message>();
    for (const row of lastMessageRows) {
      lastMessageByConversation.set(row.conversation_id, toMessage(row));
    }

    // Unread counts are computed per-user using the stored last_read_at
    // cursor. Messages the requester sent themselves never count as unread.
    const unreadByConversation = new Map<string, number>();
    if (options) {
      const { rows: unreadRows } = await this.db.query<{ conversation_id: string; unread: string }>(
        `
        SELECT m.conversation_id, COUNT(*)::text AS unread
        FROM messages m
        JOIN conversation_participants cp
          ON cp.conversation_id = m.conversation_id AND cp.user_id = $2
        WHERE m.conversation_id = ANY($1::text[])
          AND m.from_user_id <> $2
          AND m.created_at > cp.last_read_at
        GROUP BY m.conversation_id
        `,
        [ids, options.requesterUserId]
      );
      for (const row of unreadRows) {
        unreadByConversation.set(row.conversation_id, Number(row.unread));
      }
    }

    return convRows.map((row) => {
      const participants = participantsByConversation.get(row.id) ?? [];
      const lastMessage = lastMessageByConversation.get(row.id);
      return {
        id: row.id,
        type: row.conversation_type,
        groupName: row.group_name ?? undefined,
        participants: participants.map((p) => p.user_id).sort(),
        participantNames: participants.map((p) => p.user_name),
        messages: lastMessage ? [lastMessage] : [],
        lastMessage,
        lastMessageAt: Number(row.last_message_at),
        unreadCount: unreadByConversation.get(row.id) ?? 0,
      };
    });
  }
}
