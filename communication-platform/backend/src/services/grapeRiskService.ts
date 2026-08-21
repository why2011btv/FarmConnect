import {
  HourlyWeather,
  DailyTempF,
  fetchHourlyRecent,
  fetchDailySeason,
  accumulateGdd,
} from "./grapeWeather.js";
import {
  wetEvents,
  WetEvent,
  blackRotInfection,
  phomopsisInfection,
  downyPrimaryInfection,
  downySecondaryInfection,
  downySporulation,
  powderyMildewIndex,
  DayTemps,
  botrytisRisk,
} from "./grapeDiseaseModels.js";
import { phenologyContext, PhenologyContext } from "./grapePhenology.js";

export type RiskLevel = "low" | "moderate" | "high" | "not-applicable";

export type DiseaseRisk = {
  key: "black_rot" | "phomopsis" | "powdery_mildew" | "downy_mildew" | "botrytis";
  name: string;
  level: RiskLevel;
  headline: string;
  detail: string;
};

export type DiseaseAssessment = {
  updatedAt: number;
  gddBase50FromApr1: number;
  phenology: PhenologyContext;
  diseases: DiseaseRisk[];
  disclaimer: string;
};

export type AssessOptions = {
  bloomDateIso?: string | null;
  shootLengthCm?: number; // for downy primary; defaults assume established canopy mid-season
};

const DISCLAIMER =
  "Modeled infection-condition estimates (Spotts black rot, Gubler-Thomas powdery, Erincik Phomopsis, " +
  "3-10/DMCast downy) from weather — decision support for scouting, NOT a spray recommendation. Validate " +
  "against Cornell NEWA and observed disease. Product, rate, FRAC group, REI and PHI are governed by the " +
  "product label (the legal authority) and your state's Pest Management Guidelines for Grapes.";

/** Hour-of-day in local time from an ISO timestamp like "2026-08-20T14:00". */
function hourOfDay(iso: string): number {
  const t = iso.split("T")[1] ?? "00";
  return Number(t.slice(0, 2));
}

/** Groups the hourly temperature series into per-day arrays (local calendar day). */
function groupDays(hourly: HourlyWeather): DayTemps[] {
  const byDate = new Map<string, number[]>();
  for (let i = 0; i < hourly.timeIso.length; i += 1) {
    const date = hourly.timeIso[i].split("T")[0];
    const list = byDate.get(date) ?? [];
    list.push(hourly.temperatureF[i]);
    byDate.set(date, list);
  }
  return [...byDate.keys()].sort().map((d) => ({ hourlyTempF: byDate.get(d)! }));
}

function daysAgoOfIndex(hourly: HourlyWeather, index: number, now: Date): number {
  const t = new Date(hourly.timeIso[index]).getTime();
  return (now.getTime() - t) / (24 * 60 * 60 * 1000);
}

function recentWindow(hourly: HourlyWeather, days: number): number {
  return Math.max(0, hourly.timeIso.length - days * 24);
}

function levelToWord(level: RiskLevel): string {
  return level === "high" ? "High" : level === "moderate" ? "Moderate" : level === "low" ? "Low" : "N/A";
}

/**
 * Pure assembly: runs every model on an hourly window + season GDD and returns per-disease risk.
 * Separated from the network so it can be unit-tested with synthetic weather.
 */
