import { FastifyInstance } from "fastify";
import { Pool } from "pg";
import { z } from "zod";
import { requireAuth } from "../auth/requireAuth.js";
import { badRequest } from "../lib/badRequest.js";
import { assessVineyardDiseaseRisk } from "../services/grapeRiskService.js";

const querySchema = z.object({
  lat: z.coerce.number().min(-90).max(90),
  lng: z.coerce.number().min(-180).max(180),
  bloomDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  shootCm: z.coerce.number().min(0).max(400).optional(),
});

/**
 * Weather-driven grape disease infection-condition estimates for a vineyard, from the validated
 * models (Spotts black rot, Gubler-Thomas powdery, Erincik Phomopsis, 3-10/DMCast downy, Botrytis).
 *
 * This is decision support / scouting prioritization, not a spray recommendation — the response
 * carries that disclaimer. Assessment is at vineyard scale (the models need an hourly weather
 * series, which we have regionally), so the whole vineyard shares one assessment.
 */
export async function diseaseRiskRoutes(app: FastifyInstance, db: Pool) {
  app.get("/v1/vineyard/disease-risk", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;

    const parsed = querySchema.safeParse(req.query);
    if (!parsed.success) return reply.code(400).send(badRequest(parsed.error));

    try {
      const assessment = await assessVineyardDiseaseRisk(parsed.data.lat, parsed.data.lng, {
        bloomDateIso: parsed.data.bloomDate ?? null,
        shootLengthCm: parsed.data.shootCm,
      });
      if (!assessment) return reply.code(502).send({ error: "Weather data is temporarily unavailable" });
      return assessment;
    } catch (error) {
      app.log.error({ error }, "disease risk assessment failed");
      return reply.code(500).send({ error: "Failed to assess disease risk" });
    }
  });
}
