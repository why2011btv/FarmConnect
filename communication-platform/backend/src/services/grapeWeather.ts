/**
 * Weather inputs for the grape disease/phenology models.
 *
 * Two shapes, from Open-Meteo:
 *   - hourly recent (temperature, RH, precip) over the last ~10 days, for leaf-wetness events and
 *     the infection models;
 *   - daily historical (Tmax/Tmin) from a spring biofix to today, for accumulated growing degree
 *     days (GDD), which drives phenology.
 *
 * This replaces the old "GDD = max(0, T-50) from one instantaneous reading", which was not GDD.
 * Real GDD is the daily mean minus the base, floored at 0, summed across the season.
 */

export type HourlyWeather = {
  timeIso: string[];
  temperatureF: number[];
  relativeHumidityPct: number[];
  precipitationInch: number[];
};

export type DailyTempF = { dateIso: string; tMaxF: number; tMinF: number };

const GDD_BASE_F = 50; // grape GDD base (10 C)
const GBM_BASE_F = 47.14; // grape berry moth base

/** One day's growing degree days: mean temp minus base, never negative. */
export function gddForDay(tMaxF: number, tMinF: number, baseF = GDD_BASE_F): number {
  const mean = (tMaxF + tMinF) / 2;
  return Math.max(0, mean - baseF);
}

/** Accumulated GDD across a series of daily highs/lows. */
export function accumulateGdd(days: DailyTempF[], baseF = GDD_BASE_F): number {
  return days.reduce((sum, d) => sum + gddForDay(d.tMaxF, d.tMinF, baseF), 0);
}

export function accumulateGbmGdd(days: DailyTempF[]): number {
  return accumulateGdd(days, GBM_BASE_F);
}

function isoDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

/**
 * Daily Tmax/Tmin from a biofix (default March 1 of the current year) through yesterday, via the
 * Open-Meteo archive API. `now` is injected so the function is deterministic and testable.
 */
export async function fetchDailySeason(
  lat: number,
  lng: number,
  now: Date,
  biofixMonthDay = "03-01"
): Promise<DailyTempF[]> {
  const year = now.getUTCFullYear();
  const start = `${year}-${biofixMonthDay}`;
  const end = isoDate(new Date(now.getTime() - 24 * 60 * 60 * 1000)); // through yesterday
  if (start > end) return [];

  const params = new URLSearchParams({
    latitude: String(lat),
    longitude: String(lng),
    start_date: start,
    end_date: end,
    daily: "temperature_2m_max,temperature_2m_min",
    temperature_unit: "fahrenheit",
    timezone: "auto",
  });
  const res = await fetch(`https://archive-api.open-meteo.com/v1/archive?${params.toString()}`);
  if (!res.ok) return [];
  const data = (await res.json()) as {
    daily?: { time?: string[]; temperature_2m_max?: Array<number | null>; temperature_2m_min?: Array<number | null> };
  };
  const time = data.daily?.time ?? [];
  const hi = data.daily?.temperature_2m_max ?? [];
  const lo = data.daily?.temperature_2m_min ?? [];
  const out: DailyTempF[] = [];
  for (let i = 0; i < time.length; i += 1) {
    const h = hi[i];
    const l = lo[i];
    if (typeof h === "number" && typeof l === "number") {
      out.push({ dateIso: time[i], tMaxF: h, tMinF: l });
    }
  }
  return out;
}

/** Hourly temperature/RH/precip over the last `pastDays` days plus today, via the forecast API. */
export async function fetchHourlyRecent(
  lat: number,
  lng: number,
  pastDays = 10
): Promise<HourlyWeather | null> {
  const params = new URLSearchParams({
    latitude: String(lat),
    longitude: String(lng),
    hourly: "temperature_2m,relative_humidity_2m,precipitation",
    temperature_unit: "fahrenheit",
    precipitation_unit: "inch",
    past_days: String(Math.min(92, Math.max(1, pastDays))),
    forecast_days: "1",
    timezone: "auto",
  });
  const res = await fetch(`https://api.open-meteo.com/v1/forecast?${params.toString()}`);
  if (!res.ok) return null;
  const data = (await res.json()) as {
    hourly?: {
      time?: string[];
      temperature_2m?: Array<number | null>;
      relative_humidity_2m?: Array<number | null>;
      precipitation?: Array<number | null>;
    };
  };
  const h = data.hourly;
  if (!h?.time) return null;
  const n = (v: number | null | undefined, f: number) =>
    typeof v === "number" && Number.isFinite(v) ? v : f;
  return {
    timeIso: h.time,
    temperatureF: (h.temperature_2m ?? []).map((v) => n(v, NaN)),
    relativeHumidityPct: (h.relative_humidity_2m ?? []).map((v) => n(v, 0)),
    precipitationInch: (h.precipitation ?? []).map((v) => n(v, 0)),
  };
}
