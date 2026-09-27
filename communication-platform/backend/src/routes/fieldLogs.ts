import { FastifyInstance } from "fastify";
import { Pool } from "pg";
import { z } from "zod";
import { requireAuth } from "../auth/requireAuth.js";
import { getFarmRole } from "../auth/farmAccess.js";
import { badRequest } from "../lib/badRequest.js";
import { createId } from "../lib/id.js";

const createSchema = z.object({
  kind: z.enum(["Spray", "Scouting", "General"]),
  createdAt: z.number().int().positive().optional(),
  blockId: z.string().max(100).optional(),
  blockName: z.string().max(100).optional(),
  locationDetail: z.string().min(1).max(300),
  grapeVariety: z.string().max(100).default(""),
  title: z.string().min(1).max(200),
  notes: z.string().max(2000).default(""),
  product: z.string().max(200).optional(),
  applicationRate: z.string().max(200).optional(),
  issueType: z.string().max(200).optional(),
  severity: z.number().int().min(1).max(5).optional(),
});

type FieldLogRow = {
  id: string; kind: "Spray" | "Scouting" | "General"; created_at: string;
  block_id: string | null; block_name: string | null; location_detail: string;
  grape_variety: string; title: string; notes: string; product: string | null;
  application_rate: string | null; issue_type: string | null; severity: number | null;
};

function toItem(row: FieldLogRow) {
  return {
    id: row.id,
    kind: row.kind,
    createdAt: new Date(row.created_at).getTime(),
    blockId: row.block_id,
    blockName: row.block_name,
    locationDetail: row.location_detail,
    grapeVariety: row.grape_variety,
    title: row.title,
    notes: row.notes,
    product: row.product,
    applicationRate: row.application_rate,
    issueType: row.issue_type,
    severity: row.severity,
  };
}

async function farmMember(db: Pool, userId: string, farmId: string) {
  return (await getFarmRole(db, userId, farmId)) != null;
}

/** Shared, farm-scoped spray/scouting/general records. */
export async function fieldLogRoutes(app: FastifyInstance, db: Pool) {
  app.get("/v1/farms/:farmId/field-logs", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;
    const { farmId } = req.params as { farmId: string };
    if (!(await farmMember(db, authUser.id, farmId))) return reply.code(404).send({ error: "Farm not found" });
    const { rows } = await db.query<FieldLogRow>(
      `SELECT id, kind, created_at, block_id, block_name, location_detail, grape_variety,
              title, notes, product, application_rate, issue_type, severity
         FROM field_logs WHERE farm_id = $1 ORDER BY created_at DESC`,
      [farmId]
    );
    return { items: rows.map(toItem) };
  });

  app.post("/v1/farms/:farmId/field-logs", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;
    const { farmId } = req.params as { farmId: string };
    if (!(await farmMember(db, authUser.id, farmId))) return reply.code(404).send({ error: "Farm not found" });
    const parsed = createSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send(badRequest(parsed.error));
    const d = parsed.data;
    const id = createId("fl");
    await db.query(
      `INSERT INTO field_logs
       (id, farm_id, user_id, kind, created_at, block_id, block_name, location_detail,
        grape_variety, title, notes, product, application_rate, issue_type, severity)
       VALUES ($1,$2,$3,$4,COALESCE(to_timestamp($5 / 1000.0), NOW()),$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)`,
      [id, farmId, authUser.id, d.kind, d.createdAt ?? Date.now(), d.blockId ?? null, d.blockName ?? null,
        d.locationDetail, d.grapeVariety, d.title, d.notes, d.product ?? null, d.applicationRate ?? null,
        d.issueType ?? null, d.severity ?? null]
    );
    return { id };
  });

  app.delete("/v1/farms/:farmId/field-logs/:id", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;
    const { farmId, id } = req.params as { farmId: string; id: string };
    if (!(await farmMember(db, authUser.id, farmId))) return reply.code(404).send({ error: "Farm not found" });
    const result = await db.query("DELETE FROM field_logs WHERE id = $1 AND farm_id = $2", [id, farmId]);
    if (result.rowCount === 0) return reply.code(404).send({ error: "Field log not found" });
    return reply.code(204).send();
  });
}
