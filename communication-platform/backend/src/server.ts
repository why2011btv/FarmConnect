import "dotenv/config";
import multipart from "@fastify/multipart";
import fastifyStatic from "@fastify/static";
import cors from "@fastify/cors";
import sensible from "@fastify/sensible";
import Fastify from "fastify";
import { mkdirSync } from "node:fs";
import path from "node:path";
import { pool } from "./db.js";
import { ChatRepository } from "./repositories/chatRepository.js";
import { PostRepository } from "./repositories/postRepository.js";
import { authRoutes } from "./routes/auth.js";
import { chatRoutes } from "./routes/chats.js";
import { notificationRoutes } from "./routes/notifications.js";
import { postRoutes } from "./routes/posts.js";
import { sensorRoutes } from "./routes/sensors.js";
import { uploadRoutes } from "./routes/uploads.js";

const app = Fastify({
  logger: true,
});

await app.register(cors, {
  origin: true,
  credentials: false,
});

await app.register(sensible);
const uploadsRoot = path.resolve(process.cwd(), "uploads");
mkdirSync(uploadsRoot, { recursive: true });

await app.register(multipart, {
  limits: {
    fileSize: 5 * 1024 * 1024,
    files: 1,
  },
});
await app.register(fastifyStatic, {
  root: uploadsRoot,
  prefix: "/uploads/",
});

app.get("/health", async () => ({ ok: true, service: "communication-backend" }));
await authRoutes(app, pool);

const postRepository = new PostRepository(pool);
const chatRepository = new ChatRepository(pool);

await postRoutes(app, postRepository, pool);
await chatRoutes(app, chatRepository, pool);
await uploadRoutes(app, pool);
await notificationRoutes(app, pool);
await sensorRoutes(app, pool);

const port = Number(process.env.PORT ?? 4000);
const host = process.env.HOST ?? "0.0.0.0";

app.listen({ port, host }).catch((err) => {
  app.log.error(err);
  process.exit(1);
});

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.on(signal, async () => {
    await app.close();
    await pool.end();
    process.exit(0);
  });
}
