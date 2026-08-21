/**
 * Short, plain-language actions for a disease risk level.
 *
 * Written for a grower to glance at in the field: at most two actions per disease, each a one-line
 * instruction with a tiny reason (or none). Still non-prescriptive — never names a product/rate and
 * never says "spray now"; materials/rate/REI/PHI belong to the label.
 *
 * Categories: scout (look), cultural (canopy/harvest work), protect (spray timing/logic).
 */

export type ActionCategory = "scout" | "cultural" | "protect";
export type DiseaseAction = { category: ActionCategory; action: string; reason: string };

type Level = "low" | "moderate" | "high" | "not-applicable";

const scout = (action: string, reason = ""): DiseaseAction => ({ category: "scout", action, reason });
const cultural = (action: string, reason = ""): DiseaseAction => ({ category: "cultural", action, reason });
const protect = (action: string, reason = ""): DiseaseAction => ({ category: "protect", action, reason });

/** Returns 0–2 short actions for a disease at a given risk level. */
export function actionsFor(key: string, level: Level, _opts: { inCriticalWindow: boolean }): DiseaseAction[] {
  if (level === "not-applicable" || level === "low") return [];
  const high = level === "high";

  switch (key) {
    case "black_rot":
      return high
        ? [
            scout("Check shaded lower clusters for tan spots.", "signs show ~2 weeks later"),
            protect("Keep spray cover on ahead of wet weather.", "cover prevents, it can't cure"),
          ]
        : [scout("Watch lower clusters for tan spots after rain.")];

    case "powdery_mildew":
      return high
        ? [
            cultural("Thin leaves and shoots to open the canopy.", "shade and still air feed it; dryness doesn't stop it"),
            protect("Tighten your spray interval and rotate product groups.", "slows resistance"),
          ]
        : [cultural("Keep the fruit-zone canopy open for airflow.")];

    case "downy_mildew":
      return high
        ? [
            protect("Renew spray cover before the next rain.", "downy needs wet leaves; rain washes cover off"),
            scout("After humid nights, check leaf tops for yellow spots."),
          ]
        : [scout("After humid nights, check leaf tops for yellow spots.")];

    case "phomopsis":
      return high
        ? [
            protect("Protect new shoots before rain, early season.", "spores splash from old wood"),
            cultural("Prune out old dead canes.", "that's where it overwinters"),
          ]
        : [scout("Check basal shoots and leaves for small dark specks.")];

    case "botrytis":
      return [
        cultural("Pull leaves around clusters for airflow."),
        cultural("Pick ahead of forecast rain.", "rain on ripe fruit causes rot"),
      ];

    default:
      return [];
  }
}
