import { createHash, timingSafeEqual } from "node:crypto";
import { FastifyReply, FastifyRequest } from "fastify";

function digest(value: string): Buffer {
  return createHash("sha256").update(value, "utf8").digest();
}
export function requirePartnerAuth(req: FastifyRequest, reply: FastifyReply): boolean {
  const expectedHash = process.env.PARTNER_API_KEY_HASH?.trim().toLowerCase();
  if (!expectedHash || !/^[a-f0-9]{64}$/.test(expectedHash)) {
    reply.code(503).send({ error: "Partner API is not configured" });
    return false;
  }

  const headerKey = req.headers["x-partner-api-key"];
  const authorization = req.headers.authorization;
  const bearerKey = authorization?.startsWith("Bearer ") ? authorization.slice(7).trim() : undefined;
  const supplied = (Array.isArray(headerKey) ? headerKey[0] : headerKey) ?? bearerKey;
  if (!supplied) {
    reply.header("www-authenticate", 'Bearer realm="Persephone partner API"');
    reply.code(401).send({ error: "Missing partner API key" });
    return false;
  }

  const actual = digest(supplied);
  const expected = Buffer.from(expectedHash, "hex");
  if (actual.length !== expected.length || !timingSafeEqual(actual, expected)) {
    reply.code(401).send({ error: "Invalid partner API key" });
    return false;
  }

  reply.header("cache-control", "private, no-store");
  return true;
}
