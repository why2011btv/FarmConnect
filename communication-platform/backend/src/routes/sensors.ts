import { FastifyInstance } from "fastify";
import { Pool } from "pg";
import { requireAuth } from "../auth/requireAuth.js";
import { SensorDeviceOverview } from "../types.js";

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

export async function sensorRoutes(app: FastifyInstance, db: Pool) {
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

    if (deviceRows.length === 0) return { items: [] as SensorDeviceOverview[] };

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

    return { items };
  });
}
