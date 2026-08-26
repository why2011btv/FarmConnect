import { Pool } from "pg";
import { getUserFarmIds } from "../auth/farmAccess.js";

/**
 * Builds a private, per-user sensor-data context block for the chat assistant.
 *
 * Tenancy: readings are scoped through getUserFarmIds(userId), so the block only ever contains the
 * calling account's own farm sensors — never another grower's. It's injected fresh per request and
 * never stored in chat history, so it can't leak into titles or persist stale.
 *
 * Day boundaries use the client's tz offset so "yesterday"/"two days ago" match what the grower sees.
 * Returns null when the user has no farm or no recent readings.
 */
export async function buildAssistantSensorContext(
  db: Pool,
  userId: string,
  tzOffsetMinutes: number,
  nowMs: number,
  daysBack = 8
): Promise<string | null> {
  const farmIds = await getUserFarmIds(db, userId);
  if (farmIds.length === 0) return null;

  const offsetMs = Math.trunc(tzOffsetMinutes) * 60_000;
  const windowStart = nowMs - daysBack * 24 * 60 * 60 * 1000;

  // Per-day aggregates in the grower's local time (shift epoch by offset, then take the date).
  const daily = await db.query<{
    device: string;
    sensor_type: string;
    unit: string;
    local_day: string;
    vmin: string;
    vmax: string;
    vavg: string;
    n: string;
  }>(
    `
    SELECT d.name AS device, sr.sensor_type, sr.unit,
           to_char(to_timestamp((sr.created_at + $2) / 1000.0), 'YYYY-MM-DD') AS local_day,
           min(sr.value) AS vmin, max(sr.value) AS vmax, avg(sr.value) AS vavg, count(*) AS n
    FROM sensor_readings sr
    JOIN devices d ON d.id = sr.device_id
    WHERE d.farm_id = ANY($1::text[]) AND sr.created_at >= $3
    GROUP BY d.name, sr.sensor_type, sr.unit, local_day
    ORDER BY d.name ASC, local_day DESC, sr.sensor_type ASC
    `,
    [farmIds, offsetMs, windowStart]
  );
  if (daily.rows.length === 0) return null;

  // Latest reading per device+sensor (any age).
  const latest = await db.query<{
    device: string;
    sensor_type: string;
    value: string;
    unit: string;
    created_at: string;
  }>(
    `
    SELECT DISTINCT ON (d.name, sr.sensor_type)
      d.name AS device, sr.sensor_type, sr.value, sr.unit, sr.created_at
    FROM sensor_readings sr
    JOIN devices d ON d.id = sr.device_id
    WHERE d.farm_id = ANY($1::text[])
    ORDER BY d.name ASC, sr.sensor_type ASC, sr.created_at DESC
    `,
    [farmIds]
  );

  const localDateStr = (ms: number) =>
    new Date(ms + offsetMs).toISOString().slice(0, 10);
  const localDateTimeStr = (ms: number) =>
    new Date(ms + offsetMs).toISOString().slice(0, 16).replace("T", " ");
  const today = localDateStr(nowMs);
  const fmt = (v: string | number) => {
    const n = typeof v === "string" ? Number(v) : v;
    return Number.isFinite(n) ? n.toFixed(1) : String(v);
  };
  const relLabel = (day: string): string => {
    const diff = Math.round(
      (Date.parse(today + "T00:00:00Z") - Date.parse(day + "T00:00:00Z")) / 86_400_000
    );
    if (diff === 0) return "today";
    if (diff === 1) return "yesterday";
    if (diff > 1) return `${diff} days ago`;
    return day;
  };

  // Group latest and daily by device.
  const devices = Array.from(new Set(daily.rows.map((r) => r.device))).slice(0, 12);
  const latestByDevice = new Map<string, string[]>();
  for (const r of latest.rows) {
    const list = latestByDevice.get(r.device) ?? [];
    list.push(`${r.sensor_type} ${fmt(r.value)}${r.unit === "%" ? "%" : ` ${r.unit}`}`);
    latestByDevice.set(r.device, list);
  }
  const latestTimeByDevice = new Map<string, number>();
  for (const r of latest.rows) {
    const t = Number(r.created_at);
    latestTimeByDevice.set(r.device, Math.max(latestTimeByDevice.get(r.device) ?? 0, t));
  }

  const lines: string[] = [];
  lines.push("=== GROWER'S OWN SENSOR DATA (private to this account) ===");
  lines.push(
    `Current local time: ${localDateTimeStr(nowMs)} (UTC offset ${tzOffsetMinutes >= 0 ? "+" : "-"}${String(
      Math.floor(Math.abs(tzOffsetMinutes) / 60)
    ).padStart(2, "0")}:${String(Math.abs(tzOffsetMinutes) % 60).padStart(2, "0")}). Dates below are the grower's local time.`
  );

  for (const device of devices) {
    lines.push("");
    lines.push(`Device: ${device}`);
    const lt = latestTimeByDevice.get(device);
    const latestParts = latestByDevice.get(device);
    if (latestParts && lt) {
      lines.push(`  Latest: ${latestParts.join(", ")} (${localDateTimeStr(lt)})`);
    }
    // Rebuild per-day, per-sensor summary for this device.
    const dayRows = daily.rows.filter((r) => r.device === device);
    const byDay = new Map<string, string[]>();
    for (const r of dayRows) {
      const list = byDay.get(r.local_day) ?? [];
      list.push(
        `${r.sensor_type} ${fmt(r.vmin)}/${fmt(r.vavg)}/${fmt(r.vmax)}${r.unit === "%" ? "%" : ` ${r.unit}`} (n=${r.n})`
      );
      byDay.set(r.local_day, list);
    }
    lines.push("  Daily (min/avg/max):");
    for (const day of Array.from(byDay.keys()).sort().reverse()) {
      lines.push(`    ${day} (${relLabel(day)}): ${byDay.get(day)!.join("; ")}`);
    }
  }

  return lines.join("\n");
}
