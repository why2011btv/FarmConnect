import { Pool } from "pg";

export type PartnerFarm = {
  key: "farm-1" | "farm-2";
  label: string;
  farmId: string;
  startDate: string;
  startAt: number;
};

const EASTERN_MIDNIGHT: Record<PartnerFarm["key"], string> = {
  "farm-1": "2026-08-20T00:00:00-04:00",
  "farm-2": "2026-09-14T00:00:00-04:00",
};

export const PARTNER_FARMS: PartnerFarm[] = [
  {
    key: "farm-1",
    label: "Farm 1",
    farmId: process.env.PARTNER_FARM_1_ID ?? "farm_1_not_configured",
    startDate: "2026-08-20",
    startAt: Date.parse(EASTERN_MIDNIGHT["farm-1"]),
  },
  {
    key: "farm-2",
    label: "Farm 2",
    farmId: process.env.PARTNER_FARM_2_ID ?? "farm_2_not_configured",
    startDate: "2026-09-14",
    startAt: Date.parse(EASTERN_MIDNIGHT["farm-2"]),
  },
];

export function findPartnerFarm(key: string): PartnerFarm | undefined {
  return PARTNER_FARMS.find((farm) => farm.key === key);
}

/** Stable partner-safe node id that never exposes the internal farm UUID embedded in device ids. */
export function publicDeviceId(farm: PartnerFarm, deviceId: string, deviceName: string): string {
  const suffix = deviceId.match(/-([a-z]+\d+)$/i)?.[1]
    ?? deviceName.match(/([a-z]+\d+)$/i)?.[1]
    ?? "node";
  return `${farm.key}-${suffix.toLowerCase()}`;
}

export type DailyMetric = {
  date: string;
  sampleCount: number;
  temperature: MetricRange | null;
  humidity: MetricRange | null;
  leafWetness: MetricRange | null;
};

type MetricRange = { average: number; minimum: number; maximum: number; unit: string };

type AggregateRow = {
  day: string;
  sensor_type: string;
  sample_count: string;
  average: string;
  minimum: string;
  maximum: string;
  unit: string;
};

const round = (value: string | number, digits = 1) => Number(Number(value).toFixed(digits));

export async function getDailyMetrics(
  db: Pool,
  farm: PartnerFarm,
  from: number,
  to: number
): Promise<DailyMetric[]> {
  const { rows } = await db.query<AggregateRow>(
    `SELECT
       to_char((to_timestamp(sr.created_at / 1000.0) AT TIME ZONE 'America/New_York')::date, 'YYYY-MM-DD') AS day,
       sr.sensor_type,
       COUNT(*)::text AS sample_count,
       AVG(sr.value)::text AS average,
       MIN(sr.value)::text AS minimum,
       MAX(sr.value)::text AS maximum,
       MIN(sr.unit) AS unit
     FROM sensor_readings sr
     JOIN devices d ON d.id = sr.device_id
     WHERE d.farm_id = $1 AND sr.created_at >= $2 AND sr.created_at < $3
     GROUP BY day, sr.sensor_type
     ORDER BY day ASC, sr.sensor_type ASC`,
    [farm.farmId, Math.max(from, farm.startAt), to]
  );

  const byDay = new Map<string, DailyMetric>();
  for (const row of rows) {
    const item = byDay.get(row.day) ?? {
      date: row.day,
      sampleCount: 0,
      temperature: null,
      humidity: null,
      leafWetness: null,
    };
    item.sampleCount += Number(row.sample_count);
    const range = {
      average: round(row.average),
      minimum: round(row.minimum),
      maximum: round(row.maximum),
      unit: row.unit,
    };
    if (row.sensor_type === "temperature") item.temperature = range;
    if (row.sensor_type === "humidity") item.humidity = range;
    if (row.sensor_type === "leaf_wetness" || row.sensor_type === "soil_moisture") {
      item.leafWetness = range;
    }
    byDay.set(row.day, item);
  }
  return [...byDay.values()];
}

export type PartnerRecommendation = {
  id: string;
  date: string;
  severity: "normal" | "watch" | "attention";
  category: "monitoring" | "scouting" | "sensor-health";
  title: string;
  recommendation: string;
  evidence: string;
  disclaimer: string;
};

const DISCLAIMER =
  "Decision support only. These sensors do not measure soil nutrients, and this is not a fertilizer-rate or pesticide recommendation.";

export function recommendationsFromDailyMetrics(
  farm: PartnerFarm,
  daily: DailyMetric[]
): PartnerRecommendation[] {
  const items: PartnerRecommendation[] = [];
  for (const day of daily) {
    const humidity = day.humidity;
    const wetness = day.leafWetness;
    const temperature = day.temperature;

    if (humidity && wetness && humidity.maximum >= 95 && wetness.average >= 55) {
      items.push({
        id: `${farm.key}-${day.date}-wet`,
        date: day.date,
        severity: "attention",
        category: "scouting",
        title: "Prolonged moisture conditions",
        recommendation:
          "Prioritize field scouting and inspect canopy airflow and wet areas. Compare observations with a validated local disease model before making any treatment decision.",
        evidence: `Humidity reached ${humidity.maximum}${humidity.unit}; average leaf wetness was ${wetness.average}${wetness.unit}.`,
        disclaimer: DISCLAIMER,
      });
    } else if ((humidity?.average ?? 0) >= 85 || (wetness?.average ?? 0) >= 50) {
      items.push({
        id: `${farm.key}-${day.date}-moisture`,
        date: day.date,
        severity: "watch",
        category: "scouting",
        title: "Moisture conditions worth watching",
        recommendation:
          "Continue routine scouting, especially in sheltered or dense-canopy areas, and document any visible symptoms before considering an intervention.",
        evidence: `Average humidity ${humidity?.average ?? "n/a"}${humidity?.unit ?? ""}; average leaf wetness ${wetness?.average ?? "n/a"}${wetness?.unit ?? ""}.`,
        disclaimer: DISCLAIMER,
      });
    }

    if ((temperature?.maximum ?? -Infinity) >= 30) {
      items.push({
        id: `${farm.key}-${day.date}-heat`,
        date: day.date,
        severity: "watch",
        category: "monitoring",
        title: "High-temperature period",
        recommendation:
          "Check vines for visible heat or water stress during the warmest part of the day. Do not infer irrigation or nutrient need from air temperature alone.",
        evidence: `Maximum measured temperature was ${temperature!.maximum}${temperature!.unit}.`,
        disclaimer: DISCLAIMER,
      });
    }

    if (day.sampleCount < 12) {
      items.push({
        id: `${farm.key}-${day.date}-coverage`,
        date: day.date,
        severity: "watch",
        category: "sensor-health",
        title: "Limited sensor coverage",
        recommendation: "Check sensor power and connectivity before using this day's readings for comparison.",
        evidence: `Only ${day.sampleCount} readings were received across all metrics.`,
        disclaimer: DISCLAIMER,
      });
    }

    if (!items.some((item) => item.date === day.date)) {
      items.push({
        id: `${farm.key}-${day.date}-routine`,
        date: day.date,
        severity: "normal",
        category: "monitoring",
        title: "Continue routine monitoring",
        recommendation: "No sensor-condition trigger was identified. Continue regular field observations and record any changes.",
        evidence: `Received ${day.sampleCount} readings; no configured monitoring threshold was crossed.`,
        disclaimer: DISCLAIMER,
      });
    }
  }
  return items.sort((a, b) => b.date.localeCompare(a.date) || a.id.localeCompare(b.id));
}

export function csvCell(value: unknown): string {
  const text = value == null ? "" : String(value);
  return /[",\n\r]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}
