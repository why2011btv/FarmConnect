import { randomBytes } from "node:crypto";
import { FastifyInstance } from "fastify";
import { Pool } from "pg";
import { z } from "zod";
import { hash, compare } from "bcryptjs";
import { badRequest } from "../lib/badRequest.js";

function extractBearerToken(authHeader?: string): string | null {
  if (!authHeader) return null;
  return authHeader.startsWith("Bearer ") ? authHeader.slice(7) : null;
}

const signInSchema = z.object({
  username: z.string().min(1),
  password: z.string().min(1),
});

const signUpSchema = z.object({
  username: z.string().min(1),
  password: z.string().min(6),
  displayName: z.string().min(1),
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
    const parsed = signInSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send(badRequest(parsed.error));

    const username = normalizeUsername(parsed.data.username);
    if (!username) return reply.code(400).send({ error: "Username is required" });

    const user = await db.query<{ id: string; name: string; password_hash: string | null }>(
      "SELECT id, name, password_hash FROM users WHERE username = $1 AND deleted_at IS NULL LIMIT 1",
      [username]
    );

    const row = user.rows[0];
    // Use a constant generic error for both unknown-username and wrong-password so we don't leak
    // which usernames exist.
    const invalid = () => reply.code(401).send({ error: "Invalid username or password" });
    if (!row) return invalid();

    // Accounts without a stored password (legacy/seed rows) cannot log in.
    if (!row.password_hash) return invalid();
    const passwordOk = await compare(parsed.data.password, row.password_hash);
    if (!passwordOk) return invalid();

    const token = createToken();
    const expiresAt = new Date(Date.now() + 1000 * 60 * 60 * 24 * 30);
    await db.query(
      "INSERT INTO auth_sessions(token, user_id, expires_at) VALUES ($1, $2, $3)",
      [token, row.id, expiresAt]
    );

    // Opportunistically clean up expired sessions for this user to keep the table bounded.
    await db.query(
      "DELETE FROM auth_sessions WHERE user_id = $1 AND expires_at < NOW()",
      [row.id]
    );

    return {
      token,
      user: { id: row.id, name: row.name },
      expiresAt: expiresAt.toISOString(),
    };
  });

  app.post("/v1/auth/signup", async (req, reply) => {
    const parsed = signUpSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send(badRequest(parsed.error));

    const username = normalizeUsername(parsed.data.username);
    const password = parsed.data.password;
    const displayName = parsed.data.displayName.trim();
    if (!username) return reply.code(400).send({ error: "Username is required" });
    if (!displayName) return reply.code(400).send({ error: "Display name is required" });

    const existing = await db.query<{ id: string }>(
      "SELECT id FROM users WHERE username = $1 AND deleted_at IS NULL LIMIT 1",
      [username]
    );
    if (existing.rows[0]) {
      return reply.code(409).send({ error: "Username is already taken" });
    }

    const id = createUserId();
    const passwordHash = await hash(password, 12);
    await db.query(
      "INSERT INTO users(id, name, username, password_hash) VALUES ($1, $2, $3, $4)",
      [id, displayName, username, passwordHash]
    );

    const token = createToken();
    const expiresAt = new Date(Date.now() + 1000 * 60 * 60 * 24 * 30);
    await db.query(
      "INSERT INTO auth_sessions(token, user_id, expires_at) VALUES ($1, $2, $3)",
      [token, id, expiresAt]
    );

    return {
      token,
      user: {
        id,
        name: displayName,
      },
      expiresAt: expiresAt.toISOString(),
    };
  });

  app.get("/v1/auth/me", async (req, reply) => {
    const token = extractBearerToken(req.headers.authorization);
    if (!token) return reply.code(401).send({ error: "Missing token" });

    const result = await db.query<{ id: string; name: string }>(
      `
      SELECT u.id, u.name
      FROM auth_sessions s
      JOIN users u ON u.id = s.user_id
      WHERE s.token = $1 AND s.expires_at > NOW() AND u.deleted_at IS NULL
      LIMIT 1
      `,
      [token]
    );
    if (!result.rows[0]) return reply.code(401).send({ error: "Invalid token" });
    return { user: result.rows[0] };
  });

  // Logout: invalidates the caller's session token. Idempotent.
  app.delete("/v1/auth/session", async (req, reply) => {
    const token = extractBearerToken(req.headers.authorization);
    if (!token) return reply.code(401).send({ error: "Missing token" });

    await db.query("DELETE FROM auth_sessions WHERE token = $1", [token]);
    return reply.code(204).send();
  });

  // Account deletion (Apple Guideline 5.1.1(v)). Anonymize-in-place: scrub all PII, disable login
  // permanently, and revoke sessions + push tokens. Content (posts/comments/messages) is retained
  // but re-attributed to a "[deleted user]" placeholder so other users' threads don't break.
  app.delete("/v1/auth/account", async (req, reply) => {
    const token = extractBearerToken(req.headers.authorization);
    if (!token) return reply.code(401).send({ error: "Missing token" });

    const session = await db.query<{ user_id: string }>(
      `SELECT u.id AS user_id
       FROM auth_sessions s JOIN users u ON u.id = s.user_id
       WHERE s.token = $1 AND s.expires_at > NOW() AND u.deleted_at IS NULL
       LIMIT 1`,
      [token]
    );
    const userId = session.rows[0]?.user_id;
    if (!userId) return reply.code(401).send({ error: "Invalid or expired token" });

    const client = await db.connect();
    try {
      await client.query("BEGIN");

      // Scrub PII on the user row and make the username collision-proof + unrecognizable.
      // Username has a UNIQUE + NOT NULL constraint, so use the (unique) user id as the new value.
      await client.query(
        `UPDATE users
         SET name = '[deleted user]',
             username = 'deleted_' || id,
             password_hash = NULL,
             deleted_at = NOW()
         WHERE id = $1`,
        [userId]
      );

      // Scrub denormalized name copies stored alongside content.
      await client.query("UPDATE comments SET user_name = '[deleted user]' WHERE user_id = $1", [userId]);
      await client.query("UPDATE messages SET from_user_name = '[deleted user]' WHERE from_user_id = $1", [userId]);

      // Revoke all sessions and push tokens for the account.
      await client.query("DELETE FROM auth_sessions WHERE user_id = $1", [userId]);
      await client.query("DELETE FROM device_tokens WHERE user_id = $1", [userId]);

      await client.query("COMMIT");
    } catch (error) {
      await client.query("ROLLBACK");
      app.log.error({ error }, "Account deletion failed");
      return reply.code(500).send({ error: "Failed to delete account" });
    } finally {
      client.release();
    }

    return reply.code(204).send();
  });
}
