import { FastifyInstance } from "fastify";
import { Pool } from "pg";
import { z } from "zod";
import { requireAuth } from "../auth/requireAuth.js";
import { ChatRepository } from "../repositories/chatRepository.js";
import { queuePushNotification } from "../services/notificationService.js";

const getMessagesQuerySchema = z.object({
  otherUserId: z.string().min(1),
});

const sendMessageSchema = z.object({
  toUserId: z.string().min(1),
  text: z.string().min(1),
});

export async function chatRoutes(app: FastifyInstance, chatRepository: ChatRepository, db: Pool) {
  app.get("/v1/conversations", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;
    const list = await chatRepository.listConversations(authUser.id);
    return { items: list };
  });

  app.get("/v1/messages", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;

    const parsed = getMessagesQuerySchema.safeParse(req.query);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.message });

    const items = await chatRepository.listMessages(authUser.id, parsed.data.otherUserId);
    return { items };
  });

  app.post("/v1/messages", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;

    const parsed = sendMessageSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.message });

    const result = await chatRepository.sendMessage({
      ...parsed.data,
      fromUserId: authUser.id,
      fromUserName: authUser.name,
    });
    if (parsed.data.toUserId !== authUser.id) {
      await queuePushNotification(
        db,
        app.log,
        parsed.data.toUserId,
        "New message",
        `${authUser.name}: ${parsed.data.text}`
      );
    }
    return { item: result.message, conversation: result.conversation };
  });
}
