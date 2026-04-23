import { ZodError } from "zod";

const isDevelopment = process.env.NODE_ENV !== "production";

/**
 * Safe error payload for a failed request body/params validation.
 *
 * In development, includes the first Zod issue path + message so integrators
 * can fix client bugs quickly. In production, returns a generic message and
 * never leaks schema details.
 */
export function badRequest(error: ZodError, fallback = "Invalid request"): { error: string } {
  if (!isDevelopment) return { error: fallback };
  const issue = error.issues[0];
  if (!issue) return { error: fallback };
  const path = issue.path.length > 0 ? `${issue.path.join(".")}: ` : "";
  return { error: `${path}${issue.message}` };
}
