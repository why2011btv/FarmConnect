import { FastifyInstance } from "fastify";
import { Pool } from "pg";
import { z } from "zod";
import { requireAuth } from "../auth/requireAuth.js";
import { ChatRepository } from "../repositories/chatRepository.js";
import { moderateUserContent } from "../services/moderationService.js";
import { queuePushNotification } from "../services/notificationService.js";

const getMessagesQuerySchema = z.object({
  otherUserId: z.string().min(1).optional(),
  conversationId: z.string().min(1).optional(),
});

const sendMessageSchema = z.object({
  toUserId: z.string().min(1).optional(),
  conversationId: z.string().min(1).optional(),
  text: z.string().min(1),
});

const createGroupSchema = z.object({
  name: z.string().min(1),
  memberUserIds: z.array(z.string().min(1)).min(1),
});

export async function chatRoutes(app: FastifyInstance, chatRepository: ChatRepository, db: Pool) {
  app.get("/v1/users", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;
    const { rows } = await db.query<{ id: string; name: string }>(
      "SELECT id, name FROM users WHERE id <> $1 ORDER BY name ASC",
      [authUser.id]
    );
    return { items: rows };
  });

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

    let items: Awaited<ReturnType<ChatRepository["listMessages"]>>;
    if (parsed.data.conversationId) {
      items = await chatRepository.listMessagesByConversation(parsed.data.conversationId, authUser.id);
    } else if (parsed.data.otherUserId) {
      items = await chatRepository.listMessages(authUser.id, parsed.data.otherUserId);
    } else {
      return reply.code(400).send({ error: "conversationId or otherUserId is required" });
    }
    return { items };
  });

  app.post("/v1/conversations/group", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;
    const parsed = createGroupSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.message });

    const conversation = await chatRepository.createGroupConversation(
      authUser.id,
      parsed.data.name.trim(),
      parsed.data.memberUserIds
    );
    return { item: conversation };
  });

  app.post("/v1/messages", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;

    const parsed = sendMessageSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.message });

    const moderation = await moderateUserContent(app.log, {
      text: parsed.data.text,
    });
    if (!moderation.allowed) {
      return reply.code(400).send({
        error: `Content violates platform rule: ${moderation.reason ?? "inappropriate content detected"}`,
      });
    }

    let result: Awaited<ReturnType<ChatRepository["sendMessage"]>> | Awaited<ReturnType<ChatRepository["sendMessageToConversation"]>>;
    if (parsed.data.conversationId) {
      result = await chatRepository.sendMessageToConversation({
        fromUserId: authUser.id,
        fromUserName: authUser.name,
        conversationId: parsed.data.conversationId,
        text: parsed.data.text,
      });
      const participantIds = await chatRepository.getConversationParticipantIds(parsed.data.conversationId);
      for (const participantId of participantIds) {
        if (participantId === authUser.id) continue;
        await queuePushNotification(
          db,
          app.log,
          participantId,
          "New group message",
          `${authUser.name}: ${parsed.data.text}`
        );
      }
    } else if (parsed.data.toUserId) {
      result = await chatRepository.sendMessage({
        toUserId: parsed.data.toUserId,
        text: parsed.data.text,
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
    } else {
      return reply.code(400).send({ error: "conversationId or toUserId is required" });
    }
    return { item: result.message, conversation: result.conversation };
  });
}
