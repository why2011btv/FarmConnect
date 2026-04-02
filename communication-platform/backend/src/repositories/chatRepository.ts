import { Pool } from "pg";
import { createId, getConversationId } from "../lib/id.js";
import { Conversation, Message } from "../types.js";

type ConversationRow = {
  id: string;
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

function toMessage(row: MessageRow): Message {
  return {
    id: row.id,
    conversationId: row.conversation_id,
    fromUserId: row.from_user_id,
    fromUserName: row.from_user_name,
    toUserId: row.to_user_id,
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
      SELECT c.id, c.last_message_at
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
    const { rows } = await this.db.query<MessageRow>(
      `
      SELECT id, conversation_id, from_user_id, from_user_name, to_user_id, text, created_at, read
      FROM messages
      WHERE conversation_id = $1
      ORDER BY created_at ASC
      `,
      [id]
    );
    return rows.map(toMessage);
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

  private async loadConversations(ids: string[]): Promise<Conversation[]> {
    if (!ids.length) return [];

    const { rows: convRows } = await this.db.query<ConversationRow>(
      `
      SELECT id, last_message_at
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
        participants: participants.map((p) => p.user_id).sort(),
        participantNames: participants.map((p) => p.user_name),
        messages: messagesByConversation.get(row.id) ?? [],
        lastMessageAt: Number(row.last_message_at),
      };
    });
  }
}
