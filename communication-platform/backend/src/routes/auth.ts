import { randomBytes } from "node:crypto";
import { FastifyInstance } from "fastify";
import { Pool } from "pg";
import { z } from "zod";
import { hash, compare } from "bcryptjs";
import { badRequest } from "../lib/badRequest.js";
import { generateShortCode, hashSecret, normalizeShortCode } from "../lib/accessCode.js";
import { checkRateLimit, clientBucket } from "../lib/rateLimit.js";
import { sendEmailVerificationEmail, sendPasswordResetEmail } from "../services/mailService.js";
import { bootstrapAdminEmails } from "../auth/requireAdmin.js";

function extractBearerToken(authHeader?: string): string | null {
  if (!authHeader) return null;
  return authHeader.startsWith("Bearer ") ? authHeader.slice(7) : null;
}

// Login accepts either an email (the identifier going forward) or a username (so builds already
// on testers' phones keep working through the transition). Exactly one is required.
const signInSchema = z
  .object({
    email: z.string().min(1).optional(),
    username: z.string().min(1).optional(),
    password: z.string().min(1),
  })
  .refine((v) => Boolean(v.email || v.username), {
    message: "email or username is required",
    path: ["email"],
  });

const signUpSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
  displayName: z.string().min(1),
  username: z.string().min(1).optional(),
});

const forgotPasswordSchema = z.object({
  email: z.string().email(),
});

const resetPasswordSchema = z.object({
  email: z.string().email(),
  code: z.string().min(1),
  password: z.string().min(8),
});

const verifyEmailSchema = z.object({
  code: z.string().min(1),
});

// Adding an address to a legacy account. The current password is required: a stolen session
// alone must not be enough to attach an attacker's address, because doing so would hand them the
// password-reset channel for the account.
const setEmailSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
});

const SESSION_TTL_MS = 1000 * 60 * 60 * 24 * 30;
const RESET_TTL_MS = 1000 * 60 * 30;
const VERIFICATION_TTL_MS = 1000 * 60 * 60 * 24;

function createUserId() {
  return `u_${randomBytes(8).toString("hex")}`;
}

function createToken() {
  return randomBytes(24).toString("hex");
}

function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

function normalizeUsername(username: string): string {
  return username
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_]/g, "_")
    .replace(/_+/g, "_")
    .replace(/^_+|_+$/g, "");
}

/**
 * Picks a free username. Callers sign up with an email now, so the username is derived from the
 * address local part and only exists for display/@-mentions; collisions get a random suffix
 * rather than failing the signup.
 */
async function allocateUsername(db: Pool, preferred: string): Promise<string> {
  const base = normalizeUsername(preferred) || "grower";
  for (let attempt = 0; attempt < 6; attempt += 1) {
    const candidate = attempt === 0 ? base : `${base}_${randomBytes(2).toString("hex")}`;
    const { rows } = await db.query<{ id: string }>(
      "SELECT id FROM users WHERE username = $1 LIMIT 1",
      [candidate]
    );
    if (rows.length === 0) return candidate;
  }
  return `${base}_${randomBytes(4).toString("hex")}`;
}

type UserRow = {
  id: string;
  name: string;
  email: string | null;
  email_verified_at: Date | null;
  is_admin?: boolean;
};

function toProfile(row: UserRow) {
  return {
    id: row.id,
    name: row.name,
    email: row.email,
    emailVerified: Boolean(row.email_verified_at),
    isAdmin: Boolean(row.is_admin),
  };
}

/**
 * Grants staff access to addresses listed in ADMIN_BOOTSTRAP_EMAILS, so the first admin can be
 * created from the Railway dashboard without touching the database. Returns the effective flag.
 */
async function applyAdminBootstrap(
  db: Pool,
  userId: string,
  email: string | null,
  current: boolean
): Promise<boolean> {
  if (current || !email) return current;
  if (!bootstrapAdminEmails().has(email.toLowerCase())) return current;
  await db.query("UPDATE users SET is_admin = TRUE WHERE id = $1", [userId]);
  return true;
}

