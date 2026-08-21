import { timingSafeEqual } from "node:crypto";
import { FastifyInstance } from "fastify";
import { Pool } from "pg";
import { z } from "zod";
import { requireAuth } from "../auth/requireAuth.js";
import { getUserFarmIds } from "../auth/farmAccess.js";
import { hashSecret } from "../lib/accessCode.js";
import { createId } from "../lib/id.js";
import { SensorDeviceOverview, SensorInsight } from "../types.js";
import { badRequest } from "../lib/badRequest.js";

type DeviceRow = {
  id: string;
  name: string;
  farm_name: string;
  location_label: string;
  status: "online" | "offline";
  last_seen_at: string;
};

/** Constant-time comparison of two hex digests of equal length. */
function hashesMatch(a: string, b: string): boolean {
  const left = Buffer.from(a, "hex");
  const right = Buffer.from(b, "hex");
  if (left.length !== right.length || left.length === 0) return false;
  return timingSafeEqual(left, right);
}

type ReadingRow = {
  device_id: string;
  sensor_type: string;
  value: number;
  unit: string;
  created_at: string;
};

const ingestReadingSchema = z.object({
  sensorType: z.string().min(1),
  value: z.number(),
  unit: z.string().min(1),
  createdAt: z.number().int().positive().optional(),
});

const ingestPayloadSchema = z.object({
  deviceId: z.string().min(1),
  deviceName: z.string().min(1),
  farmName: z.string().min(1),
  locationLabel: z.string().min(1),
  readings: z.array(ingestReadingSchema).min(1),
  status: z.enum(["online", "offline"]).optional(),
  deviceTimestamp: z.number().int().positive().optional(),
});

function buildInsights(items: SensorDeviceOverview[]): SensorInsight[] {
  const insights: SensorInsight[] = [];
  const now = Date.now();

  for (const device of items) {
    const readingMap = new Map(device.readings.map((r) => [r.sensorType, r]));

    if (device.status === "offline") {
      insights.push({
        id: `offline_${device.id}`,
        title: `${device.name} offline`,
        message: `No recent heartbeat from ${device.locationLabel}. Check power or network.`,
        severity: "high",
        deviceId: device.id,
        createdAt: now,
      });
    }

    // NOTE: previously this emitted agronomic prescriptions from single-threshold rules —
    // "temp>=30C -> irrigate", "humidity<40% -> monitor disease", "soil<30% -> irrigate".
    // Those are unsound for the humid, largely dry-farmed Northeast/Mid-Atlantic (30C is not heat
    // stress here; LOW humidity LOWERS fungal risk; prescribing irrigation off air temp adds vigor
    // and disease). They were removed pending validated, phenology-aware models. This endpoint now
    // reports only operational device status; disease pressure is shown per block in the app with a
    // clear "not a spray recommendation" disclaimer.
  }

  if (insights.length === 0 && items.length > 0) {
    insights.push({
      id: "stable_farm",
      title: "Conditions look stable",
      message: "No urgent sensor anomalies detected in the latest readings.",
      severity: "low",
      createdAt: now,
    });
  }

  return insights;
}