export function assessFromWeather(
  hourly: HourlyWeather,
  gddBase50: number,
  opts: AssessOptions,
  now: Date
): DiseaseAssessment {
  const phenology = phenologyContext(now, opts.bloomDateIso ?? null);
  const events = wetEvents(hourly.temperatureF, hourly.relativeHumidityPct, hourly.precipitationInch);
  const windowStart = recentWindow(hourly, 7);
  const recentEvents = events.filter((e) => e.startIndex >= windowStart);

  const daysAgoLabel = (e: WetEvent) => {
    const d = daysAgoOfIndex(hourly, e.startIndex, now);
    return d < 1 ? "in the last day" : `${Math.round(d)} day${Math.round(d) === 1 ? "" : "s"} ago`;
  };

  const diseases: DiseaseRisk[] = [];

  // --- Black rot ---
  {
    const infections = recentEvents.filter((e) => blackRotInfection(e).infection);
    if (!phenology.fruitSusceptibleBlackRot && phenology.hasBloomDate) {
      diseases.push({
        key: "black_rot",
        name: "Black rot",
        level: "not-applicable",
        headline: "Past the fruit-susceptible window",
        detail: "Berries are past the black-rot susceptible period (~6 weeks post-bloom). New fruit infection is unlikely.",
      });
    } else if (infections.length > 0) {
      const e = infections[infections.length - 1];
      diseases.push({
        key: "black_rot",
        name: "Black rot",
        level: "high",
        headline: `Infection conditions met ${daysAgoLabel(e)}`,
        detail: `A wetting period of ${e.hours}h near ${Math.round(e.meanTempF)}°F met the Spotts infection threshold. Scout susceptible tissue; refer to your program and the label.`,
      });
    } else {
      diseases.push({
        key: "black_rot",
        name: "Black rot",
        level: recentEvents.some((e) => blackRotInfection(e).marginHours > -3) ? "moderate" : "low",
        headline: "No infection period detected recently",
        detail: "Recent wetting periods did not reach the Spotts temperature/duration threshold for black rot.",
      });
    }
  }

  // --- Phomopsis (early season, rain-splash) ---
  {
    if (!phenology.inPhomopsisWindow && phenology.hasBloomDate) {
      diseases.push({
        key: "phomopsis",
        name: "Phomopsis",
        level: "not-applicable",
        headline: "Past the early-season window",
        detail: "The critical Phomopsis window is bud break through pre-bloom; the primary spray target has passed.",
      });
    } else {
      const rainy = recentEvents.filter((e) => e.rainInch >= 0.04 && phomopsisInfection(e).infection);
      if (rainy.length > 0) {
        const e = rainy[rainy.length - 1];
        diseases.push({
          key: "phomopsis",
          name: "Phomopsis",
          level: "high",
          headline: `Rain-splash infection conditions ${daysAgoLabel(e)}`,
          detail: `A rain event with ${e.hours}h wetness near ${Math.round(e.meanTempC)}°C met the Phomopsis threshold on new shoots.`,
        });
      } else {
        diseases.push({
          key: "phomopsis",
          name: "Phomopsis",
          level: "low",
          headline: "No qualifying rain-splash event",
          detail: "No recent rain event met the Phomopsis wetness/temperature threshold.",
        });
      }
    }
  }

  // --- Powdery mildew (Gubler-Thomas over the available window) ---
  {
    const pm = powderyMildewIndex(groupDays(hourly));
    const level: RiskLevel = pm.band === "high" ? "high" : pm.band === "moderate" ? "moderate" : "low";
    diseases.push({
      key: "powdery_mildew",
      name: "Powdery mildew",
      level,
      headline: `Risk index ${pm.index}/100 (${levelToWord(level)})`,
      detail: pm.initiated
        ? "Recent temperatures were in the 70–85°F band favorable to powdery mildew. Note: powdery is temperature-driven and NOT reduced by dryness."
        : "Temperatures have not yet sustained the consecutive favorable days that start the powdery-mildew index. (Recent-window estimate.)",
    });
  }

  // --- Downy mildew (primary + secondary) ---
  {
    // Primary: >=10mm rain over last 48h, temp >=10C, shoots >=10cm (assumed if canopy established).
    const last48 = hourly.precipitationInch.slice(-48).reduce((a, b) => a + b, 0);
    const last48mm = last48 * 25.4;
    const recentTempC = ((hourly.temperatureF[hourly.temperatureF.length - 1] ?? 60) - 32) * 5 / 9;
    const shoots = opts.shootLengthCm ?? 30;
    const primary = downyPrimaryInfection({ shootLengthCm: shoots, airTempC: recentTempC, rainMm24to48h: last48mm });

    // Secondary: qualifying wet event + a sporulation-favorable night in the window.
    const dark = hourly.timeIso.map((iso) => {
      const h = hourOfDay(iso);
      return h < 6 || h >= 20;
    });
    const sporulation = downySporulation(dark, hourly.relativeHumidityPct, hourly.temperatureF);
    const secondary = recentEvents.some((e) => downySecondaryInfection(e, sporulation));

    if (primary || secondary) {
      diseases.push({
        key: "downy_mildew",
        name: "Downy mildew",
        level: "high",
        headline: primary ? "Primary infection conditions (10-10-24)" : "Secondary infection conditions",
        detail: primary
          ? `~${last48mm.toFixed(0)}mm rain over 48h with temperature ≥10°C on ≥10cm shoots — favorable for primary downy infection.`
          : "A qualifying leaf-wetness period followed a humid, dark night favorable for sporulation.",
      });
    } else {
      diseases.push({
        key: "downy_mildew",
        name: "Downy mildew",
        level: last48mm >= 5 ? "moderate" : "low",
        headline: "No infection period detected recently",
        detail: "Recent rain/leaf-wetness and night humidity did not meet the downy infection thresholds.",
      });
    }
  }

  // --- Botrytis / bunch rot (relevant veraison -> harvest) ---
  {
    const worst = recentEvents.reduce<ReturnType<typeof botrytisRisk>>((acc, e) => {
      const r = botrytisRisk(e);
      const rank = { none: 0, low: 1, medium: 2, high: 3 } as const;
      return rank[r] > rank[acc] ? r : acc;
    }, "none");
    const lateSeason = !phenology.hasBloomDate || phenology.stage === "late-season" || phenology.stage === "post-critical";
    const level: RiskLevel = worst === "high" ? "high" : worst === "medium" ? "moderate" : "low";
    diseases.push({
      key: "botrytis",
      name: "Botrytis / bunch rot",
      level: lateSeason ? level : "not-applicable",
      headline: lateSeason ? `${levelToWord(level)} — prolonged berry wetness` : "Most relevant from veraison to harvest",
      detail: lateSeason
        ? "Extended wetness at 15–25°C on ripening fruit favors Botrytis and sour rot; tight/split clusters and wounds raise risk."
        : "Botrytis and sour rot matter mainly on ripening fruit; watch this from veraison onward.",
    });
  }

  return {
    updatedAt: now.getTime(),
    gddBase50FromApr1: Math.round(gddBase50),
    phenology,
    diseases,
    disclaimer: DISCLAIMER,
  };
}

// --- Cached network wrapper (per rounded location + bloom date; disease weather changes slowly) ---
type CacheEntry = { at: number; value: DiseaseAssessment };
const cache = new Map<string, CacheEntry>();
const CACHE_TTL_MS = 2 * 60 * 60 * 1000;

export async function assessVineyardDiseaseRisk(
  lat: number,
  lng: number,
  opts: AssessOptions,
  now: Date = new Date()
): Promise<DiseaseAssessment | null> {
  const key = `${lat.toFixed(2)},${lng.toFixed(2)},${opts.bloomDateIso ?? ""}`;
  const hit = cache.get(key);
  if (hit && now.getTime() - hit.at < CACHE_TTL_MS) return hit.value;

  const [hourly, daily] = await Promise.all([
    fetchHourlyRecent(lat, lng, 12),
    fetchDailySeason(lat, lng, now, "04-01"),
  ]);
  if (!hourly) return null;

  const gdd = accumulateGdd(daily as DailyTempF[]);
  const value = assessFromWeather(hourly, gdd, opts, now);
  cache.set(key, { at: now.getTime(), value });
  return value;
}
