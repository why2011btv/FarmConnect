/**
 * Turns a disease risk level into ACTIONABLE, reasoned guidance for the grower.
 *
 * The design threads the liability needle: the app never tells anyone to apply a specific product
 * at a specific rate (that is the label's job, legally). Instead it gives the actions an agronomist
 * gives first — scout, manage the canopy, and get the TIMING of protection right — each paired with
 * the biological reason, and always defers materials/rate/REI/PHI to the label + state guidelines.
 *
 * Categories:
 *   scout    — always safe, always appropriate; find out what's actually there.
 *   cultural — non-pesticide IPM (canopy, airflow, sanitation, harvest timing).
 *   protect  — protection TIMING and program logic; specifics deferred to the label.
 */

export type ActionCategory = "scout" | "cultural" | "protect";

export type DiseaseAction = {
  category: ActionCategory;
  action: string;
  reason: string;
};

type Level = "low" | "moderate" | "high" | "not-applicable";

const LABEL_NOTE =
  "Choose materials, rate, REI and PHI from the product label (the legal authority) and your state's grape guidelines.";

/** Returns tiered actions for a disease at a given risk level and phenology gate. */
export function actionsFor(
  key: string,
  level: Level,
  opts: { inCriticalWindow: boolean }
): DiseaseAction[] {
  if (level === "not-applicable") return [];

  const scout = (action: string, reason: string): DiseaseAction => ({ category: "scout", action, reason });
  const cultural = (action: string, reason: string): DiseaseAction => ({ category: "cultural", action, reason });
  const protect = (action: string, reason: string): DiseaseAction => ({ category: "protect", action, reason });

  const high = level === "high";
  const moderate = level === "moderate";

  switch (key) {
    case "black_rot": {
      const out: DiseaseAction[] = [
        scout(
          "Scout shaded, lower-canopy leaves and young clusters for tan spots ringed with tiny black dots over the next 1–2 weeks.",
          "Black rot symptoms appear 1–2 weeks after infection, so scout on a lag — what you find tells you whether protection held."
        ),
      ];
      if (high || moderate)
        out.push(
          cultural(
            "Pull leaves in the fruit zone to speed canopy drying after rain and dew.",
            "Shorter leaf-wetness periods fall below the infection threshold; open canopies dry faster."
          )
        );
      if (high)
        out.push(
          protect(
            `Make sure protectant coverage was intact BEFORE this wetting period — protectants can't cure an infection that already occurred; a post-infection material only helps within its label's kick-back window. ${LABEL_NOTE}`,
            "Clusters are in the susceptible window and this event met the Spotts infection threshold."
          )
        );
      return out;
    }

    case "powdery_mildew": {
      const out: DiseaseAction[] = [
        cultural(
          "Open the fruit-zone canopy with leaf and shoot thinning for airflow and light.",
          "Powdery mildew thrives in dense, shaded canopies and — unlike downy — is NOT suppressed by dryness, so canopy management is a primary tool."
        ),
        scout(
          "Scout upper and lower leaf surfaces and clusters for white, powdery patches.",
          "Early colonies are easiest to knock back and confirm whether the model's risk is real in your blocks."
        ),
      ];
      if (high)
        out.push(
          protect(
            `Tighten your powdery program toward the shorter interval this index implies, and rotate mode-of-action (FRAC) groups — QoI/FRAC 11 resistance is widespread in the East. ${LABEL_NOTE}`,
            "The index reflects sustained 70–85°F temperatures favorable to powdery; repeating one mode of action drives resistance and control failure."
          )
        );
      return out;
    }

    case "downy_mildew": {
      const out: DiseaseAction[] = [
        scout(
          "After humid nights, scout upper leaf surfaces for yellow 'oil spots' with white downy growth on the underside.",
          "Sporulation happens overnight; the oilspot/white-underside pair confirms active downy."
        ),
        cultural(
          "Improve airflow and avoid late-day overhead watering to cut nighttime leaf wetness.",
          "Downy needs several hours of free water at night to infect and sporulate; drier nights break the cycle."
        ),
      ];
      if (high)
        out.push(
          protect(
            `Renew protectant coverage before the next rain — downy needs free water and heavy rain can wash protectant off. ${LABEL_NOTE}`,
            "This event met the downy infection thresholds (rain / leaf wetness with warmth)."
          )
        );
      return out;
    }

    case "phomopsis": {
      const out: DiseaseAction[] = [
        scout(
          "Scout basal leaves and shoots for small dark lesions, often with a yellow halo.",
          "Basal-node infections early become the cane lesions and fruit rot that hurt later."
        ),
        cultural(
          "Prune out and remove old infected canes and dead spurs.",
          "They are the overwintering inoculum that rain splashes onto new shoots."
        ),
      ];
      if (high)
        out.push(
          protect(
            `Protect new shoots (roughly 1–6 inches) ahead of rain events early in the season. ${LABEL_NOTE}`,
            "Spores splash from old wood onto young tissue during rain; early shoots are the damaging infection court."
          )
        );
      return out;
    }

    case "botrytis": {
      const out: DiseaseAction[] = [
        cultural(
          "Leaf-pull the cluster zone (from fruit set) and manage vigor and tight clusters.",
          "Open, drier cluster zones and looser clusters resist Botrytis and sour rot."
        ),
        cultural(
          "Plan to pick ahead of forecast rain as fruit ripens.",
          "Rain on ripe fruit drives berry splitting and sour rot — the forecast, not the sensors, is your harvest deadline."
        ),
      ];
      if (high || moderate)
        out.push(
          scout(
            "Scout tight or split clusters and wounded berries for gray mold or sour rot.",
            "Wounds from birds, insects and powdery mildew are the entry points; find hot spots before they spread."
          )
        );
      return out;
    }

    default:
      return [];
  }
}
