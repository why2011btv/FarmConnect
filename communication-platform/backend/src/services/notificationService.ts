import { FastifyBaseLogger } from "fastify";
import { Pool } from "pg";

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

  // APNs integration point:
  // Replace with queue + APNs provider call in production.
  logger.info(
    { userId, title, body, targetCount: rows.length },
    "Queued push notification stub"
  );
  return { queued: true, targetCount: rows.length };
}
