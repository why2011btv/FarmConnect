import "dotenv/config";
import { assessVineyardDiseaseRisk } from "../services/grapeRiskService.js";

/**
 * Cross-check harness: NEWA has no public API for its disease-model output, so a fully automated
 * comparison is not possible. This runs OUR models on the coordinates of known Cornell NEWA grape
 * stations and prints the results in a form you can diff, by eye, against NEWA's website for the
 * same station — the practical, season-long validation the disclaimers refer to.
 *
 * NEWA runs black rot, Phomopsis and powdery mildew (NOT downy) with the SAME published models we
 * implement, so those three are the meaningful comparison. Differences come mostly from INPUTS —
 * NEWA uses a station's measured leaf wetness; we estimate it from RH (plus block sensor fusion in
 * the app). So this validates input fidelity more than the model math (which is unit-tested).
 *
 *   npm run validate-newa                       # default reference station(s)
 *   npm run validate-newa -- --bloom 2026-06-20 # anchor phenology
 *   npm run validate-newa -- --station "My Site,42.10,-76.90"
 */

type Station = { name: string; lat: number; lng: number };

// Known Cornell NEWA grape reference station(s). Add your own with --station "Name,lat,lng".
const DEFAULT_STATIONS: Station[] = [
  { name: "Geneva (Cornell AgriTech), NY", lat: 42.8807, lng: -77.0269 },
];

function parseArgs(argv: string[]): { bloom?: string; stations: Station[] } {
  const stations: Station[] = [];
  let bloom: string | undefined;
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === "--bloom") bloom = argv[++i];
    else if (argv[i] === "--station") {
      const [name, lat, lng] = (argv[++i] ?? "").split(",");
      if (name && lat && lng) stations.push({ name, lat: Number(lat), lng: Number(lng) });
    }
  }
  return { bloom, stations: stations.length ? stations : DEFAULT_STATIONS };
}

const COMPARE_KEYS = ["black_rot", "phomopsis", "powdery_mildew"];

async function main() {
  const { bloom, stations } = parseArgs(process.argv.slice(2));
  console.log("Cross-check: OUR models vs Cornell NEWA (compare these against https://newa.cornell.edu/grape-diseases)\n");
  console.log(bloom ? `Bloom date: ${bloom}\n` : "No bloom date set (phenology gates disabled).\n");

  for (const s of stations) {
    const a = await assessVineyardDiseaseRisk(s.lat, s.lng, { bloomDateIso: bloom ?? null });
    if (!a) { console.log(`${s.name}: weather unavailable`); continue; }
    console.log(`=== ${s.name}  (${s.lat}, ${s.lng}) ===`);
    console.log(`   GDD base50 (since Apr 1): ${a.gddBase50FromApr1}   phenology: ${a.phenology.stage}`);
    for (const key of COMPARE_KEYS) {
      const d = a.diseases.find((x) => x.key === key);
      if (d) console.log(`   ${d.name.padEnd(16)} OURS: ${d.level.toUpperCase().padEnd(15)} ${d.headline}`);
    }
    console.log("   -> Open NEWA for this station, read its black rot / Phomopsis / powdery risk, and record agreement.\n");
  }

  console.log("Log agreement/disagreement over the season. Persistent disagreement usually means an");
  console.log("input gap (measured vs estimated leaf wetness, biofix date), not the model math.");
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
