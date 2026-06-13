import { FastifyInstance } from "fastify";
import { Pool } from "pg";
import { z } from "zod";
import { requireAuth } from "../auth/requireAuth.js";
import { badRequest } from "../lib/badRequest.js";
import {
  AssistantChatRepository,
  AssistantChatMessage,
} from "../repositories/assistantChatRepository.js";
import { completeAssistantChat, ChatMessageInput } from "../services/openRouterChatService.js";

const createSessionSchema = z.object({
  title: z.string().min(1).max(120).optional(),
});

const sendChatSchema = z.object({
  sessionId: z.string().min(1).optional(),
  text: z.string(),
  imageUrls: z.array(z.string().url()).max(5).optional(),
});

function buildOpenRouterMessages(messages: AssistantChatMessage[]): ChatMessageInput[] {
  const lastUserIndex = messages.map((m) => m.role).lastIndexOf("user");
  return messages.map((message, index) => ({
    role: message.role,
    content: message.content,
    imageUrls: index === lastUserIndex ? message.imageUrls : undefined,
  }));
}

function deriveTitle(text: string): string {
  const trimmed = text.trim();
  if (!trimmed) return "New chat";
  const maxLength = 40;
  return trimmed.length > maxLength ? `${trimmed.slice(0, maxLength)}…` : trimmed;
}

export async function aiRoutes(app: FastifyInstance, db: Pool) {
  const repo = new AssistantChatRepository(db);

  app.get("/v1/ai/sessions", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;
    const items = await repo.listSessions(authUser.id);
    return { items };
  });

  app.post("/v1/ai/sessions", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;

    const parsed = createSessionSchema.safeParse(req.body ?? {});
    if (!parsed.success) return reply.code(400).send(badRequest(parsed.error));

    const item = await repo.createSession(authUser.id, parsed.data.title ?? "New chat");
    return { item };
  });

  app.get("/v1/ai/sessions/:sessionId", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;

    const { sessionId } = req.params as { sessionId: string };
    const item = await repo.getSession(authUser.id, sessionId);
    if (!item) return reply.code(404).send({ error: "Session not found" });
    return { item };
  });

  app.delete("/v1/ai/sessions/:sessionId", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;

    const { sessionId } = req.params as { sessionId: string };
    const deleted = await repo.deleteSession(authUser.id, sessionId);
    if (!deleted) return reply.code(404).send({ error: "Session not found" });
    return reply.code(204).send();
  });

  app.post("/v1/ai/chat", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;

    const parsed = sendChatSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send(badRequest(parsed.error));

    const text = parsed.data.text.trim();
    const imageUrls = parsed.data.imageUrls ?? [];
    if (!text && imageUrls.length === 0) {
      return reply.code(400).send({ error: "Message text or image is required" });
    }

    if (!process.env.OPENROUTER_API_KEY) {
      return reply.code(503).send({ error: "AI chat is not configured" });
    }

    let sessionId = parsed.data.sessionId;
    let session = sessionId ? await repo.getSession(authUser.id, sessionId) : null;
    if (sessionId && !session) {
      return reply.code(404).send({ error: "Session not found" });
    }
    if (!session) {
      session = await repo.createSession(authUser.id);
      sessionId = session.id;
    }

    try {
      const userMessage = await repo.addMessage({
        sessionId: sessionId!,
        role: "user",
        content: text,
        imageUrls,
      });

      if (session.title === "New chat" && text) {
        await repo.updateSessionTitle(sessionId!, deriveTitle(text));
      }

      const history = await repo.listMessages(sessionId!);
      const replyText = await completeAssistantChat(app.log, buildOpenRouterMessages(history));

      const assistantMessage = await repo.addMessage({
        sessionId: sessionId!,
        role: "assistant",
        content: replyText,
      });

      const updatedSession = await repo.getSession(authUser.id, sessionId!);
      return {
        session: updatedSession,
        userMessage,
        assistantMessage,
        reply: replyText,
      };
    } catch (error) {
      app.log.error({ error }, "AI chat failed");
      const message = error instanceof Error ? error.message : "Failed to get AI response";
      return reply.code(502).send({ error: message });
    }
  });
}
