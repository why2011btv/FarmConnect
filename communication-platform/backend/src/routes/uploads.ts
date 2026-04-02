import { FastifyInstance } from "fastify";
import { z } from "zod";

const createUploadSchema = z.object({
  fileName: z.string().min(1),
  mimeType: z.string().min(1),
});

export async function uploadRoutes(app: FastifyInstance) {
  app.post("/v1/uploads/create", async (req, reply) => {
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
}
