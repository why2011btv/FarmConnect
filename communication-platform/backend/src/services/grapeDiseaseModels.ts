/**
 * Validated grape disease infection models for the US Northeast / Mid-Atlantic.
 *
 * These replace the app's earlier invented 0-100 heuristics with the peer-reviewed models that
 * Cornell NEWA and the regional extension guidelines actually use. Every threshold here traces to a
 * cited source (see comments), and every model has unit tests against published reference points.
 *
 * IMPORTANT FRAMING: these compute *infection conditions* from weather. They are decision SUPPORT —
 * risk/scouting estimates — not a spray recommendation. Product, rate, FRAC group, REI and PHI come
 * from the product label (the legal authority) and the NY/PA Pest Management Guidelines. Output
 * should always be validated against NEWA / observed disease before being relied upon.
 *
 * Sources: Spotts 1977 (black rot, as adopted by NEWA/Penn State/Ohio State); Gubler & Thomas /
 * UC IPM (powdery mildew risk index); Erincik et al. 2003 + Magarey 2005 generic form (Phomopsis);
 * the "3-10 / 10-10-24" rule and DMCast (downy mildew); Sentelhas et al. (leaf wetness from RH).
 */

// ---------------------------------------------------------------------------
// Leaf wetness (no sensor): an hour is wet if RH >= 90% OR it rained.
// ---------------------------------------------------------------------------

export const LEAF_WETNESS_RH_THRESHOLD = 90;

export function hourIsWet(relativeHumidityPct: number, precipInch: number): boolean {
  return relativeHumidityPct >= LEAF_WETNESS_RH_THRESHOLD || precipInch > 0;
}

export type WetEvent = {
  startIndex: number;
  hours: number;
  meanTempF: number;
  meanTempC: number;
  rainInch: number;
};

const fToC = (f: number) => ((f - 32) * 5) / 9;

/**
 * Contiguous wet-hour events from parallel hourly series. A dry gap up to `maxGapHours` (default 1)
 * does not end an event, matching how the infection models tolerate brief interruptions.
 */
export function wetEvents(
  temperatureF: number[],
  relativeHumidityPct: number[],
  precipitationInch: number[],
  maxGapHours = 1
): WetEvent[] {
  const n = temperatureF.length;
  const events: WetEvent[] = [];
  let i = 0;
  while (i < n) {
    if (!hourIsWet(relativeHumidityPct[i] ?? 0, precipitationInch[i] ?? 0)) {
      i += 1;
      continue;
    }
    // start of an event
    const start = i;
    let lastWet = i;
    let gap = 0;
    let j = i;
    while (j < n) {
      if (hourIsWet(relativeHumidityPct[j] ?? 0, precipitationInch[j] ?? 0)) {
        lastWet = j;
        gap = 0;
      } else {
        gap += 1;
        if (gap > maxGapHours) break;
      }
      j += 1;
    }
    let tempSum = 0;
    let rain = 0;
    let wetCount = 0;
    for (let k = start; k <= lastWet; k += 1) {
      if (hourIsWet(relativeHumidityPct[k] ?? 0, precipitationInch[k] ?? 0)) {
        tempSum += temperatureF[k] ?? 0;
        wetCount += 1;
      }
      rain += precipitationInch[k] ?? 0;
    }
    const meanTempF = wetCount > 0 ? tempSum / wetCount : temperatureF[start] ?? 0;
    events.push({
      startIndex: start,
      hours: wetCount,
      meanTempF,
      meanTempC: fToC(meanTempF),
      rainInch: rain,
    });
    i = lastWet + 1;
  }
  return events;
}

/** Piecewise-linear interpolation over (x,y) points sorted ascending by x; clamps at the ends. */
function interp(x: number, pts: Array<[number, number]>): number {
  if (x <= pts[0][0]) return pts[0][1];
  if (x >= pts[pts.length - 1][0]) return pts[pts.length - 1][1];
  for (let i = 1; i < pts.length; i += 1) {
    if (x <= pts[i][0]) {
      const [x0, y0] = pts[i - 1];
      const [x1, y1] = pts[i];
      return y0 + ((y1 - y0) * (x - x0)) / (x1 - x0);
    }
  }
  return pts[pts.length - 1][1];
}

