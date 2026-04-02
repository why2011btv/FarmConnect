import { FastifyInstance } from "fastify";
import { Pool } from "pg";
import { z } from "zod";
import { requireAuth } from "../auth/requireAuth.js";

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
    const parsed = sendNotificationSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.message });

    // Stub for APNs worker integration.
    // In production: enqueue to background worker + APNs provider.
    const { rows } = await db.query<{ device_token: string }>(
      "SELECT device_token FROM device_tokens WHERE user_id = $1",
      [parsed.data.userId]
    );
    const targets = rows.map((r) => r.device_token);
    return { queued: true, targetCount: targets.length };
  });
}
