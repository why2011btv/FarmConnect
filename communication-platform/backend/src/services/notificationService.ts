import { FastifyBaseLogger } from "fastify";
import { Pool } from "pg";
import { sendApnsPush } from "./apnsService.js";
import { Category } from "../types.js";

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

type NearbyPreferenceRow = {
  user_id: string;
  radius_miles: number;
  categories: string[];
  quiet_hours_enabled: boolean;
  quiet_start: string;
  quiet_end: string;
  timezone_offset_minutes: number;
  location_lat: number | null;
  location_lng: number | null;
};

function haversineMiles(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const toRad = (value: number) => (value * Math.PI) / 180;
  const earthRadiusMiles = 3958.8;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2
    + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * earthRadiusMiles * Math.asin(Math.sqrt(a));
}

function isWithinQuietHours(
  nowUtcMs: number,
  timezoneOffsetMinutes: number,
  quietStart: string,
  quietEnd: string
): boolean {
  const parseMinutes = (hhmm: string) => {
    const [hh, mm] = hhmm.split(":").map((v) => Number(v));
    if (!Number.isFinite(hh) || !Number.isFinite(mm)) return null;
    if (hh < 0 || hh > 23 || mm < 0 || mm > 59) return null;
    return hh * 60 + mm;
  };
  const start = parseMinutes(quietStart);
  const end = parseMinutes(quietEnd);
  if (start == null || end == null) return false;

  const localMs = nowUtcMs + timezoneOffsetMinutes * 60 * 1000;
  const localDate = new Date(localMs);
  const localMinutes = localDate.getUTCHours() * 60 + localDate.getUTCMinutes();

  if (start === end) return false;
  if (start < end) {
    return localMinutes >= start && localMinutes < end;
  }
  return localMinutes >= start || localMinutes < end;
}

export async function queueNearbyPostNotifications(
  db: Pool,
  logger: FastifyBaseLogger,
  payload: {
    authorUserId: string;
    authorName: string;
    title: string;
    category: Category;
    lat: number;
    lng: number;
  }
) {
  const { rows } = await db.query<NearbyPreferenceRow>(
    `
    SELECT
      user_id, radius_miles, categories, quiet_hours_enabled,
      quiet_start, quiet_end, timezone_offset_minutes, location_lat, location_lng
    FROM notification_preferences
    WHERE enabled = TRUE
      AND user_id <> $1
    `,
    [payload.authorUserId]
  );

  if (!rows.length) return { attempted: 0, notified: 0 };

  let notified = 0;
  const now = Date.now();
  for (const pref of rows) {
    if (pref.location_lat == null || pref.location_lng == null) continue;
    if (!pref.categories.includes(payload.category)) continue;

    const distanceMiles = haversineMiles(
      pref.location_lat,
      pref.location_lng,
      payload.lat,
      payload.lng
    );
    if (distanceMiles > pref.radius_miles) continue;

    if (
      pref.quiet_hours_enabled
      && isWithinQuietHours(
        now,
        pref.timezone_offset_minutes,
        pref.quiet_start,
        pref.quiet_end
      )
    ) {
      continue;
    }

    await queuePushNotification(
      db,
      logger,
      pref.user_id,
      "New nearby post",
      `${payload.authorName}: ${payload.title}`
    );
    notified += 1;
  }

  return { attempted: rows.length, notified };
}