// ---------------------------------------------------------------------------
// Black rot — Spotts (1977) leaf-wetness x temperature table (NEWA/extension form).
// ---------------------------------------------------------------------------

// °F -> minimum continuous leaf-wetness hours for infection. U-shaped, optimum 80°F.
const BLACK_ROT_TABLE_F: Array<[number, number]> = [
  [50, 24], [55, 12], [60, 9], [65, 8], [70, 7], [75, 7], [80, 6], [85, 9], [90, 12],
];

/** Required wetness hours at a temperature (°F). Infinity outside the infective 50-90°F range. */
export function blackRotRequiredHours(tempF: number): number {
  if (tempF < 50 || tempF > 90) return Infinity;
  return interp(tempF, BLACK_ROT_TABLE_F);
}

/** Binary infection (Spotts defines no severity classes). Optional margin = hours over threshold. */
export function blackRotInfection(event: WetEvent): { infection: boolean; marginHours: number } {
  const req = blackRotRequiredHours(event.meanTempF);
  return { infection: event.hours >= req, marginHours: Number.isFinite(req) ? event.hours - req : -Infinity };
}

// ---------------------------------------------------------------------------
// Phomopsis — Erincik et al. 2003 anchors via Magarey (2005) generic form.
// Wreq(T) = 5 / f(T), f(T)=((Tmax-T)/(Tmax-Topt)) * ((T-Tmin)/(Topt-Tmin))^exp
// Tmin 5C, Topt 18C, Tmax 35.5C, exp = (Topt-Tmin)/(Tmax-Topt) = 13/17.5 = 0.743.
// ---------------------------------------------------------------------------

const PHOM_TMIN_C = 5;
const PHOM_TOPT_C = 18;
const PHOM_TMAX_C = 35.5;
const PHOM_EXP = (PHOM_TOPT_C - PHOM_TMIN_C) / (PHOM_TMAX_C - PHOM_TOPT_C); // 0.7428...
const PHOM_WMIN = 5;

export function phomopsisRequiredHours(tempC: number): number {
  if (tempC <= PHOM_TMIN_C || tempC >= PHOM_TMAX_C) return Infinity;
  const f =
    ((PHOM_TMAX_C - tempC) / (PHOM_TMAX_C - PHOM_TOPT_C)) *
    Math.pow((tempC - PHOM_TMIN_C) / (PHOM_TOPT_C - PHOM_TMIN_C), PHOM_EXP);
  if (f <= 0) return Infinity;
  return PHOM_WMIN / f;
}

export function phomopsisInfection(event: WetEvent): { infection: boolean; requiredHours: number } {
  const req = phomopsisRequiredHours(event.meanTempC);
  return { infection: event.hours >= req, requiredHours: req };
}

// ---------------------------------------------------------------------------
// Downy mildew — primary "3-10 / 10-10-24" rule + secondary LWD x temperature.
// ---------------------------------------------------------------------------

/** Primary oosporic infection: shoots >=10cm AND air temp >=10C AND >=10mm rain within 24-48h. */
export function downyPrimaryInfection(args: {
  shootLengthCm: number;
  airTempC: number;
  rainMm24to48h: number;
}): boolean {
  return args.shootLengthCm >= 10 && args.airTempC >= 10 && args.rainMm24to48h >= 10;
}

// °C -> minimum leaf-wetness hours for secondary infection (optimum ~18-21C ≈ 2h).
const DOWNY_SECONDARY_TABLE_C: Array<[number, number]> = [
  [10, 6], [13, 3.5], [15, 2.7], [18, 2.2], [21, 2], [25, 2.4], [30, 4],
];

export function downySecondaryRequiredHours(tempC: number): number {
  if (tempC < 10 || tempC > 30) return Infinity;
  return interp(tempC, DOWNY_SECONDARY_TABLE_C);
}

