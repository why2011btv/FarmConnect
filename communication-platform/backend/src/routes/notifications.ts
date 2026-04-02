import { FastifyInstance } from "fastify";
import { Pool } from "pg";
import { z } from "zod";
import { requireAuth } from "../auth/requireAuth.js";
import { queuePushNotification } from "../services/notificationService.js";

const registerTokenSchema = z.object({
  deviceToken: z.string().min(1),
});

const sendNotificationSchema = z.object({
  userId: z.string().min(1),
  title: z.string().min(1),
  body: z.string().min(1),
});

export async function notificationRoutes(app: FastifyInstance, db: Pool) {
  app.post("/v1/notifications/register-device", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;

    const parsed = registerTokenSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.message });

    await db.query(
      `
      INSERT INTO device_tokens(user_id, device_token)
      VALUES ($1, $2)
      ON CONFLICT DO NOTHING
      `,
      [authUser.id, parsed.data.deviceToken]
    );
    return { ok: true };
  });

  app.post("/v1/notifications/send", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;

    const parsed = sendNotificationSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.message });

    // Allow sending only to self in this scaffold endpoint.
    if (parsed.data.userId !== authUser.id) {
      return reply.code(403).send({ error: "Cannot send arbitrary notifications" });
    }
    return queuePushNotification(db, app.log, parsed.data.userId, parsed.data.title, parsed.data.body);
  });
}
