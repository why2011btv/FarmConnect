import { Pool } from "pg";
import { createId } from "../lib/id.js";

export type AssistantChatSessionRow = {
  id: string;
  user_id: string;
  title: string;
  created_at: Date;
  updated_at: Date;
};

export type AssistantChatMessageRow = {
  id: string;
  session_id: string;
  role: "user" | "assistant";
  content: string;
  image_urls: string[];
  created_at: Date;
};

export type AssistantChatSession = {
  id: string;
  title: string;
  createdAt: string;
  updatedAt: string;
  preview?: string;
  messages?: AssistantChatMessage[];
};

export type AssistantChatMessage = {
  id: string;
  sessionId: string;
  role: "user" | "assistant";
  content: string;
  imageUrls: string[];
  createdAt: string;
};

function toIso(date: Date): string {
  return date.toISOString();
}

function toMessage(row: AssistantChatMessageRow): AssistantChatMessage {
  return {
    id: row.id,
    sessionId: row.session_id,
    role: row.role,
    content: row.content,
    imageUrls: Array.isArray(row.image_urls) ? row.image_urls : [],
    createdAt: toIso(row.created_at),
  };
}

function truncatePreview(text: string, maxLength = 80): string {
  const trimmed = text.trim();
  if (!trimmed) return "";
  return trimmed.length > maxLength ? `${trimmed.slice(0, maxLength)}…` : trimmed;
}

export class AssistantChatRepository {
  constructor(private readonly db: Pool) {}

  async listSessions(userId: string): Promise<AssistantChatSession[]> {
    const result = await this.db.query<
      AssistantChatSessionRow & { preview: string | null }
    >(
      `
      SELECT
        s.id,
        s.user_id,
        s.title,
        s.created_at,
        s.updated_at,
        (
          SELECT m.content
          FROM assistant_chat_messages m
          WHERE m.session_id = s.id
          ORDER BY m.created_at DESC
          LIMIT 1
        ) AS preview
      FROM assistant_chat_sessions s
      WHERE s.user_id = $1
      ORDER BY s.updated_at DESC
      `,
      [userId]
    );

    return result.rows.map((row) => ({
      id: row.id,
      title: row.title,
      createdAt: toIso(row.created_at),
      updatedAt: toIso(row.updated_at),
      preview: row.preview ? truncatePreview(row.preview) : undefined,
    }));
  }

  async getSession(userId: string, sessionId: string): Promise<AssistantChatSession | null> {
    const sessionResult = await this.db.query<AssistantChatSessionRow>(
      `
      SELECT id, user_id, title, created_at, updated_at
      FROM assistant_chat_sessions
      WHERE id = $1 AND user_id = $2
      LIMIT 1
      `,
      [sessionId, userId]
    );
    const session = sessionResult.rows[0];
    if (!session) return null;

    const messages = await this.listMessages(sessionId);
    return {
      id: session.id,
      title: session.title,
      createdAt: toIso(session.created_at),
      updatedAt: toIso(session.updated_at),
      messages,
    };
  }

  async listMessages(sessionId: string): Promise<AssistantChatMessage[]> {
    const result = await this.db.query<AssistantChatMessageRow>(
      `
      SELECT id, session_id, role, content, image_urls, created_at
      FROM assistant_chat_messages
      WHERE session_id = $1
      ORDER BY created_at ASC
      `,
      [sessionId]
    );
    return result.rows.map(toMessage);
  }

  async createSession(userId: string, title = "New chat"): Promise<AssistantChatSession> {
    const id = createId("acs");
    const result = await this.db.query<AssistantChatSessionRow>(
      `
      INSERT INTO assistant_chat_sessions(id, user_id, title)
      VALUES ($1, $2, $3)
      RETURNING id, user_id, title, created_at, updated_at
      `,
      [id, userId, title]
    );
    const row = result.rows[0];
    return {
      id: row.id,
      title: row.title,
      createdAt: toIso(row.created_at),
      updatedAt: toIso(row.updated_at),
      messages: [],
    };
  }

  async deleteSession(userId: string, sessionId: string): Promise<boolean> {
    const result = await this.db.query(
      `DELETE FROM assistant_chat_sessions WHERE id = $1 AND user_id = $2`,
      [sessionId, userId]
    );
    return (result.rowCount ?? 0) > 0;
  }

  async addMessage(input: {
    sessionId: string;
    role: "user" | "assistant";
    content: string;
    imageUrls?: string[];
  }): Promise<AssistantChatMessage> {
    const id = createId("acm");
    const imageUrls = input.imageUrls ?? [];
    const result = await this.db.query<AssistantChatMessageRow>(
      `
      INSERT INTO assistant_chat_messages(id, session_id, role, content, image_urls)
      VALUES ($1, $2, $3, $4, $5::jsonb)
      RETURNING id, session_id, role, content, image_urls, created_at
      `,
      [id, input.sessionId, input.role, input.content, JSON.stringify(imageUrls)]
    );

    await this.db.query(
      `UPDATE assistant_chat_sessions SET updated_at = NOW() WHERE id = $1`,
      [input.sessionId]
    );

    return toMessage(result.rows[0]);
  }

  async updateSessionTitle(sessionId: string, title: string): Promise<void> {
    await this.db.query(
      `UPDATE assistant_chat_sessions SET title = $2, updated_at = NOW() WHERE id = $1`,
      [sessionId, title]
    );
  }

  async touchSession(sessionId: string): Promise<void> {
    await this.db.query(
      `UPDATE assistant_chat_sessions SET updated_at = NOW() WHERE id = $1`,
      [sessionId]
    );
  }
}
