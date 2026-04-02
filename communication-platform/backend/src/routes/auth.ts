import { randomBytes } from "node:crypto";
import { FastifyInstance } from "fastify";
import { Pool } from "pg";
import { z } from "zod";

const loginSchema = z.object({
  name: z.string().min(1),
});

function createUserId() {
  return `u_${randomBytes(8).toString("hex")}`;
}

function createToken() {
  return randomBytes(24).toString("hex");
}

export async function authRoutes(app: FastifyInstance, db: Pool) {
  app.post("/v1/auth/login", async (req, reply) => {
    const parsed = loginSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.message });

    const name = parsed.data.name.trim();
    if (!name) return reply.code(400).send({ error: "Name is required" });

    let user = await db.query<{ id: string; name: string }>(
      "SELECT id, name FROM users WHERE LOWER(name) = LOWER($1) LIMIT 1",
      [name]
    );

    if (!user.rows[0]) {
      const id = createUserId();
      await db.query("INSERT INTO users(id, name) VALUES ($1, $2)", [id, name]);
      user = await db.query<{ id: string; name: string }>(
        "SELECT id, name FROM users WHERE id = $1",
        [id]
      );
    }

    const token = createToken();
    const expiresAt = new Date(Date.now() + 1000 * 60 * 60 * 24 * 30);
    await db.query(
      "INSERT INTO auth_sessions(token, user_id, expires_at) VALUES ($1, $2, $3)",
      [token, user.rows[0].id, expiresAt]
    );

    return {
      token,
      user: user.rows[0],
      expiresAt: expiresAt.toISOString(),
    };
  });

  app.get("/v1/auth/me", async (req, reply) => {
    const authHeader = req.headers.authorization;
    const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
    if (!token) return reply.code(401).send({ error: "Missing token" });

    const result = await db.query<{ id: string; name: string }>(
      `
      SELECT u.id, u.name
      FROM auth_sessions s
      JOIN users u ON u.id = s.user_id
      WHERE s.token = $1 AND s.expires_at > NOW()
      LIMIT 1
      `,
      [token]
    );
    if (!result.rows[0]) return reply.code(401).send({ error: "Invalid token" });
    return { user: result.rows[0] };
  });
}
