import { randomBytes } from "node:crypto";
import { FastifyInstance } from "fastify";
import { Pool } from "pg";
import { z } from "zod";
import { compare, hash } from "bcryptjs";

const loginSchema = z.object({
  username: z.string().min(1),
  password: z.string().min(6),
  displayName: z.string().min(1).optional(),
});

function createUserId() {
  return `u_${randomBytes(8).toString("hex")}`;
}

function createToken() {
  return randomBytes(24).toString("hex");
}

function normalizeUsername(username: string): string {
  const normalized = username
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_]/g, "_")
    .replace(/_+/g, "_")
    .replace(/^_+|_+$/g, "");
  return normalized;
}

export async function authRoutes(app: FastifyInstance, db: Pool) {
  app.post("/v1/auth/login", async (req, reply) => {
    const parsed = loginSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.message });

    const username = normalizeUsername(parsed.data.username);
    const password = parsed.data.password;
    const displayName = parsed.data.displayName?.trim();
    if (!username) return reply.code(400).send({ error: "Username is required" });
    if (!password) return reply.code(400).send({ error: "Password is required" });

    let user = await db.query<{ id: string; name: string; username: string; password_hash: string | null }>(
      "SELECT id, name, username, password_hash FROM users WHERE username = $1 LIMIT 1",
      [username]
    );

    // Backward compatibility for older clients that still type display name in the username box.
    if (!user.rows[0]) {
      const fallback = await db.query<{ id: string; name: string; username: string; password_hash: string | null }>(
        "SELECT id, name, username, password_hash FROM users WHERE LOWER(name) = LOWER($1)",
        [parsed.data.username.trim()]
      );
      if (fallback.rows.length === 1) {
        user = { ...fallback, rows: [fallback.rows[0]] };
      }
    }

    if (!user.rows[0]) {
      const id = createUserId();
      const passwordHash = await hash(password, 12);
      await db.query(
        "INSERT INTO users(id, name, username, password_hash) VALUES ($1, $2, $3, $4)",
        [id, displayName || username, username, passwordHash]
      );
      user = await db.query<{ id: string; name: string; username: string; password_hash: string | null }>(
        "SELECT id, name, username, password_hash FROM users WHERE id = $1",
        [id]
      );
    } else if (!user.rows[0].password_hash) {
      // Backward compatibility: existing name-only accounts get bound to first password login.
      const passwordHash = await hash(password, 12);
      await db.query("UPDATE users SET password_hash = $1 WHERE id = $2", [passwordHash, user.rows[0].id]);
      user.rows[0].password_hash = passwordHash;
    } else {
      const matches = await compare(password, user.rows[0].password_hash);
      if (!matches) {
        return reply.code(401).send({ error: "Invalid credentials" });
      }
    }

    const token = createToken();
    const expiresAt = new Date(Date.now() + 1000 * 60 * 60 * 24 * 30);
    await db.query(
      "INSERT INTO auth_sessions(token, user_id, expires_at) VALUES ($1, $2, $3)",
      [token, user.rows[0].id, expiresAt]
    );

    return {
      token,
      user: {
        id: user.rows[0].id,
        name: user.rows[0].name,
      },
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
