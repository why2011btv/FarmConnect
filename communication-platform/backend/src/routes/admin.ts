import { FastifyInstance } from "fastify";
import { Pool } from "pg";
import { z } from "zod";
import { requireAdmin } from "../auth/requireAdmin.js";
import { badRequest } from "../lib/badRequest.js";
import {
  MAX_NODES,
  issueAccessCode,
  provisionFarm,
  rotateDeviceKey,
} from "../services/provisioningService.js";
import { runSensorHealthCheck } from "../services/sensorHealthService.js";

const createFarmSchema = z.object({
  name: z.string().min(1).max(120),
  nodeCount: z.number().int().min(1).max(MAX_NODES).default(8),
  label: z.string().max(120).optional(),
  maxUses: z.number().int().positive().max(1000).optional(),
});

const createCodeSchema = z.object({
  label: z.string().max(120).optional(),
  maxUses: z.number().int().positive().max(1000).optional(),
  expiresInDays: z.number().int().positive().max(3650).optional(),
});

/**
 * Staff-only provisioning API, so customers can be onboarded from the app rather than over SSH.
 *
 * Everything that returns a secret returns it exactly once: only hashes are persisted, so a code
 * or ingest key that is not written down has to be reissued, never recovered.
 */
export async function adminRoutes(app: FastifyInstance, db: Pool) {
  app.get("/v1/admin/farms", async (req, reply) => {
    if (!(await requireAdmin(req, reply, db))) return;

    const { rows } = await db.query<{
      id: string;
      name: string;
      created_at: Date;
      device_count: string;
      member_count: string;
      online_count: string;
      active_code_count: string;
      last_seen_at: string | null;
    }>(
      `SELECT f.id,
              f.name,
              f.created_at,
              (SELECT COUNT(*)::TEXT FROM devices d WHERE d.farm_id = f.id) AS device_count,
              (SELECT COUNT(*)::TEXT FROM farm_members m WHERE m.farm_id = f.id) AS member_count,
              (SELECT COUNT(*)::TEXT FROM devices d WHERE d.farm_id = f.id AND d.status = 'online') AS online_count,
              (SELECT COUNT(*)::TEXT FROM farm_access_codes c
                 WHERE c.farm_id = f.id AND c.revoked_at IS NULL
                   AND (c.expires_at IS NULL OR c.expires_at > NOW())) AS active_code_count,
              (SELECT MAX(d.last_seen_at)::TEXT FROM devices d WHERE d.farm_id = f.id) AS last_seen_at
       FROM farms f
       ORDER BY f.created_at DESC`
    );

    return {
      items: rows.map((r) => ({
        id: r.id,
        name: r.name,
        createdAt: r.created_at.toISOString(),
        deviceCount: Number(r.device_count),
        memberCount: Number(r.member_count),
        onlineCount: Number(r.online_count),
        activeCodeCount: Number(r.active_code_count),
        lastSeenAt: r.last_seen_at ? Number(r.last_seen_at) : null,
      })),
    };
  });

  /** Onboards a customer: farm + N nodes + one access code. Secrets returned once. */
  app.post("/v1/admin/farms", async (req, reply) => {
    if (!(await requireAdmin(req, reply, db))) return;

    const parsed = createFarmSchema.safeParse(req.body ?? {});
    if (!parsed.success) return reply.code(400).send(badRequest(parsed.error));

    const name = parsed.data.name.trim();
    if (!name) return reply.code(400).send({ error: "Farm name is required" });

    try {
      const result = await provisionFarm(db, {
        name,
        nodeCount: parsed.data.nodeCount,
        label: parsed.data.label ?? null,
        maxUses: parsed.data.maxUses ?? null,
      });
      return {
        farm: { id: result.farmId, name: result.farmName },
        accessCode: result.accessCode,
        nodes: result.nodes.map((n) => ({
          id: n.id,
          name: n.name,
          locationLabel: n.locationLabel,
          ingestKey: n.ingestKey,
        })),
      };
    } catch (error) {
      app.log.error({ error }, "Farm provisioning failed");
      return reply.code(500).send({ error: "Failed to provision farm" });
    }
  });

  /** Farm detail: nodes, members and code metadata. Never any plaintext secret. */
  app.get("/v1/admin/farms/:farmId", async (req, reply) => {
    if (!(await requireAdmin(req, reply, db))) return;

    const { farmId } = req.params as { farmId: string };
    const farm = await db.query<{ id: string; name: string; created_at: Date }>(
      "SELECT id, name, created_at FROM farms WHERE id = $1",
      [farmId]
    );
    if (!farm.rows[0]) return reply.code(404).send({ error: "Farm not found" });

    const devices = await db.query<{
      id: string;
      name: string;
      location_label: string;
      status: string;
      last_seen_at: string;
      ingest_key_hash: string | null;
    }>(
      `SELECT id, name, location_label, status, last_seen_at, ingest_key_hash
       FROM devices WHERE farm_id = $1 ORDER BY name`,
      [farmId]
    );

    const members = await db.query<{
      id: string;
      name: string;
      email: string | null;
      role: string;
      joined_at: Date;
    }>(
      `SELECT u.id, u.name, u.email, m.role, m.joined_at
       FROM farm_members m JOIN users u ON u.id = m.user_id
       WHERE m.farm_id = $1 AND u.deleted_at IS NULL
       ORDER BY m.joined_at`,
      [farmId]
    );

    const codes = await db.query<{
      id: string;
      label: string | null;
      max_uses: number | null;
      use_count: number;
      created_at: Date;
      expires_at: Date | null;
      revoked_at: Date | null;
    }>(
      `SELECT id, label, max_uses, use_count, created_at, expires_at, revoked_at
       FROM farm_access_codes WHERE farm_id = $1 ORDER BY created_at DESC`,
      [farmId]
    );

    return {
      farm: {
        id: farm.rows[0].id,
        name: farm.rows[0].name,
        createdAt: farm.rows[0].created_at.toISOString(),
      },
      devices: devices.rows.map((d) => ({
        id: d.id,
        name: d.name,
        locationLabel: d.location_label,
        status: d.status,
        lastSeenAt: Number(d.last_seen_at),
        hasIngestKey: Boolean(d.ingest_key_hash),
      })),
      members: members.rows.map((m) => ({
        id: m.id,
        name: m.name,
        email: m.email,
        role: m.role,
        joinedAt: m.joined_at.toISOString(),
      })),
      codes: codes.rows.map((c) => ({
        id: c.id,
        label: c.label,
        maxUses: c.max_uses,
        useCount: c.use_count,
        createdAt: c.created_at.toISOString(),
        expiresAt: c.expires_at?.toISOString() ?? null,
        revokedAt: c.revoked_at?.toISOString() ?? null,
      })),
    };
  });

  /** Issues a replacement card for an existing farm. */
  app.post("/v1/admin/farms/:farmId/codes", async (req, reply) => {
    if (!(await requireAdmin(req, reply, db))) return;

    const { farmId } = req.params as { farmId: string };
    const parsed = createCodeSchema.safeParse(req.body ?? {});
    if (!parsed.success) return reply.code(400).send(badRequest(parsed.error));

    const farm = await db.query("SELECT id FROM farms WHERE id = $1", [farmId]);
    if (!farm.rows[0]) return reply.code(404).send({ error: "Farm not found" });

    const code = await issueAccessCode(db, farmId, {
      label: parsed.data.label ?? null,
      maxUses: parsed.data.maxUses ?? null,
      expiresInDays: parsed.data.expiresInDays ?? null,
    });
    return { code };
  });

  app.delete("/v1/admin/farms/:farmId/codes/:codeId", async (req, reply) => {
    if (!(await requireAdmin(req, reply, db))) return;

    const { farmId, codeId } = req.params as { farmId: string; codeId: string };
    await db.query(
      "UPDATE farm_access_codes SET revoked_at = NOW() WHERE id = $1 AND farm_id = $2 AND revoked_at IS NULL",
      [codeId, farmId]
    );
    return reply.code(204).send();
  });

  app.delete("/v1/admin/farms/:farmId/members/:userId", async (req, reply) => {
    if (!(await requireAdmin(req, reply, db))) return;

    const { farmId, userId } = req.params as { farmId: string; userId: string };
    await db.query("DELETE FROM farm_members WHERE farm_id = $1 AND user_id = $2", [farmId, userId]);
    return reply.code(204).send();
  });

  /** Open (and recently resolved) sensor health alerts across all farms. */
  app.get("/v1/admin/sensor-health", async (req, reply) => {
    if (!(await requireAdmin(req, reply, db))) return;

    const { rows } = await db.query<{
      id: string; device_id: string; farm_id: string | null; kind: string;
      sensor_type: string | null; severity: string; detail: string;
      sensor_value: number | null; reference_value: number | null;
      created_at: Date; updated_at: Date; resolved_at: Date | null; notified_at: Date | null;
      device_name: string | null; farm_name: string | null;
    }>(
      `SELECT a.*, d.name AS device_name, f.name AS farm_name
       FROM sensor_health_alerts a
       LEFT JOIN devices d ON d.id = a.device_id
       LEFT JOIN farms f ON f.id = a.farm_id
       WHERE a.resolved_at IS NULL OR a.resolved_at > NOW() - INTERVAL '7 days'
       ORDER BY (a.resolved_at IS NULL) DESC, a.severity DESC, a.updated_at DESC
       LIMIT 200`
    );
    return {
      items: rows.map((r) => ({
        id: r.id, deviceId: r.device_id, deviceName: r.device_name, farmName: r.farm_name,
        kind: r.kind, sensorType: r.sensor_type, severity: r.severity, detail: r.detail,
        sensorValue: r.sensor_value, referenceValue: r.reference_value,
        createdAt: r.created_at.toISOString(), updatedAt: r.updated_at.toISOString(),
        resolvedAt: r.resolved_at?.toISOString() ?? null,
        notifiedAt: r.notified_at?.toISOString() ?? null,
        open: r.resolved_at === null,
      })),
    };
  });

  /** Run a sensor-health sweep on demand (the scheduler also runs it periodically). */
  app.post("/v1/admin/sensor-health/check", async (req, reply) => {
    if (!(await requireAdmin(req, reply, db))) return;
    try {
      const summary = await runSensorHealthCheck(db, app.log);
      return summary;
    } catch (error) {
      app.log.error({ error }, "manual sensor health check failed");
      return reply.code(500).send({ error: "Health check failed" });
    }
  });

  /** New ingest key for one node, for a device that was lost, resold or reflashed. */
  app.post("/v1/admin/devices/:deviceId/rotate-key", async (req, reply) => {
    if (!(await requireAdmin(req, reply, db))) return;

    const { deviceId } = req.params as { deviceId: string };
    const key = await rotateDeviceKey(db, deviceId);
    if (!key) return reply.code(404).send({ error: "Device not found" });
    return { deviceId, ingestKey: key };
  });
}
