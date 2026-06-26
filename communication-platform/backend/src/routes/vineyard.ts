import { FastifyInstance } from "fastify";
import { Pool } from "pg";
import { z } from "zod";
import { requireAuth } from "../auth/requireAuth.js";
import { badRequest } from "../lib/badRequest.js";
import { searchVineyard, resolveVineyardBoundary } from "../services/vineyardBoundaryService.js";

const searchSchema = z.object({
  name: z.string().min(1).max(200),
});

const analyzeSchema = z.object({
  // Chosen location (from a search candidate). The client picks; we don't re-geocode the name.
  center: z.object({ lat: z.number(), lng: z.number() }),
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
  // Step 1: name -> location candidates + researched info card.
  app.post("/v1/vineyard/search", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;

    const parsed = searchSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send(badRequest(parsed.error));

    try {
      return await searchVineyard(app.log, parsed.data.name.trim());
    } catch (error) {
      app.log.error({ error }, "Vineyard search failed");
      const message = error instanceof Error ? error.message : "Failed to search vineyard";
      return reply.code(502).send({ error: message });
    }
  });

  // Step 2: chosen center -> vine-area parcels.
  app.post("/v1/vineyard/analyze", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;

    const parsed = analyzeSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send(badRequest(parsed.error));

    try {
      const result = await resolveVineyardBoundary(
        app.log,
        { lat: parsed.data.center.lat, lng: parsed.data.center.lng },
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
