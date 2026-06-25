import { FastifyInstance } from "fastify";
import { Pool } from "pg";
import { z } from "zod";
import { requireAuth } from "../auth/requireAuth.js";
import { badRequest } from "../lib/badRequest.js";
import { resolveVineyardBoundary } from "../services/vineyardBoundaryService.js";

const analyzeSchema = z.object({
  name: z.string().min(1).max(200),
  snapshot: z
    .object({
      imageDataUrl: z.string().min(1),
      region: z.object({
        centerLat: z.number(),
        centerLng: z.number(),
        latDelta: z.number().positive(),
        lngDelta: z.number().positive(),
      }),
    })
    .optional(),
});

export async function vineyardRoutes(app: FastifyInstance, db: Pool) {
  app.post("/v1/vineyard/analyze", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;

    const parsed = analyzeSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send(badRequest(parsed.error));

    try {
      const result = await resolveVineyardBoundary(
        app.log,
        parsed.data.name.trim(),
        parsed.data.snapshot
      );
      return result;
    } catch (error) {
      app.log.error({ error }, "Vineyard analyze failed");
      const message = error instanceof Error ? error.message : "Failed to analyze vineyard";
      return reply.code(502).send({ error: message });
    }
  });
}
