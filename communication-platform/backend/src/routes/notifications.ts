import { FastifyInstance } from "fastify";
import { Pool } from "pg";
import { z } from "zod";
import { requireAuth } from "../auth/requireAuth.js";
import { queuePushNotification } from "../services/notificationService.js";

const categoryValues = ["Disease", "Pest", "Weather", "Note", "Market"] as const;

const registerTokenSchema = z.object({
  deviceToken: z.string().min(1),
});

const sendNotificationSchema = z.object({
  userId: z.string().min(1),
  title: z.string().min(1),
  body: z.string().min(1),
});

const notificationPreferencesSchema = z.object({
  enabled: z.boolean(),
  radiusMiles: z.number().int().min(1).max(100),
  categories: z.array(z.enum(categoryValues)).min(1),
  quietHoursEnabled: z.boolean(),
  quietStart: z.string().regex(/^\d{2}:\d{2}$/),
  quietEnd: z.string().regex(/^\d{2}:\d{2}$/),
  timezoneOffsetMinutes: z.number().int().min(-14 * 60).max(14 * 60),
  locationLat: z.number().min(-90).max(90).nullable(),
  locationLng: z.number().min(-180).max(180).nullable(),
});

type NotificationPreferenceRow = {
  user_id: string;
  enabled: boolean;
  radius_miles: number;
  categories: string[];
  quiet_hours_enabled: boolean;
  quiet_start: string;
  quiet_end: string;
  timezone_offset_minutes: number;
  location_lat: number | null;
  location_lng: number | null;
};

function defaultPreferences() {
  return {
    enabled: true,
    radiusMiles: 10,
    categories: [...categoryValues],
    quietHoursEnabled: false,
    quietStart: "22:00",
    quietEnd: "07:00",
    timezoneOffsetMinutes: 0,
    locationLat: null as number | null,
    locationLng: null as number | null,
  };
}

function toPreferences(row: NotificationPreferenceRow | undefined) {
  if (!row) return defaultPreferences();
  return {
    enabled: row.enabled,
    radiusMiles: row.radius_miles,
    categories: row.categories.filter((value): value is (typeof categoryValues)[number] =>
      categoryValues.includes(value as (typeof categoryValues)[number])
    ),
    quietHoursEnabled: row.quiet_hours_enabled,
    quietStart: row.quiet_start,
    quietEnd: row.quiet_end,
    timezoneOffsetMinutes: row.timezone_offset_minutes,
    locationLat: row.location_lat,
    locationLng: row.location_lng,
  };
}

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

  app.get("/v1/notifications/preferences", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;

    const { rows } = await db.query<NotificationPreferenceRow>(
      `
      SELECT
        user_id, enabled, radius_miles, categories, quiet_hours_enabled,
        quiet_start, quiet_end, timezone_offset_minutes, location_lat, location_lng
      FROM notification_preferences
      WHERE user_id = $1
      LIMIT 1
      `,
      [authUser.id]
    );

    return { item: toPreferences(rows[0]) };
  });

  app.put("/v1/notifications/preferences", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;

    const parsed = notificationPreferencesSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.message });

    const prefs = parsed.data;
    await db.query(
      `
      INSERT INTO notification_preferences (
        user_id, enabled, radius_miles, categories, quiet_hours_enabled,
        quiet_start, quiet_end, timezone_offset_minutes, location_lat, location_lng, updated_at
      )
      VALUES ($1, $2, $3, $4::text[], $5, $6, $7, $8, $9, $10, $11)
      ON CONFLICT (user_id) DO UPDATE SET
        enabled = EXCLUDED.enabled,
        radius_miles = EXCLUDED.radius_miles,
        categories = EXCLUDED.categories,
        quiet_hours_enabled = EXCLUDED.quiet_hours_enabled,
        quiet_start = EXCLUDED.quiet_start,
        quiet_end = EXCLUDED.quiet_end,
        timezone_offset_minutes = EXCLUDED.timezone_offset_minutes,
        location_lat = EXCLUDED.location_lat,
        location_lng = EXCLUDED.location_lng,
        updated_at = EXCLUDED.updated_at
      `,
      [
        authUser.id,
        prefs.enabled,
        prefs.radiusMiles,
        prefs.categories,
        prefs.quietHoursEnabled,
        prefs.quietStart,
        prefs.quietEnd,
        prefs.timezoneOffsetMinutes,
        prefs.locationLat,
        prefs.locationLng,
        Date.now(),
      ]
    );

    return { item: prefs };
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
