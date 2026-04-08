import { randomBytes } from "node:crypto";
import path from "node:path";
import { FastifyInstance } from "fastify";
import { Pool } from "pg";
import { z } from "zod";
import { requireAuth } from "../auth/requireAuth.js";
import { isR2Configured, uploadImageToR2 } from "../services/r2Storage.js";

const createUploadSchema = z.object({
  fileName: z.string().min(1),
  mimeType: z.string().min(1),
});

export async function uploadRoutes(app: FastifyInstance, db: Pool) {
  app.post("/v1/uploads/create", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;

    const parsed = createUploadSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.message });

    // Placeholder for signed URL generation (S3/Supabase Storage/GCS).
    // Replace with storage provider SDK logic in next iteration.
    const { fileName } = parsed.data;
    return {
      uploadUrl: `https://example-upload.invalid/${encodeURIComponent(fileName)}`,
      publicUrl: `https://cdn.example.invalid/${encodeURIComponent(fileName)}`,
      expiresInSeconds: 600,
    };
  });

  app.post("/v1/uploads/image", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;

    const file = await req.file();
    if (!file) return reply.code(400).send({ error: "Missing file" });

    if (!file.mimetype.startsWith("image/")) {
      return reply.code(400).send({ error: "Only image files are supported" });
    }

    const buffer = await file.toBuffer();
    if (buffer.byteLength > 5 * 1024 * 1024) {
      return reply.code(400).send({ error: "Image exceeds 5MB limit" });
    }

    const ext = path.extname(file.filename || "").toLowerCase() || ".jpg";
    const objectKey = `${Date.now()}_${randomBytes(6).toString("hex")}${ext}`;

    if (!isR2Configured()) {
      return reply.code(500).send({
        error: "Image storage is not configured. Set R2_* environment variables.",
      });
    }

    const publicUrl = await uploadImageToR2(objectKey, buffer, file.mimetype);

    return {
      publicUrl,
      size: buffer.byteLength,
      mimeType: file.mimetype,
    };
  });
}
