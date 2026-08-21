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
import { aiRoutes } from "./routes/ai.js";
import { weatherRoutes } from "./routes/weather.js";
import { vineyardRoutes } from "./routes/vineyard.js";
import { farmRoutes } from "./routes/farms.js";
import { runSensorHealthCheck } from "./services/sensorHealthService.js";
import { adminRoutes } from "./routes/admin.js";

const app = Fastify({
  logger: true,
  bodyLimit: 10 * 1024 * 1024,
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
await weatherRoutes(app, pool);
await aiRoutes(app, pool);
await vineyardRoutes(app, pool);
await farmRoutes(app, pool);
await adminRoutes(app, pool);

// Periodic sensor-health sweep: alarms the ops team about faulty/silent nodes. Set
// SENSOR_HEALTH_CHECK_DISABLED=true to turn off. Interval is in-process (single Railway instance).
const healthIntervalMinutes = Number(process.env.SENSOR_HEALTH_CHECK_MINUTES ?? 120);
if (process.env.SENSOR_HEALTH_CHECK_DISABLED !== "true") {
  const sweep = () => {
    runSensorHealthCheck(pool, app.log).catch((error) =>
      app.log.error({ error }, "scheduled sensor health check failed")
    );
  };
  // First run shortly after boot, then on the interval.
  setTimeout(sweep, 30_000);
  setInterval(sweep, Math.max(15, healthIntervalMinutes) * 60_000);
}

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
