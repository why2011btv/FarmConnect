import { readFile } from "node:fs/promises";
import path from "node:path";
import { FastifyInstance } from "fastify";
import { Pool } from "pg";
import { z } from "zod";
import { requirePartnerAuth } from "../auth/partnerAuth.js";
import {
  csvCell,
  findPartnerFarm,
  getDailyMetrics,
  PARTNER_FARMS,
  publicDeviceId,
  recommendationsFromDailyMetrics,
} from "../services/partnerDataService.js";

const DAY_MS = 24 * 60 * 60 * 1000;

const rangeSchema = z.object({
  from: z.coerce.number().int().positive().optional(),
  to: z.coerce.number().int().positive().optional(),
});

function rangeFor(query: unknown, startAt: number) {
  const parsed = rangeSchema.safeParse(query);
  if (!parsed.success) return null;
  const from = Math.max(startAt, parsed.data.from ?? startAt);
  const to = Math.min(Date.now() + DAY_MS, parsed.data.to ?? Date.now() + 1);
  return to > from ? { from, to } : null;
}

function publicFarm(farm: (typeof PARTNER_FARMS)[number]) {
  return { key: farm.key, label: farm.label, startDate: farm.startDate, startAt: farm.startAt };
}

function apiKeyOk(req: Parameters<typeof requirePartnerAuth>[0], reply: Parameters<typeof requirePartnerAuth>[1]) {
  return requirePartnerAuth(req, reply);
}

