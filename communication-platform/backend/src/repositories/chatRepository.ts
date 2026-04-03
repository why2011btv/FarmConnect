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
    const { rows: convRows } = await this.db.query<ConversationRow>(
      `
      SELECT c.id, c.conversation_type, c.group_name, c.last_message_at
      FROM conversations c
      JOIN conversation_participants cp ON cp.conversation_id = c.id
      WHERE cp.user_id = $1
      ORDER BY c.last_message_at DESC
      `,
      [userId]
    );

    if (!convRows.length) return [];
    const ids = convRows.map((r) => r.id);
    return this.loadConversations(ids);
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

      await client.query("COMMIT");
      const conversation = (await this.loadConversations([conversationId]))[0];
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
      const conversation = (await this.loadConversations([conversationId]))[0];
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

      await client.query("COMMIT");
      const conversation = (await this.loadConversations([input.conversationId]))[0];
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

  private async loadConversations(ids: string[]): Promise<Conversation[]> {
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

    const { rows: messageRows } = await this.db.query<MessageRow>(
      `
      SELECT id, conversation_id, from_user_id, from_user_name, to_user_id, text, created_at, read
      FROM messages
      WHERE conversation_id = ANY($1::text[])
      ORDER BY created_at ASC
      `,
      [ids]
    );

    const participantsByConversation = new Map<string, ParticipantRow[]>();
    for (const row of participantRows) {
      const list = participantsByConversation.get(row.conversation_id) ?? [];
      list.push(row);
      participantsByConversation.set(row.conversation_id, list);
    }

    const messagesByConversation = new Map<string, Message[]>();
    for (const row of messageRows) {
      const list = messagesByConversation.get(row.conversation_id) ?? [];
      list.push(toMessage(row));
      messagesByConversation.set(row.conversation_id, list);
    }

    return convRows.map((row) => {
      const participants = participantsByConversation.get(row.id) ?? [];
      return {
        id: row.id,
        type: row.conversation_type,
        groupName: row.group_name ?? undefined,
        participants: participants.map((p) => p.user_id).sort(),
        participantNames: participants.map((p) => p.user_name),
        messages: messagesByConversation.get(row.id) ?? [],
        lastMessageAt: Number(row.last_message_at),
      };
    });
  }
}