export async function sensorRoutes(app: FastifyInstance, db: Pool) {
  /**
   * Reading ingest from a field node.
   *
   * Preferred path is `x-device-key`: every shipped node carries its own secret, bound to a
   * pre-provisioned device row, so a key recovered from a node sitting in one customer's vineyard
   * cannot write readings for anybody else — and cannot invent new device ids.
   *
   * `x-sensor-key` is the original single shared key. It is kept working so nodes already in the
   * field keep reporting, but it can only write into the legacy farm and should be retired once
   * those nodes are reflashed with per-device keys. Leave SENSOR_INGEST_API_KEY unset to disable it.
   */
  app.post("/v1/sensors/ingest", async (req, reply) => {
    const parsed = ingestPayloadSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send(badRequest(parsed.error));

    const payload = parsed.data;
    const now = Date.now();
    const lastSeenAt = payload.deviceTimestamp ?? now;
    const status = payload.status ?? "online";

    const deviceKey = req.headers["x-device-key"] as string | undefined;
    const legacyKey = req.headers["x-sensor-key"] as string | undefined;
    const expectedLegacyKey = process.env.SENSOR_INGEST_API_KEY;

    if (deviceKey) {
      const { rows } = await db.query<{ ingest_key_hash: string | null }>(
        "SELECT ingest_key_hash FROM devices WHERE id = $1 LIMIT 1",
        [payload.deviceId]
      );
      const storedHash = rows[0]?.ingest_key_hash;
      // Same response for unknown device and wrong key, so the endpoint can't be used to
      // enumerate which device ids exist.
      if (!storedHash || !hashesMatch(hashSecret(deviceKey), storedHash)) {
        return reply.code(401).send({ error: "Invalid device credentials" });
      }

      // farm_id is deliberately not updatable from the payload — ownership is set at provisioning
      // time, never by the device itself.
      await db.query(
        `UPDATE devices
         SET name = $2, farm_name = $3, location_label = $4, status = $5, last_seen_at = $6
         WHERE id = $1`,
        [
          payload.deviceId,
          payload.deviceName,
          payload.farmName,
          payload.locationLabel,
          status,
          lastSeenAt,
        ]
      );
    } else if (legacyKey && expectedLegacyKey && legacyKey === expectedLegacyKey) {
      const legacyFarmId = process.env.LEGACY_FARM_ID ?? "farm_legacy";
      req.log.warn(
        { deviceId: payload.deviceId },
        "Sensor ingest used the shared legacy key; reflash this node with a per-device key"
      );

      // The shared key may only touch the legacy farm. Without this, it could overwrite a
      // customer's device by guessing its id.
      const existing = await db.query<{ farm_id: string }>(
        "SELECT farm_id FROM devices WHERE id = $1 LIMIT 1",
        [payload.deviceId]
      );
      if (existing.rows[0] && existing.rows[0].farm_id !== legacyFarmId) {
        return reply.code(401).send({ error: "Invalid device credentials" });
      }

      await db.query(
        `
        INSERT INTO devices (id, name, farm_name, location_label, status, last_seen_at, farm_id)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        ON CONFLICT (id) DO UPDATE SET
          name = EXCLUDED.name,
          farm_name = EXCLUDED.farm_name,
          location_label = EXCLUDED.location_label,
          status = EXCLUDED.status,
          last_seen_at = EXCLUDED.last_seen_at
        `,
        [
          payload.deviceId,
          payload.deviceName,
          payload.farmName,
          payload.locationLabel,
          status,
          lastSeenAt,
          legacyFarmId,
        ]
      );
    } else {
      return reply.code(401).send({ error: "Invalid device credentials" });
    }

    for (const reading of payload.readings) {
      await db.query(
        `
        INSERT INTO sensor_readings(id, device_id, sensor_type, value, unit, created_at)
        VALUES ($1, $2, $3, $4, $5, $6)
        `,
        [
          createId("sr"),
          payload.deviceId,
          reading.sensorType,
          reading.value,
          reading.unit,
          reading.createdAt ?? now,
        ]
      );
    }

    return {
      ok: true,
      deviceId: payload.deviceId,
      insertedReadings: payload.readings.length,
      receivedAt: now,
    };
  });

  app.get("/v1/sensors/overview", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;

    const maxAgeHours = Math.min(
      168,
      Math.max(1, Number((req.query as { maxAgeHours?: string }).maxAgeHours ?? 168))
    );
    const cutoffMs = Date.now() - maxAgeHours * 60 * 60 * 1000;

    // Tenancy boundary: a user only ever sees devices belonging to farms they have joined by
    // redeeming an access code. No membership means no devices, not all devices.
    const farmIds = await getUserFarmIds(db, authUser.id);
    if (farmIds.length === 0) {
      return { items: [] as SensorDeviceOverview[], insights: [] as SensorInsight[] };
    }

    const { rows: deviceRows } = await db.query<DeviceRow>(
      `
      SELECT id, name, farm_name, location_label, status, last_seen_at
      FROM devices
      WHERE last_seen_at >= $1
        AND farm_id = ANY($2::text[])
      ORDER BY name ASC
      `,
      [cutoffMs, farmIds]
    );

    if (deviceRows.length === 0) {
      return { items: [] as SensorDeviceOverview[], insights: [] as SensorInsight[] };
    }

    const ids = deviceRows.map((d) => d.id);
    const { rows: readingRows } = await db.query<ReadingRow>(
      `
      SELECT DISTINCT ON (device_id, sensor_type)
        device_id, sensor_type, value, unit, created_at
      FROM sensor_readings
      WHERE device_id = ANY($1::text[])
        AND created_at >= $2
      ORDER BY device_id, sensor_type, created_at DESC
      `,
      [ids, cutoffMs]
    );

    const readingsByDevice = new Map<string, ReadingRow[]>();
    for (const row of readingRows) {
      const list = readingsByDevice.get(row.device_id) ?? [];
      list.push(row);
      readingsByDevice.set(row.device_id, list);
    }

    const items: SensorDeviceOverview[] = deviceRows.map((d) => ({
      id: d.id,
      name: d.name,
      farmName: d.farm_name,
      locationLabel: d.location_label,
      status: d.status,
      lastSeenAt: Number(d.last_seen_at),
      readings: (readingsByDevice.get(d.id) ?? []).map((r) => ({
        sensorType: r.sensor_type,
        value: r.value,
        unit: r.unit,
        createdAt: Number(r.created_at),
      })),
    }));

    return { items, insights: buildInsights(items) };
  });
}
