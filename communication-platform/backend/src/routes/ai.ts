import { FastifyInstance } from "fastify";
import { Pool } from "pg";
import { z } from "zod";
import { requireAuth } from "../auth/requireAuth.js";
import { badRequest } from "../lib/badRequest.js";
import { completeAssistantChat } from "../services/openRouterChatService.js";

const chatMessageSchema = z.object({
  role: z.enum(["user", "assistant"]),
  content: z.string(),
  imageDataUrls: z.array(z.string().min(1)).max(5).optional(),
});

const chatSchema = z.object({
  messages: z.array(chatMessageSchema).min(1),
});

export async function aiRoutes(app: FastifyInstance, db: Pool) {
  app.post("/v1/ai/chat", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;

    const parsed = chatSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send(badRequest(parsed.error));

    if (!process.env.OPENROUTER_API_KEY) {
      return reply.code(503).send({ error: "AI chat is not configured" });
    }

    try {
      const replyText = await completeAssistantChat(app.log, parsed.data.messages);
      return { reply: replyText };
    } catch (error) {
      app.log.error({ error }, "AI chat failed");
      return reply.code(502).send({ error: "Failed to get AI response" });
    }
  });
}