export async function partnerRoutes(app: FastifyInstance, db: Pool) {
  app.get("/partner", async (_req, reply) => {
    const html = await readFile(path.resolve(process.cwd(), "public/partner.html"), "utf8");
    return reply.type("text/html; charset=utf-8").send(html);
  });

  app.get("/v1/partner/openapi.json", async (req, reply) => {
    if (!apiKeyOk(req, reply)) return;
    const serverUrl = `${req.protocol}://${req.host}`;
    return {
      openapi: "3.1.0",
      info: {
        title: "Persephone's Basket Partner Data API",
        version: "1.0.0",
        description:
          "Read-only access to consented, pseudonymized farm sensor readings and transparent decision-support recommendations.",
      },
      servers: [{ url: serverUrl }],
      components: {
        securitySchemes: {
          PartnerApiKey: { type: "apiKey", in: "header", name: "x-partner-api-key" },
        },
      },
      security: [{ PartnerApiKey: [] }],
      paths: {
        "/v1/partner/farms": { get: { summary: "List authorized farms" } },
        "/v1/partner/farms/{farmKey}/summary": {
          get: { summary: "Farm summary, latest readings, and daily aggregates" },
        },
        "/v1/partner/farms/{farmKey}/readings": {
          get: { summary: "Paginated raw sensor readings" },
        },
        "/v1/partner/farms/{farmKey}/recommendations": {
          get: { summary: "Transparent recommendations derived from daily sensor metrics" },
        },
        "/v1/partner/farms/{farmKey}/readings.csv": {
          get: { summary: "Download all in-range readings as CSV" },
        },
        "/v1/partner/farms/{farmKey}/recommendations.csv": {
          get: { summary: "Download all in-range recommendations as CSV" },
        },
      },
    };
  });

  app.get("/v1/partner/farms", async (req, reply) => {
    if (!apiKeyOk(req, reply)) return;
    return { farms: PARTNER_FARMS.map(publicFarm) };
  });

  app.get("/v1/partner/farms/:farmKey/summary", async (req, reply) => {
    if (!apiKeyOk(req, reply)) return;
    const farm = findPartnerFarm((req.params as { farmKey: string }).farmKey);
    if (!farm) return reply.code(404).send({ error: "Farm not found" });
    const range = rangeFor(req.query, farm.startAt);
    if (!range) return reply.code(400).send({ error: "Invalid date range" });

    const [daily, deviceResult, countResult] = await Promise.all([
      getDailyMetrics(db, farm, range.from, range.to),
      db.query<{
        id: string; name: string; location_label: string; status: string; last_seen_at: string;
        sensor_type: string | null; value: number | null; unit: string | null; created_at: string | null;
      }>(
        `SELECT d.id, d.name, d.location_label, d.status, d.last_seen_at,
                latest.sensor_type, latest.value, latest.unit, latest.created_at
         FROM devices d
         LEFT JOIN LATERAL (
           SELECT DISTINCT ON (sensor_type) sensor_type, value, unit, created_at
           FROM sensor_readings
           WHERE device_id = d.id AND created_at >= $2 AND created_at < $3
           ORDER BY sensor_type, created_at DESC
         ) latest ON TRUE
         WHERE d.farm_id = $1
         ORDER BY d.name, latest.sensor_type`,
        [farm.farmId, range.from, range.to]
      ),
      db.query<{ readings: string; devices_reporting: string; first_at: string | null; last_at: string | null }>(
        `SELECT COUNT(sr.*)::text AS readings, COUNT(DISTINCT sr.device_id)::text AS devices_reporting,
                MIN(sr.created_at)::text AS first_at, MAX(sr.created_at)::text AS last_at
         FROM sensor_readings sr JOIN devices d ON d.id = sr.device_id
         WHERE d.farm_id = $1 AND sr.created_at >= $2 AND sr.created_at < $3`,
        [farm.farmId, range.from, range.to]
      ),
    ]);

    const devices = new Map<string, {
      id: string; name: string; block: string; status: string; lastSeenAt: number; readings: Record<string, unknown>;
    }>();
    for (const row of deviceResult.rows) {
      const item = devices.get(row.id) ?? {
        id: publicDeviceId(farm, row.id, row.name),
        name: row.name,
        block: row.location_label,
        status: row.status,
        lastSeenAt: Number(row.last_seen_at),
        readings: {},
      };
      if (row.sensor_type && row.value != null && row.created_at) {
        item.readings[row.sensor_type] = {
          value: Number(row.value), unit: row.unit, createdAt: Number(row.created_at),
        };
      }
      devices.set(row.id, item);
    }
    const counts = countResult.rows[0];
    const recommendations = recommendationsFromDailyMetrics(farm, daily);
    return {
      farm: publicFarm(farm),
      range,
      totals: {
        readings: Number(counts.readings),
        devicesReporting: Number(counts.devices_reporting),
        firstReadingAt: counts.first_at ? Number(counts.first_at) : null,
        lastReadingAt: counts.last_at ? Number(counts.last_at) : null,
        recommendations: recommendations.length,
      },
      devices: [...devices.values()],
      daily,
      latestRecommendations: recommendations.slice(0, 8),
      methodology: {
        timezone: "America/New_York",
        privacy: "Farm identities are pseudonymized for this partner view.",
        limitation: "Temperature, humidity, and leaf-wetness sensors do not measure soil nutrients.",
      },
    };
  });

  app.get("/v1/partner/farms/:farmKey/readings", async (req, reply) => {
    if (!apiKeyOk(req, reply)) return;
    const farm = findPartnerFarm((req.params as { farmKey: string }).farmKey);
    if (!farm) return reply.code(404).send({ error: "Farm not found" });
    const range = rangeFor(req.query, farm.startAt);
    if (!range) return reply.code(400).send({ error: "Invalid date range" });
    const q = req.query as { limit?: string; offset?: string };
    const limit = Math.min(5000, Math.max(1, Number(q.limit ?? 1000)));
    const offset = Math.max(0, Number(q.offset ?? 0));
    if (!Number.isInteger(limit) || !Number.isInteger(offset)) {
      return reply.code(400).send({ error: "limit and offset must be integers" });
    }
    const { rows } = await db.query<{
      id: string; device_id: string; device_name: string; location_label: string;
      sensor_type: string; value: number; unit: string; created_at: string;
    }>(
      `SELECT sr.id, sr.device_id, d.name AS device_name, d.location_label,
              sr.sensor_type, sr.value, sr.unit, sr.created_at
       FROM sensor_readings sr JOIN devices d ON d.id = sr.device_id
       WHERE d.farm_id = $1 AND sr.created_at >= $2 AND sr.created_at < $3
       ORDER BY sr.created_at ASC, sr.id ASC LIMIT $4 OFFSET $5`,
      [farm.farmId, range.from, range.to, limit, offset]
    );
    return {
      farm: publicFarm(farm), range, limit, offset,
      items: rows.map((row) => ({
        id: row.id, deviceId: publicDeviceId(farm, row.device_id, row.device_name), deviceName: row.device_name,
        block: row.location_label, sensorType: row.sensor_type, value: Number(row.value),
        unit: row.unit, recordedAt: Number(row.created_at),
      })),
    };
  });

  app.get("/v1/partner/farms/:farmKey/recommendations", async (req, reply) => {
    if (!apiKeyOk(req, reply)) return;
    const farm = findPartnerFarm((req.params as { farmKey: string }).farmKey);
    if (!farm) return reply.code(404).send({ error: "Farm not found" });
    const range = rangeFor(req.query, farm.startAt);
    if (!range) return reply.code(400).send({ error: "Invalid date range" });
    const daily = await getDailyMetrics(db, farm, range.from, range.to);
    return { farm: publicFarm(farm), range, items: recommendationsFromDailyMetrics(farm, daily) };
  });

  app.get("/v1/partner/farms/:farmKey/readings.csv", async (req, reply) => {
    if (!apiKeyOk(req, reply)) return;
    const farm = findPartnerFarm((req.params as { farmKey: string }).farmKey);
    if (!farm) return reply.code(404).send({ error: "Farm not found" });
    const range = rangeFor(req.query, farm.startAt);
    if (!range) return reply.code(400).send({ error: "Invalid date range" });
    const { rows } = await db.query<{
      id: string; device_id: string; device_name: string; location_label: string;
      sensor_type: string; value: number; unit: string; created_at: string;
    }>(
      `SELECT sr.id, sr.device_id, d.name AS device_name, d.location_label,
              sr.sensor_type, sr.value, sr.unit, sr.created_at
       FROM sensor_readings sr JOIN devices d ON d.id = sr.device_id
       WHERE d.farm_id = $1 AND sr.created_at >= $2 AND sr.created_at < $3
       ORDER BY sr.created_at ASC, sr.id ASC LIMIT 250000`,
      [farm.farmId, range.from, range.to]
    );
    const lines = ["farm,date_time_utc,timestamp_ms,device_id,device_name,block,sensor_type,value,unit"];
    for (const row of rows) {
      lines.push([
        farm.label, new Date(Number(row.created_at)).toISOString(), row.created_at,
        publicDeviceId(farm, row.device_id, row.device_name),
        row.device_name, row.location_label, row.sensor_type, row.value, row.unit,
      ].map(csvCell).join(","));
    }
    return reply
      .header("content-disposition", `attachment; filename="${farm.key}-sensor-readings.csv"`)
      .type("text/csv; charset=utf-8")
      .send(lines.join("\n") + "\n");
  });

  app.get("/v1/partner/farms/:farmKey/recommendations.csv", async (req, reply) => {
    if (!apiKeyOk(req, reply)) return;
    const farm = findPartnerFarm((req.params as { farmKey: string }).farmKey);
    if (!farm) return reply.code(404).send({ error: "Farm not found" });
    const range = rangeFor(req.query, farm.startAt);
    if (!range) return reply.code(400).send({ error: "Invalid date range" });
    const items = recommendationsFromDailyMetrics(farm, await getDailyMetrics(db, farm, range.from, range.to));
    const lines = ["farm,date,severity,category,title,recommendation,evidence,disclaimer"];
    for (const item of items) {
      lines.push([
        farm.label, item.date, item.severity, item.category, item.title,
        item.recommendation, item.evidence, item.disclaimer,
      ].map(csvCell).join(","));
    }
    return reply
      .header("content-disposition", `attachment; filename="${farm.key}-recommendations.csv"`)
      .type("text/csv; charset=utf-8")
      .send(lines.join("\n") + "\n");
  });
}
