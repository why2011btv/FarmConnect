import { FastifyInstance } from "fastify";
import { Pool } from "pg";
import { z } from "zod";
import { requireAuth } from "../auth/requireAuth.js";
import { getFarmRole, requireFarmOwner, getUserFarmIds } from "../auth/farmAccess.js";
import { generateAccessCode, hashSecret, normalizeAccessCode } from "../lib/accessCode.js";
import { badRequest } from "../lib/badRequest.js";
import { checkRateLimit, clientBucket } from "../lib/rateLimit.js";
import { createId } from "../lib/id.js";

const claimSchema = z.object({
  code: z.string().min(1),
});

const createCodeSchema = z.object({
  label: z.string().max(120).optional(),
  maxUses: z.number().int().positive().max(1000).optional(),
  expiresInDays: z.number().int().positive().max(3650).optional(),
});

type FarmRow = {
  id: string;
  name: string;
  role: "owner" | "member";
  joined_at: Date;
  device_count: string;
};

export async function farmRoutes(app: FastifyInstance, db: Pool) {
  /** Farms the caller belongs to. An empty list is the app's cue to show the access-code screen. */
  app.get("/v1/farms", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;

    const { rows } = await db.query<FarmRow>(
      `SELECT f.id,
              f.name,
              m.role,
              m.joined_at,
              (SELECT COUNT(*)::TEXT FROM devices d WHERE d.farm_id = f.id) AS device_count
       FROM farm_members m
       JOIN farms f ON f.id = m.farm_id
       WHERE m.user_id = $1
       ORDER BY m.joined_at ASC`,
      [authUser.id]
    );

    return {
      items: rows.map((r) => ({
        id: r.id,
        name: r.name,
        role: r.role,
        joinedAt: r.joined_at.toISOString(),
        deviceCount: Number(r.device_count),
      })),
    };
  });

  /**
   * Redeems a farm access code, adding the caller to that farm.
   *
   * The code is an enrollment credential, not a password: it is exchanged once for durable
   * membership, so it never has to be stored on the customer's phone and revoking it later does
   * not lock out people who already joined.
   */
  app.post("/v1/farms/claim", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;

    const parsed = claimSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send(badRequest(parsed.error));

    const perUser = await checkRateLimit(db, `claim:${authUser.id}`, 10, 60 * 60);
    const perIp = await checkRateLimit(db, clientBucket("claim-ip", req.ip), 30, 60 * 60);
    if (!perUser || !perIp) {
      return reply.code(429).send({ error: "Too many attempts. Try again in an hour." });
    }

    // One flat response for every failure mode — unknown, revoked, expired, exhausted. Distinct
    // messages would tell an attacker when they had guessed a real farm's code.
    const invalid = () => reply.code(404).send({ error: "Invalid access code" });

    const normalized = normalizeAccessCode(parsed.data.code);
    if (!normalized) return invalid();

    const client = await db.connect();
    try {
      await client.query("BEGIN");

      // Lock the row so two people redeeming a max_uses-limited code at once cannot both pass
      // the use_count check.
      const { rows } = await client.query<{
        id: string;
        farm_id: string;
        max_uses: number | null;
        use_count: number;
      }>(
        `SELECT id, farm_id, max_uses, use_count
         FROM farm_access_codes
         WHERE code_hash = $1
           AND revoked_at IS NULL
           AND (expires_at IS NULL OR expires_at > NOW())
         LIMIT 1
         FOR UPDATE`,
        [hashSecret(normalized)]
      );

      const code = rows[0];
      if (!code || (code.max_uses !== null && code.use_count >= code.max_uses)) {
        await client.query("ROLLBACK");
        return invalid();
      }

      const existingRole = await getFarmRole(client, authUser.id, code.farm_id);

      // Re-redeeming when already a member is a no-op rather than an error: customers do retype
      // the code, and it should not burn a use or look like a failure.
      if (!existingRole) {
        await client.query(
          "INSERT INTO farm_members(farm_id, user_id, role) VALUES ($1, $2, 'member')",
          [code.farm_id, authUser.id]
        );
        await client.query(
          "UPDATE farm_access_codes SET use_count = use_count + 1 WHERE id = $1",
          [code.id]
        );
      }

      const farm = await client.query<{ id: string; name: string }>(
        "SELECT id, name FROM farms WHERE id = $1",
        [code.farm_id]
      );

      await client.query("COMMIT");

      return {
        farm: {
          id: farm.rows[0].id,
          name: farm.rows[0].name,
          role: existingRole ?? "member",
          alreadyMember: Boolean(existingRole),
        },
      };
    } catch (error) {
      await client.query("ROLLBACK");
      app.log.error({ error }, "Access code claim failed");
      return reply.code(500).send({ error: "Failed to redeem access code" });
    } finally {
      client.release();
    }
  });

  /** Access codes for a farm. Metadata only — the plaintext is unrecoverable by design. */
  app.get("/v1/farms/:farmId/codes", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;

    const { farmId } = req.params as { farmId: string };
    if (!(await requireFarmOwner(db, authUser.id, farmId))) {
      return reply.code(404).send({ error: "Farm not found" });
    }

    const { rows } = await db.query<{
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
      items: rows.map((r) => ({
        id: r.id,
        label: r.label,
        maxUses: r.max_uses,
        useCount: r.use_count,
        createdAt: r.created_at.toISOString(),
        expiresAt: r.expires_at?.toISOString() ?? null,
        revokedAt: r.revoked_at?.toISOString() ?? null,
      })),
    };
  });

  /** Mints a new access code. The plaintext is returned once here and never again. */
  app.post("/v1/farms/:farmId/codes", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;

    const { farmId } = req.params as { farmId: string };
    if (!(await requireFarmOwner(db, authUser.id, farmId))) {
      return reply.code(404).send({ error: "Farm not found" });
    }

    const parsed = createCodeSchema.safeParse(req.body ?? {});
    if (!parsed.success) return reply.code(400).send(badRequest(parsed.error));

    const code = generateAccessCode();
    const id = createId("fac");
    const expiresAt = parsed.data.expiresInDays
      ? new Date(Date.now() + parsed.data.expiresInDays * 24 * 60 * 60 * 1000)
      : null;

    await db.query(
      `INSERT INTO farm_access_codes(id, farm_id, code_hash, label, max_uses, expires_at)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [
        id,
        farmId,
        hashSecret(normalizeAccessCode(code)!),
        parsed.data.label ?? null,
        parsed.data.maxUses ?? null,
        expiresAt,
      ]
    );

    return { id, code, expiresAt: expiresAt?.toISOString() ?? null };
  });

  app.delete("/v1/farms/:farmId/codes/:codeId", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;

    const { farmId, codeId } = req.params as { farmId: string; codeId: string };
    if (!(await requireFarmOwner(db, authUser.id, farmId))) {
      return reply.code(404).send({ error: "Farm not found" });
    }

    await db.query(
      "UPDATE farm_access_codes SET revoked_at = NOW() WHERE id = $1 AND farm_id = $2 AND revoked_at IS NULL",
      [codeId, farmId]
    );
    return reply.code(204).send();
  });

  /** Members of a farm, so an owner can see who has access. */
  app.get("/v1/farms/:farmId/members", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;

    const { farmId } = req.params as { farmId: string };
    if (!(await getFarmRole(db, authUser.id, farmId))) {
      return reply.code(404).send({ error: "Farm not found" });
    }

    const { rows } = await db.query<{
      id: string;
      name: string;
      email: string | null;
      role: "owner" | "member";
      joined_at: Date;
    }>(
      `SELECT u.id, u.name, u.email, m.role, m.joined_at
       FROM farm_members m JOIN users u ON u.id = m.user_id
       WHERE m.farm_id = $1 AND u.deleted_at IS NULL
       ORDER BY m.joined_at ASC`,
      [farmId]
    );

    return {
      items: rows.map((r) => ({
        id: r.id,
        name: r.name,
        email: r.email,
        role: r.role,
        joinedAt: r.joined_at.toISOString(),
      })),
    };
  });

  /** Removes someone's access to a farm — the revoke path for a departed farmhand. */
  app.delete("/v1/farms/:farmId/members/:userId", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;

    const { farmId, userId } = req.params as { farmId: string; userId: string };
    if (!(await requireFarmOwner(db, authUser.id, farmId))) {
      return reply.code(404).send({ error: "Farm not found" });
    }

    const targetRole = await getFarmRole(db, userId, farmId);
    if (targetRole === "owner") {
      return reply.code(400).send({ error: "Cannot remove a farm owner" });
    }

    await db.query("DELETE FROM farm_members WHERE farm_id = $1 AND user_id = $2", [farmId, userId]);
    return reply.code(204).send();
  });
  /**
   * Sets coordinates for the caller's devices, from placing them on the vineyard map. Also makes
   * placement durable server-side and enables the weather-divergence health check for those nodes.
   */
  app.post("/v1/devices/locations", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;

    const parsed = z
      .object({
        locations: z
          .array(
            z.object({
              deviceId: z.string().min(1),
              latitude: z.number().min(-90).max(90),
              longitude: z.number().min(-180).max(180),
            })
          )
          .min(1)
          .max(500),
      })
      .safeParse(req.body);
    if (!parsed.success) return reply.code(400).send(badRequest(parsed.error));

    const farmIds = await getUserFarmIds(db, authUser.id);
    if (farmIds.length === 0) return reply.code(403).send({ error: "No farm access" });

    let updated = 0;
    for (const loc of parsed.data.locations) {
      // Only touch devices that belong to a farm the caller is a member of.
      const res = await db.query(
        `UPDATE devices SET latitude = $2, longitude = $3
         WHERE id = $1 AND farm_id = ANY($4::text[])`,
        [loc.deviceId, loc.latitude, loc.longitude, farmIds]
      );
      updated += res.rowCount ?? 0;
    }
    return { updated };
  });
}
