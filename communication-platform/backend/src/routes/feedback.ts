import { randomUUID } from "node:crypto";
import { FastifyInstance } from "fastify";
import { Pool } from "pg";
import { z } from "zod";
import { requireAuth } from "../auth/requireAuth.js";
import { badRequest } from "../lib/badRequest.js";

const feedbackSchema = z.object({
  category: z.enum(["Bug", "Idea", "Question", "Other"]),
  rating: z.number().int().min(1).max(5),
  message: z.string().trim().min(3).max(2_000),
  appVersion: z.string().trim().max(50).optional(),
  buildNumber: z.string().trim().max(50).optional(),
  osVersion: z.string().trim().max(100).optional(),
  deviceModel: z.string().trim().max(100).optional(),
});

export async function feedbackRoutes(app: FastifyInstance, db: Pool) {
  app.post("/v1/feedback", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;

    const parsed = feedbackSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send(badRequest(parsed.error));

    const feedback = parsed.data;
    const id = `feedback_${randomUUID()}`;
    const { rows } = await db.query<{ id: string; created_at: Date }>(
      `
      INSERT INTO user_feedback (
        id, user_id, category, rating, message,
        app_version, build_number, os_version, device_model
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
      RETURNING id, created_at
      `,
      [
        id,
        authUser.id,
        feedback.category,
        feedback.rating,
        feedback.message,
        feedback.appVersion ?? null,
        feedback.buildNumber ?? null,
        feedback.osVersion ?? null,
        feedback.deviceModel ?? null,
      ]
    );

    return reply.code(201).send({
      item: {
        id: rows[0].id,
        createdAt: rows[0].created_at.toISOString(),
      },
    });
  });
}