/**
 * Secondary infection needs a qualifying wet event AND a prior night sporulation (>=4h darkness,
 * RH>=98%, temp>~13C). Callers pass whether sporulation conditions were met.
 */
export function downySecondaryInfection(event: WetEvent, sporulationOccurred: boolean): boolean {
  if (!sporulationOccurred) return false;
  return event.hours >= downySecondaryRequiredHours(event.meanTempC);
}

/** Night sporulation: >=4 contiguous dark hours with RH>=98% and temp >13C. */
export function downySporulation(
  isDark: boolean[],
  relativeHumidityPct: number[],
  temperatureF: number[]
): boolean {
  let run = 0;
  for (let i = 0; i < isDark.length; i += 1) {
    const ok = isDark[i] && (relativeHumidityPct[i] ?? 0) >= 98 && fToC(temperatureF[i] ?? 0) > 13;
    run = ok ? run + 1 : 0;
    if (run >= 4) return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Powdery mildew — Gubler-Thomas / UC IPM risk index (temperature-driven, 0-100).
// ---------------------------------------------------------------------------

export type DayTemps = { hourlyTempF: number[] };

/** Longest run of consecutive hours with 70<=T<=85F. */
export function longestFavorableRun(hourlyTempF: number[]): number {
  let best = 0;
  let run = 0;
  for (const t of hourlyTempF) {
    if (t >= 70 && t <= 85) {
      run += 1;
      best = Math.max(best, run);
    } else {
      run = 0;
    }
  }
  return best;
}

function dayHasHotSpell(hourlyTempF: number[]): boolean {
  // Proxy for ">=95F for >15 min": any hour at/above 95F.
  return hourlyTempF.some((t) => t >= 95);
}

export type PowderyResult = { index: number; band: "low" | "moderate" | "high"; initiated: boolean };

/**
 * Runs the Gubler-Thomas index over a sequence of days (each day's hourly temps in °F), from the
 * model biofix. Initiation: 3 consecutive qualifying days -> index 0->20->40->60. Running phase:
 * qualifying +20, non-qualifying -10, hot spell -10, daily delta clamped [-10,+20], index [0,100].
 */
export function powderyMildewIndex(days: DayTemps[]): PowderyResult {
  let index = 0;
  let initiated = false;
  let initStreak = 0;

  for (const day of days) {
    const qualifying = longestFavorableRun(day.hourlyTempF) >= 6;
    const hot = dayHasHotSpell(day.hourlyTempF);

    if (!initiated) {
      if (qualifying) {
        initStreak += 1;
        index = Math.min(100, index + 20); // each of the 3 init days adds +20
        if (initStreak >= 3) initiated = true;
      } else {
        initStreak = 0;
        index = 0;
      }
      continue;
    }

    let delta = qualifying ? 20 : -10;
    if (hot) delta -= 10;
    delta = Math.max(-10, Math.min(20, delta));
    index = Math.max(0, Math.min(100, index + delta));
  }

  const band = index >= 60 ? "high" : index >= 40 ? "moderate" : "low";
  return { index, band, initiated };
}

// ---------------------------------------------------------------------------
// Botrytis / bunch rot near harvest — prolonged berry wetness x temperature.
// Approximate: anchors are 60°F (med ~15h / high ~17.5h) and warmer temps infect faster.
// ---------------------------------------------------------------------------

export function botrytisRisk(event: WetEvent): "none" | "low" | "medium" | "high" {
  if (event.meanTempC < 12) return "none"; // below ~12C little infection
  // Wetness hours for medium / high risk, easing as temperature rises toward ~21C.
  const medHours = interp(event.meanTempF, [
    [55, 20], [60, 15], [65, 11], [71, 8], [77, 8],
  ]);
  const highHours = interp(event.meanTempF, [
    [55, 24], [60, 17.5], [65, 14], [71, 11], [77, 11],
  ]);
  if (event.hours >= highHours) return "high";
  if (event.hours >= medHours) return "medium";
  if (event.hours >= medHours * 0.5) return "low";
  return "none";
}
