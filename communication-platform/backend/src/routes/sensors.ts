import { FastifyInstance } from "fastify";
import { Pool } from "pg";
import { z } from "zod";
import { requireAuth } from "../auth/requireAuth.js";
import { createId } from "../lib/id.js";
import { SensorDeviceOverview, SensorInsight } from "../types.js";

type DeviceRow = {
  id: string;
  name: string;
  farm_name: string;
  location_label: string;
  status: "online" | "offline";
  last_seen_at: string;
};

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

    const temp = readingMap.get("temperature");
    if (temp && temp.value >= 30) {
      insights.push({
        id: `temp_${device.id}`,
        title: `Heat stress risk at ${device.name}`,
        message: `Temperature is ${temp.value.toFixed(1)}${temp.unit}. Consider irrigation timing or shading.`,
        severity: temp.value >= 34 ? "high" : "medium",
        deviceId: device.id,
        createdAt: now,
      });
    }

    const moisture = readingMap.get("soil_moisture");
    if (moisture && moisture.value < 30) {
      insights.push({
        id: `soil_${device.id}`,
        title: `Low soil moisture at ${device.name}`,
        message: `Soil moisture is ${moisture.value.toFixed(1)}${moisture.unit}. Irrigation is recommended soon.`,
        severity: moisture.value < 20 ? "high" : "medium",
        deviceId: device.id,
        createdAt: now,
      });
    }

    const humidity = readingMap.get("humidity");
    if (humidity && humidity.value < 40) {
      insights.push({
        id: `humidity_${device.id}`,
        title: `Low humidity at ${device.name}`,
        message: `Humidity is ${humidity.value.toFixed(1)}${humidity.unit}. Monitor disease and transpiration risk.`,
        severity: "low",
        deviceId: device.id,
        createdAt: now,
      });
    }
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
  app.post("/v1/sensors/ingest", async (req, reply) => {
    const expectedKey = process.env.SENSOR_INGEST_API_KEY;
    if (!expectedKey) {
      return reply.code(500).send({ error: "Sensor ingest is not configured. Set SENSOR_INGEST_API_KEY." });
    }

    const providedKey = (req.headers["x-sensor-key"] as string | undefined)
      ?? (req.headers["x-device-key"] as string | undefined);
    if (!providedKey || providedKey !== expectedKey) {
      return reply.code(401).send({ error: "Invalid sensor ingest key" });
    }

    const parsed = ingestPayloadSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.message });

    const payload = parsed.data;
    const now = Date.now();
    const lastSeenAt = payload.deviceTimestamp ?? now;
    const status = payload.status ?? "online";

    await db.query(
      `
      INSERT INTO devices (id, name, farm_name, location_label, status, last_seen_at)
      VALUES ($1, $2, $3, $4, $5, $6)
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
      ]
    );

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

    const { rows: deviceRows } = await db.query<DeviceRow>(
      `
      SELECT id, name, farm_name, location_label, status, last_seen_at
      FROM devices
      ORDER BY name ASC
      `
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
      ORDER BY device_id, sensor_type, created_at DESC
      `,
      [ids]
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
