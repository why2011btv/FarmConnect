import cors from "@fastify/cors";
import sensible from "@fastify/sensible";
import Fastify from "fastify";
import { pool } from "./db.js";
import { ChatRepository } from "./repositories/chatRepository.js";
import { PostRepository } from "./repositories/postRepository.js";
import { authRoutes } from "./routes/auth.js";
import { chatRoutes } from "./routes/chats.js";
import { notificationRoutes } from "./routes/notifications.js";
import { postRoutes } from "./routes/posts.js";
import { uploadRoutes } from "./routes/uploads.js";

const app = Fastify({
  logger: true,
});

await app.register(cors, {
  origin: true,
  credentials: false,
});

await app.register(sensible);

app.get("/health", async () => ({ ok: true, service: "communication-backend" }));
await authRoutes(app, pool);

const postRepository = new PostRepository(pool);
const chatRepository = new ChatRepository(pool);

await postRoutes(app, postRepository, pool);
await chatRoutes(app, chatRepository, pool);
await app.register(uploadRoutes);
await notificationRoutes(app, pool);

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
