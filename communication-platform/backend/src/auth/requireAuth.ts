import { FastifyReply, FastifyRequest } from "fastify";
import { Pool } from "pg";

export type AuthUser = {
  id: string;
  name: string;
};

export async function requireAuth(
  req: FastifyRequest,
  reply: FastifyReply,
  db: Pool
): Promise<AuthUser | null> {
  const authHeader = req.headers.authorization;
  const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
  if (!token) {
    await reply.code(401).send({ error: "Missing authorization token" });
    return null;
  }

  const result = await db.query<AuthUser>(
    `
    SELECT u.id, u.name
    FROM auth_sessions s
    JOIN users u ON u.id = s.user_id
    WHERE s.token = $1 AND s.expires_at > NOW()
    LIMIT 1
    `,
    [token]
  );

  if (!result.rows[0]) {
    await reply.code(401).send({ error: "Invalid or expired token" });
    return null;
  }

  return result.rows[0];
}
