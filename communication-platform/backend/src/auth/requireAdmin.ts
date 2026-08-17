import { FastifyReply, FastifyRequest } from "fastify";
import { Pool } from "pg";

export type AdminUser = {
  id: string;
  name: string;
  email: string | null;
};

/**
 * Gate for staff-only endpoints.
 *
 * A signed-in non-admin gets 404, not 403: the admin surface should be invisible to customers
 * rather than merely locked, so probing it reveals nothing about what exists.
 */
export async function requireAdmin(
  req: FastifyRequest,
  reply: FastifyReply,
  db: Pool
): Promise<AdminUser | null> {
  const authHeader = req.headers.authorization;
  const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
  if (!token) {
    await reply.code(404).send({ error: "Not found" });
    return null;
  }

  const { rows } = await db.query<AdminUser & { is_admin: boolean }>(
    `SELECT u.id, u.name, u.email, u.is_admin
     FROM auth_sessions s
     JOIN users u ON u.id = s.user_id
     WHERE s.token = $1 AND s.expires_at > NOW() AND u.deleted_at IS NULL
     LIMIT 1`,
    [token]
  );

  const row = rows[0];
  if (!row || !row.is_admin) {
    await reply.code(404).send({ error: "Not found" });
    return null;
  }

  return { id: row.id, name: row.name, email: row.email };
}

/**
 * Emails that are granted admin automatically on sign-in, from ADMIN_BOOTSTRAP_EMAILS.
 *
 * Lets the first admin be created from the Railway dashboard without database access. Existing
 * admins are never demoted by removing an address here — revoke those explicitly.
 */
export function bootstrapAdminEmails(): Set<string> {
  const raw = process.env.ADMIN_BOOTSTRAP_EMAILS ?? "";
  return new Set(
    raw
      .split(",")
      .map((value) => value.trim().toLowerCase())
      .filter((value) => value.length > 0)
  );
}
