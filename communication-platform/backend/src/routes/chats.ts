import { FastifyInstance } from "fastify";
import { z } from "zod";
import { ChatRepository } from "../repositories/chatRepository.js";

const listQuerySchema = z.object({
  userId: z.string().min(1),
});

const getMessagesQuerySchema = z.object({
  userA: z.string().min(1),
  userB: z.string().min(1),
});

const sendMessageSchema = z.object({
  fromUserId: z.string().min(1),
  fromUserName: z.string().min(1),
  toUserId: z.string().min(1),
  text: z.string().min(1),
});

export async function chatRoutes(app: FastifyInstance, chatRepository: ChatRepository) {
  app.get("/v1/conversations", async (req, reply) => {
    const parsed = listQuerySchema.safeParse(req.query);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.message });

    const list = await chatRepository.listConversations(parsed.data.userId);
    return { items: list };
  });

  app.get("/v1/messages", async (req, reply) => {
    const parsed = getMessagesQuerySchema.safeParse(req.query);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.message });

    const items = await chatRepository.listMessages(parsed.data.userA, parsed.data.userB);
    return { items };
  });

  app.post("/v1/messages", async (req, reply) => {
    const parsed = sendMessageSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.message });

    const result = await chatRepository.sendMessage(parsed.data);
    return { item: result.message, conversation: result.conversation };
  });
}
