import { FastifyInstance } from "fastify";
import { Pool } from "pg";
import { z } from "zod";
import { requireAuth } from "../auth/requireAuth.js";
import { getFarmRole } from "../auth/farmAccess.js";
import { badRequest } from "../lib/badRequest.js";
import { createId } from "../lib/id.js";

const createSchema = z.object({
  sampledOn: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  blockLabel: z.string().max(80).optional(),
  brix: z.number().min(0).max(40).optional(),
  titratableAcidity: z.number().min(0).max(30).optional(),
  ph: z.number().min(2).max(5).optional(),
  notes: z.string().max(1000).optional(),
});

/** Fruit-chemistry sampling log per farm. Any farm member can read/write. */
export async function harvestRoutes(app: FastifyInstance, db: Pool) {
  app.get("/v1/farms/:farmId/fruit-samples", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;
    const { farmId } = req.params as { farmId: string };
    if (!(await getFarmRole(db, authUser.id, farmId))) return reply.code(404).send({ error: "Farm not found" });

    const { rows } = await db.query<{
      id: string; block_label: string | null; sampled_on: string;
      brix: number | null; titratable_acidity: number | null; ph: number | null;
      notes: string | null;
    }>(
      `SELECT id, block_label, to_char(sampled_on,'YYYY-MM-DD') AS sampled_on, brix, titratable_acidity, ph, notes
       FROM fruit_samples WHERE farm_id = $1 ORDER BY sampled_on ASC, created_at ASC`,
      [farmId]
    );
    return {
      items: rows.map((r) => ({
        id: r.id, blockLabel: r.block_label, sampledOn: r.sampled_on,
        brix: r.brix, titratableAcidity: r.titratable_acidity, ph: r.ph, notes: r.notes,
      })),
    };
  });

  app.post("/v1/farms/:farmId/fruit-samples", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;
    const { farmId } = req.params as { farmId: string };
    if (!(await getFarmRole(db, authUser.id, farmId))) return reply.code(404).send({ error: "Farm not found" });

    const parsed = createSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send(badRequest(parsed.error));
    const d = parsed.data;
    const id = createId("fs");
    await db.query(
      `INSERT INTO fruit_samples(id, farm_id, user_id, block_label, sampled_on, brix, titratable_acidity, ph, notes)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
      [id, farmId, authUser.id, d.blockLabel ?? null, d.sampledOn, d.brix ?? null, d.titratableAcidity ?? null, d.ph ?? null, d.notes ?? null]
    );
    return { id };
  });

  app.delete("/v1/farms/:farmId/fruit-samples/:id", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;
    const { farmId, id } = req.params as { farmId: string; id: string };
    if (!(await getFarmRole(db, authUser.id, farmId))) return reply.code(404).send({ error: "Farm not found" });
    await db.query("DELETE FROM fruit_samples WHERE id = $1 AND farm_id = $2", [id, farmId]);
    return reply.code(204).send();
  });
}
