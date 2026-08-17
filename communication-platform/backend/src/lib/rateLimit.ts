import { Pool } from "pg";

/**
 * Sliding-window rate limit backed by `rate_limit_events`.
 *
 * Records the attempt and reports whether the caller is now over the limit. Fails open on a
 * database error: throttling is defence in depth here (the secrets it guards are 80+ bits), and
 * we would rather serve a legitimate customer than hard-fail their sign-in on a transient blip.
 */
export async function checkRateLimit(
  db: Pool,
  bucket: string,
  limit: number,
  windowSeconds: number
): Promise<boolean> {
  try {
    const { rows } = await db.query<{ count: string }>(
      `SELECT COUNT(*)::TEXT AS count
       FROM rate_limit_events
       WHERE bucket = $1 AND occurred_at > NOW() - ($2 || ' seconds')::INTERVAL`,
      [bucket, String(windowSeconds)]
    );

    await db.query("INSERT INTO rate_limit_events(bucket) VALUES ($1)", [bucket]);

    // Opportunistically prune this bucket so the table stays bounded without a cron job.
    await db.query(
      `DELETE FROM rate_limit_events
       WHERE bucket = $1 AND occurred_at < NOW() - ($2 || ' seconds')::INTERVAL`,
      [bucket, String(windowSeconds * 4)]
    );

    return Number(rows[0]?.count ?? 0) < limit;
  } catch {
    return true;
  }
}

/** Builds a bucket key from a request's client address, for anonymous endpoints. */
export function clientBucket(prefix: string, ip: string | undefined): string {
  return `${prefix}:${ip ?? "unknown"}`;
}
