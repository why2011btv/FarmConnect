/**
 * Grape phenology + the disease "critical window", anchored to a grower-observed BLOOM DATE.
 *
 * Bloom is an unambiguous, observable event, so we anchor the critical window to it rather than to
 * a shaky GDD estimate. GDD (season heat) is reported as context. The critical window — immediate
 * pre-bloom through ~4 weeks post-bloom — is when clusters are most susceptible and protectant
 * sprays are made prophylactically, largely irrespective of a single day's weather.
 *
 * Sources: Cornell/NEWA and regional guidelines (critical period pre-bloom -> ~2-4 weeks post-bloom;
 * berries acquire ontogenic resistance ~4-6 weeks post-bloom); black rot fruit susceptibility bloom
 * -> ~4-6 weeks post-bloom; Phomopsis early window bud break -> pre-bloom.
 */

export type PhenologyContext = {
  hasBloomDate: boolean;
  weeksSinceBloom: number | null;
  stage: "pre-bloom" | "bloom" | "critical-window" | "post-critical" | "late-season" | "unknown";
  inCriticalWindow: boolean; // prioritize protection regardless of a single day's weather
  fruitSusceptibleBlackRot: boolean; // bloom -> ~6 weeks post-bloom
  inPhomopsisWindow: boolean; // early: before/at bloom (bud break -> pre-bloom)
  note: string;
};

const WEEK_MS = 7 * 24 * 60 * 60 * 1000;

export function phenologyContext(now: Date, bloomDateIso?: string | null): PhenologyContext {
  if (!bloomDateIso) {
    return {
      hasBloomDate: false,
      weeksSinceBloom: null,
      stage: "unknown",
      inCriticalWindow: false,
      fruitSusceptibleBlackRot: true, // unknown -> do not falsely reassure; treat fruit as susceptible
      inPhomopsisWindow: true,
      note: "Set your bloom date to tune timing. Until then, treat fruit as vulnerable.",
    };
  }

  const bloom = new Date(bloomDateIso);
  const weeks = (now.getTime() - bloom.getTime()) / WEEK_MS;

  let stage: PhenologyContext["stage"];
  if (weeks < -0.3) stage = "pre-bloom";
  else if (weeks <= 0.3) stage = "bloom";
  else if (weeks <= 4) stage = "critical-window";
  else if (weeks <= 6) stage = "post-critical";
  else stage = "late-season";

  // Critical window: immediate pre-bloom (~1 week before) through ~4 weeks post-bloom.
  const inCriticalWindow = weeks >= -1 && weeks <= 4;
  const fruitSusceptibleBlackRot = weeks >= -0.3 && weeks <= 6;
  const inPhomopsisWindow = weeks <= 0.3; // early season through bloom

  const note =
    stage === "pre-bloom"
      ? "Pre-bloom — the high-risk stretch is starting."
      : stage === "bloom"
      ? "Bloom — clusters are most vulnerable now."
      : stage === "critical-window"
      ? `${weeks.toFixed(0)} weeks after bloom — still the high-risk stretch.`
      : stage === "post-critical"
      ? `${weeks.toFixed(0)} weeks after bloom — fruit is toughening up; risk easing.`
      : `${weeks.toFixed(0)} weeks after bloom — watch for bunch rot as fruit ripens.`;

  return {
    hasBloomDate: true,
    weeksSinceBloom: weeks,
    stage,
    inCriticalWindow,
    fruitSusceptibleBlackRot,
    inPhomopsisWindow,
    note,
  };
}
