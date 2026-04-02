import { FastifyBaseLogger } from "fastify";
import { Pool } from "pg";
import { sendApnsPush } from "./apnsService.js";

export async function queuePushNotification(
  db: Pool,
  logger: FastifyBaseLogger,
  userId: string,
  title: string,
  body: string
) {
  const { rows } = await db.query<{ device_token: string }>(
    "SELECT device_token FROM device_tokens WHERE user_id = $1",
    [userId]
  );
  if (rows.length === 0) {
    logger.info({ userId, title }, "No registered device tokens for notification");
    return { queued: false, targetCount: 0 };
  }

  const deviceTokens = rows.map((r) => r.device_token);
  const result = await sendApnsPush(deviceTokens, title, body, { userId });

  logger.info(
    { userId, title, body, targetCount: rows.length, result },
    "Push notification dispatch result"
  );
  return { queued: true, targetCount: rows.length, ...result };
}