async function issueSession(db: Pool, userId: string) {
  const token = createToken();
  const expiresAt = new Date(Date.now() + SESSION_TTL_MS);
  await db.query("INSERT INTO auth_sessions(token, user_id, expires_at) VALUES ($1, $2, $3)", [
    token,
    userId,
    expiresAt,
  ]);
  await db.query("DELETE FROM auth_sessions WHERE user_id = $1 AND expires_at < NOW()", [userId]);
  return { token, expiresAt };
}

async function issueVerificationCode(db: Pool, userId: string, email: string) {
  const code = generateShortCode();
  await db.query(
    "DELETE FROM email_verification_tokens WHERE user_id = $1 AND used_at IS NULL",
    [userId]
  );
  await db.query(
    `INSERT INTO email_verification_tokens(token_hash, user_id, email, expires_at)
     VALUES ($1, $2, $3, $4)`,
    [hashSecret(code), userId, email, new Date(Date.now() + VERIFICATION_TTL_MS)]
  );
  return code;
}

export async function authRoutes(app: FastifyInstance, db: Pool) {
  app.post("/v1/auth/login", async (req, reply) => {
    const parsed = signInSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send(badRequest(parsed.error));

    // Use one constant error for unknown-account and wrong-password so we don't leak which
    // addresses are registered.
    const invalid = () => reply.code(401).send({ error: "Invalid email or password" });

    const identifier = parsed.data.email
      ? normalizeEmail(parsed.data.email)
      : normalizeUsername(parsed.data.username ?? "");
    if (!identifier) return invalid();

    const allowed = await checkRateLimit(db, `login:${identifier}`, 10, 15 * 60);
    if (!allowed) {
      return reply.code(429).send({ error: "Too many sign-in attempts. Try again in a few minutes." });
    }

    const user = await db.query<UserRow & { password_hash: string | null }>(
      `SELECT id, name, email, email_verified_at, is_admin, password_hash
       FROM users
       WHERE deleted_at IS NULL AND (LOWER(email) = $1 OR username = $1)
       LIMIT 1`,
      [identifier]
    );

    const row = user.rows[0];
    if (!row) return invalid();

    // Accounts without a stored password (legacy/seed rows) cannot log in.
    if (!row.password_hash) return invalid();
    const passwordOk = await compare(parsed.data.password, row.password_hash);
    if (!passwordOk) return invalid();

    row.is_admin = await applyAdminBootstrap(db, row.id, row.email, Boolean(row.is_admin));

    const { token, expiresAt } = await issueSession(db, row.id);
    return { token, user: toProfile(row), expiresAt: expiresAt.toISOString() };
  });

  app.post("/v1/auth/signup", async (req, reply) => {
    const parsed = signUpSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send(badRequest(parsed.error));

    const email = normalizeEmail(parsed.data.email);
    const displayName = parsed.data.displayName.trim();
    if (!displayName) return reply.code(400).send({ error: "Display name is required" });

    const existing = await db.query<{ id: string }>(
      "SELECT id FROM users WHERE LOWER(email) = $1 AND deleted_at IS NULL LIMIT 1",
      [email]
    );
    if (existing.rows[0]) {
      return reply.code(409).send({ error: "An account with that email already exists" });
    }

    const username = await allocateUsername(db, parsed.data.username ?? email.split("@")[0]);
    const id = createUserId();
    const passwordHash = await hash(parsed.data.password, 12);

    try {
      await db.query(
        "INSERT INTO users(id, name, username, email, password_hash) VALUES ($1, $2, $3, $4, $5)",
        [id, displayName, username, email, passwordHash]
      );
    } catch (error) {
      // Unique violation on the concurrent-signup race.
      if ((error as { code?: string }).code === "23505") {
        return reply.code(409).send({ error: "An account with that email already exists" });
      }
      throw error;
    }

    // Verification is sent but not enforced: a grower standing in a vineyard with one bar of signal
    // should not be blocked from seeing their sensors because an email is slow. It gates nothing
    // today beyond marking the address confirmed.
    const code = await issueVerificationCode(db, id, email);
    await sendEmailVerificationEmail(email, code, app.log);

    const isAdmin = await applyAdminBootstrap(db, id, email, false);
    const { token, expiresAt } = await issueSession(db, id);
    return {
      token,
      user: { id, name: displayName, email, emailVerified: false, isAdmin },
      expiresAt: expiresAt.toISOString(),
    };
  });

  app.get("/v1/auth/me", async (req, reply) => {
    const token = extractBearerToken(req.headers.authorization);
    if (!token) return reply.code(401).send({ error: "Missing token" });

    const result = await db.query<UserRow>(
      `
      SELECT u.id, u.name, u.email, u.email_verified_at, u.is_admin
      FROM auth_sessions s
      JOIN users u ON u.id = s.user_id
      WHERE s.token = $1 AND s.expires_at > NOW() AND u.deleted_at IS NULL
      LIMIT 1
      `,
      [token]
    );
    if (!result.rows[0]) return reply.code(401).send({ error: "Invalid token" });
    return { user: toProfile(result.rows[0]) };
  });

  /**
   * Starts a password reset. Always returns 204, whether or not the address is registered —
   * a differing response here would turn this endpoint into a free account-enumeration oracle.
   */
  app.post("/v1/auth/forgot-password", async (req, reply) => {
    const parsed = forgotPasswordSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send(badRequest(parsed.error));

    const email = normalizeEmail(parsed.data.email);

    const perEmail = await checkRateLimit(db, `forgot:${email}`, 5, 60 * 60);
    const perIp = await checkRateLimit(db, clientBucket("forgot-ip", req.ip), 20, 60 * 60);
    if (!perEmail || !perIp) {
      // Still a 204: rate-limit feedback would leak that the address exists.
      return reply.code(204).send();
    }

    const { rows } = await db.query<{ id: string }>(
      "SELECT id FROM users WHERE LOWER(email) = $1 AND deleted_at IS NULL LIMIT 1",
      [email]
    );
    const userId = rows[0]?.id;

    if (userId) {
      const code = generateShortCode();
      // Supersede any outstanding code so only the newest one works.
      await db.query(
        "DELETE FROM password_reset_tokens WHERE user_id = $1 AND used_at IS NULL",
        [userId]
      );
      await db.query(
        `INSERT INTO password_reset_tokens(token_hash, user_id, expires_at)
         VALUES ($1, $2, $3)`,
        [hashSecret(code), userId, new Date(Date.now() + RESET_TTL_MS)]
      );
      await sendPasswordResetEmail(email, code, app.log);
    }

    return reply.code(204).send();
  });

  /**
   * Completes a password reset. Revokes every existing session for the account: if the reset was
   * triggered because someone else had access, leaving their session alive defeats the point.
   */
  app.post("/v1/auth/reset-password", async (req, reply) => {
    const parsed = resetPasswordSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send(badRequest(parsed.error));

    const email = normalizeEmail(parsed.data.email);
    const code = normalizeShortCode(parsed.data.code);

    // The emailed code is only 40 bits, so the guess rate is what actually protects it.
    const allowed = await checkRateLimit(db, `reset:${email}`, 10, 60 * 60);
    if (!allowed) {
      return reply.code(429).send({ error: "Too many attempts. Request a new code and try again." });
    }

    const invalid = () => reply.code(400).send({ error: "That reset code is invalid or has expired" });

    const { rows } = await db.query<{ token_hash: string; user_id: string }>(
      `SELECT t.token_hash, t.user_id
       FROM password_reset_tokens t
       JOIN users u ON u.id = t.user_id
       WHERE t.token_hash = $1
         AND t.used_at IS NULL
         AND t.expires_at > NOW()
         AND LOWER(u.email) = $2
         AND u.deleted_at IS NULL
       LIMIT 1`,
      [hashSecret(code), email]
    );
    const row = rows[0];
    if (!row) return invalid();

    const passwordHash = await hash(parsed.data.password, 12);
    const client = await db.connect();
    try {
      await client.query("BEGIN");
      await client.query("UPDATE users SET password_hash = $1 WHERE id = $2", [
        passwordHash,
        row.user_id,
      ]);
      await client.query("UPDATE password_reset_tokens SET used_at = NOW() WHERE token_hash = $1", [
        row.token_hash,
      ]);
      await client.query("DELETE FROM auth_sessions WHERE user_id = $1", [row.user_id]);
      await client.query("COMMIT");
    } catch (error) {
      await client.query("ROLLBACK");
      app.log.error({ error }, "Password reset failed");
      return reply.code(500).send({ error: "Failed to reset password" });
    } finally {
      client.release();
    }

    // Hand back a fresh session so the app can drop the user straight into the dashboard.
    const { token, expiresAt } = await issueSession(db, row.user_id);
    const profile = await db.query<UserRow>(
      "SELECT id, name, email, email_verified_at, is_admin FROM users WHERE id = $1",
      [row.user_id]
    );
    return { token, user: toProfile(profile.rows[0]), expiresAt: expiresAt.toISOString() };
  });

  app.post("/v1/auth/verify-email", async (req, reply) => {
    const token = extractBearerToken(req.headers.authorization);
    if (!token) return reply.code(401).send({ error: "Missing token" });

    const parsed = verifyEmailSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send(badRequest(parsed.error));

    const session = await db.query<{ user_id: string }>(
      `SELECT u.id AS user_id FROM auth_sessions s JOIN users u ON u.id = s.user_id
       WHERE s.token = $1 AND s.expires_at > NOW() AND u.deleted_at IS NULL LIMIT 1`,
      [token]
    );
    const userId = session.rows[0]?.user_id;
    if (!userId) return reply.code(401).send({ error: "Invalid or expired token" });

    const allowed = await checkRateLimit(db, `verify:${userId}`, 10, 60 * 60);
    if (!allowed) return reply.code(429).send({ error: "Too many attempts. Try again later." });

    const code = normalizeShortCode(parsed.data.code);
    const { rows } = await db.query<{ token_hash: string; email: string }>(
      `SELECT token_hash, email FROM email_verification_tokens
       WHERE token_hash = $1 AND user_id = $2 AND used_at IS NULL AND expires_at > NOW()
       LIMIT 1`,
      [hashSecret(code), userId]
    );
    const row = rows[0];
    if (!row) return reply.code(400).send({ error: "That code is invalid or has expired" });

    await db.query("UPDATE email_verification_tokens SET used_at = NOW() WHERE token_hash = $1", [
      row.token_hash,
    ]);
    await db.query("UPDATE users SET email_verified_at = NOW() WHERE id = $1", [userId]);
    return { ok: true };
  });

  /**
   * Attaches an email to an account created before email login existed.
   *
   * Deliberately only fills a missing address — it is not a change-email flow, which would also
   * need confirmation sent to the previous address before switching.
   */
  app.post("/v1/auth/email", async (req, reply) => {
    const token = extractBearerToken(req.headers.authorization);
    if (!token) return reply.code(401).send({ error: "Missing token" });

    const parsed = setEmailSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send(badRequest(parsed.error));

    const session = await db.query<UserRow & { password_hash: string | null }>(
      `SELECT u.id, u.name, u.email, u.email_verified_at, u.is_admin, u.password_hash
       FROM auth_sessions s JOIN users u ON u.id = s.user_id
       WHERE s.token = $1 AND s.expires_at > NOW() AND u.deleted_at IS NULL
       LIMIT 1`,
      [token]
    );
    const row = session.rows[0];
    if (!row) return reply.code(401).send({ error: "Invalid or expired token" });

    if (row.email) {
      return reply.code(409).send({ error: "This account already has an email address" });
    }

    const allowed = await checkRateLimit(db, `setemail:${row.id}`, 10, 60 * 60);
    if (!allowed) return reply.code(429).send({ error: "Too many attempts. Try again later." });

    if (!row.password_hash) {
      return reply.code(400).send({ error: "This account cannot add an email address" });
    }
    const passwordOk = await compare(parsed.data.password, row.password_hash);
    if (!passwordOk) return reply.code(401).send({ error: "That password is incorrect" });

    const email = normalizeEmail(parsed.data.email);
    const taken = await db.query<{ id: string }>(
      "SELECT id FROM users WHERE LOWER(email) = $1 AND deleted_at IS NULL LIMIT 1",
      [email]
    );
    if (taken.rows[0]) {
      return reply.code(409).send({ error: "An account with that email already exists" });
    }

    try {
      await db.query("UPDATE users SET email = $2 WHERE id = $1", [row.id, email]);
    } catch (error) {
      if ((error as { code?: string }).code === "23505") {
        return reply.code(409).send({ error: "An account with that email already exists" });
      }
      throw error;
    }

    const code = await issueVerificationCode(db, row.id, email);
    await sendEmailVerificationEmail(email, code, app.log);

    const isAdmin = await applyAdminBootstrap(db, row.id, email, Boolean(row.is_admin));
    return { user: toProfile({ ...row, email, is_admin: isAdmin }) };
  });

  app.post("/v1/auth/resend-verification", async (req, reply) => {
    const token = extractBearerToken(req.headers.authorization);
    if (!token) return reply.code(401).send({ error: "Missing token" });

    const session = await db.query<{ user_id: string; email: string | null; verified: Date | null }>(
      `SELECT u.id AS user_id, u.email, u.email_verified_at AS verified
       FROM auth_sessions s JOIN users u ON u.id = s.user_id
       WHERE s.token = $1 AND s.expires_at > NOW() AND u.deleted_at IS NULL LIMIT 1`,
      [token]
    );
    const row = session.rows[0];
    if (!row) return reply.code(401).send({ error: "Invalid or expired token" });
    if (!row.email) return reply.code(400).send({ error: "This account has no email address" });
    if (row.verified) return { ok: true, alreadyVerified: true };

    const allowed = await checkRateLimit(db, `resend:${row.user_id}`, 3, 60 * 60);
    if (!allowed) return reply.code(429).send({ error: "Too many requests. Try again later." });

    const code = await issueVerificationCode(db, row.user_id, row.email);
    await sendEmailVerificationEmail(row.email, code, app.log);
    return { ok: true };
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
      // Email is cleared outright so the address can be used to register again later.
      await client.query(
        `UPDATE users
         SET name = '[deleted user]',
             username = 'deleted_' || id,
             email = NULL,
             email_verified_at = NULL,
             password_hash = NULL,
             deleted_at = NOW()
         WHERE id = $1`,
        [userId]
      );

      // Scrub denormalized name copies stored alongside content.
      await client.query("UPDATE comments SET user_name = '[deleted user]' WHERE user_id = $1", [userId]);
      await client.query("UPDATE messages SET from_user_name = '[deleted user]' WHERE from_user_id = $1", [userId]);

      // Revoke all sessions, push tokens, farm access and outstanding email tokens.
      await client.query("DELETE FROM auth_sessions WHERE user_id = $1", [userId]);
      await client.query("DELETE FROM device_tokens WHERE user_id = $1", [userId]);
      await client.query("DELETE FROM farm_members WHERE user_id = $1", [userId]);
      await client.query("DELETE FROM password_reset_tokens WHERE user_id = $1", [userId]);
      await client.query("DELETE FROM email_verification_tokens WHERE user_id = $1", [userId]);

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
