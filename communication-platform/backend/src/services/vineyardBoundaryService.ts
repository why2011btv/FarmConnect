import { FastifyBaseLogger } from "fastify";

export type LatLng = { lat: number; lng: number };

export type VineyardSnapshot = {
  imageDataUrl: string;
  region: { centerLat: number; centerLng: number; latDelta: number; lngDelta: number };
};

/** One geocoding candidate the user can pick from. */
export type PlaceCandidate = {
  label: string;
  lat: number;
  lng: number;
  /** OSM place class/type, e.g. "tourism/winery", "landuse/vineyard" — helps the user choose. */
  kind?: string;
};

/** Researched, unverified facts about the named vineyard (LLM knowledge + website). */
export type VineyardResearch = {
  reportedAcreage?: number;
  acreageNote?: string;
  grapeVarieties?: string[];
  ownership?: string;
  founded?: string;
  region?: string;
  summary?: string;
  /** Official website URL, if known — shown in the card and used to deepen research. */
  officialWebsite?: string;
  /** Best-known street address (used as a geocode fallback when the name doesn't resolve). */
  address?: string;
  /** Best-known coordinates from research, offered as a pick candidate when OSM geocoding fails. */
  latitude?: number;
  longitude?: number;
};

export type SearchResult = {
  candidates: PlaceCandidate[];
  research?: VineyardResearch;
};

export type BoundaryResult = {
  center: LatLng;
  /** Vine-area parcels. A real vineyard is often several disjoint blocks, so this is an array
   *  of polygons (each polygon is an array of vertices). May be empty (geocode-only). */
  parcels: LatLng[][];
  /** Acreage MEASURED from the parcels above (shoelace sum). 0 when no parcels. */
  measuredAcreage: number;
  source: "osm" | "vision" | "geocode-only";
  note?: string;
};

const USER_AGENT = "FarmConnect/1.0 (vineyard boundary lookup; contact admin@farmconnect.local)";
const NOMINATIM_URL = "https://nominatim.openstreetmap.org/search";
const OVERPASS_URL = "https://overpass-api.de/api/interpreter";
const SQUARE_METERS_PER_ACRE = 4046.8564224;
const METERS_PER_DEGREE_LAT = 111_320;

/**
 * Step 1 of the flow: turn a typed name into a LIST of location candidates the user can pick from,
 * plus a researched info card. Geocoding is fuzzy (multiple queries, no exact match required), so
 * the user is never blocked by "could not locate".
 */
export async function searchVineyard(logger: FastifyBaseLogger, name: string): Promise<SearchResult> {
  const [candidatesSettled, researchSettled] = await Promise.allSettled([
    geocodeCandidates(logger, name),
    researchVineyard(logger, name),
  ]);

  const candidates = candidatesSettled.status === "fulfilled" ? candidatesSettled.value : [];
  const research = researchSettled.status === "fulfilled" ? researchSettled.value ?? undefined : undefined;

  // Augment with research-derived locations so the user is never stuck on "No locations found"
  // when the LLM clearly knows the vineyard but Nominatim didn't return a name match.
  await augmentCandidatesFromResearch(logger, candidates, research);

  return { candidates, research };
}

/**
 * Ensure there is always something pickable when research knows the place. Adds (a) the research's
 * own lat/lng if present, and (b) a geocode of the research's address string — both deduped against
 * existing OSM candidates. These are appended (lower priority) so real OSM POIs still rank first.
 */
async function augmentCandidatesFromResearch(
  logger: FastifyBaseLogger,
  candidates: PlaceCandidate[],
  research?: VineyardResearch
): Promise<void> {
  if (!research) return;
  const near = (lat: number, lng: number) =>
    candidates.some((c) => Math.abs(c.lat - lat) < 0.01 && Math.abs(c.lng - lng) < 0.01);

  // (a) Research-provided coordinates.
  if (
    typeof research.latitude === "number" &&
    typeof research.longitude === "number" &&
    Number.isFinite(research.latitude) &&
    Number.isFinite(research.longitude) &&
    !near(research.latitude, research.longitude)
  ) {
    candidates.push({
      label: research.address ?? researchLocationLabel(research),
      lat: research.latitude,
      lng: research.longitude,
      kind: "research/location",
    });
  }

  // (b) Geocode the research's address string (often resolves when the bare name doesn't).
  if (research.address && candidates.length === 0) {
    try {
      const fromAddress = await geocodeCandidates(logger, research.address);
      for (const c of fromAddress) {
        if (!near(c.lat, c.lng)) candidates.push(c);
      }
    } catch (error) {
      logger.warn({ error }, "Address geocode fallback failed");
    }
  }
}

function researchLocationLabel(r: VineyardResearch): string {
  return r.region ? `Reported location · ${r.region}` : "Reported location";
}

/**
 * Step 2 of the flow: given a CHOSEN center (from a picked candidate), find the vine-area parcels.
 *   A. Collect ALL nearby `landuse=vineyard` polygons (OSM Overpass) -> parcels[].
 *   B. If OSM has nothing and a satellite snapshot was supplied, ask the vision LLM to trace it.
 * measuredAcreage is computed from whatever parcels we end up with. Never throws for "not found":
 * returns `source: "geocode-only"` with empty parcels so the client can seed an editable box.
 */
export async function resolveVineyardBoundary(
  logger: FastifyBaseLogger,
  center: LatLng,
  snapshot?: VineyardSnapshot
): Promise<BoundaryResult> {
  // A — OSM parcels near the chosen center.
  try {
    const parcels = await fetchVineyardParcels(logger, center);
    if (parcels.length > 0) {
      return { center, parcels, measuredAcreage: totalAcres(parcels), source: "osm" };
    }
  } catch (error) {
    logger.warn({ error }, "Overpass vineyard parcel lookup failed; continuing to fallbacks");
  }

  // B — vision fallback (single parcel) when OSM has nothing mapped.
  if (snapshot) {
    try {
      const visionBoundary = await traceBoundaryWithVision(logger, snapshot);
      if (visionBoundary && visionBoundary.length >= 3) {
        const parcels = [visionBoundary];
        return { center, parcels, measuredAcreage: totalAcres(parcels), source: "vision" };
      }
    } catch (error) {
      logger.warn({ error }, "Vision boundary extraction failed; returning geocode-only");
    }
  }

  return {
    center,
    parcels: [],
    measuredAcreage: 0,
    source: "geocode-only",
    note: "No vine boundary found here; draw or adjust it on the map.",
  };
}

// MARK: - Acreage (shoelace on equirectangular projection)

function polygonAcres(poly: LatLng[]): number {
  if (poly.length < 3) return 0;
  const lat0 = poly.reduce((s, p) => s + p.lat, 0) / poly.length;
  const mPerLng = METERS_PER_DEGREE_LAT * Math.cos((lat0 * Math.PI) / 180);
  const lng0 = poly[0].lng;
  const pts = poly.map((p) => ({
    x: (p.lng - lng0) * mPerLng,
    y: (p.lat - lat0) * METERS_PER_DEGREE_LAT,
  }));
  let sum = 0;
  for (let i = 0; i < pts.length; i++) {
    const a = pts[i];
    const b = pts[(i + 1) % pts.length];
    sum += a.x * b.y - b.x * a.y;
  }
  return Math.abs(sum) / 2 / SQUARE_METERS_PER_ACRE;
}

function totalAcres(parcels: LatLng[][]): number {
  return parcels.reduce((s, p) => s + polygonAcres(p), 0);
}

// MARK: - Geocoding (multiple fuzzy candidates)

type NominatimRow = {
  lat: string;
  lon: string;
  display_name?: string;
  class?: string;
  type?: string;
  importance?: number;
};

/**
 * Return up to ~8 location candidates for a typed name. We run several query variants (raw name,
 * name + "vineyard", name + "winery") because a vineyard is often tagged as a winery/tourism POI
 * rather than the literal name, then merge + dedupe. This replaces the old single exact-match.
 */
async function geocodeCandidates(logger: FastifyBaseLogger, name: string): Promise<PlaceCandidate[]> {
  const trimmed = name.trim();
  const queries = Array.from(
    new Set([
      trimmed,
      /vineyard|winery|estate/i.test(trimmed) ? trimmed : `${trimmed} vineyard`,
      /vineyard|winery|estate/i.test(trimmed) ? trimmed : `${trimmed} winery`,
    ])
  );

  const rows: NominatimRow[] = [];
  for (const q of queries) {
    try {
      const url = `${NOMINATIM_URL}?format=json&limit=6&addressdetails=0&q=${encodeURIComponent(q)}`;
      const response = await fetch(url, { headers: { "User-Agent": USER_AGENT, Accept: "application/json" } });
      if (!response.ok) {
        logger.warn({ status: response.status, q }, "Nominatim search failed");
        continue;
      }
      const data = (await response.json()) as NominatimRow[];
      rows.push(...data);
    } catch (error) {
      logger.warn({ error, q }, "Nominatim search threw");
    }
  }

  const candidates: PlaceCandidate[] = [];
  const seen = new Set<string>();
  for (const r of rows) {
    const lat = Number(r.lat);
    const lng = Number(r.lon);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;
    // Dedupe places within ~150m of each other.
    const key = `${lat.toFixed(3)},${lng.toFixed(3)}`;
    if (seen.has(key)) continue;
    seen.add(key);
    candidates.push({
      label: r.display_name ?? `${lat.toFixed(4)}, ${lng.toFixed(4)}`,
      lat,
      lng,
      kind: r.class && r.type ? `${r.class}/${r.type}` : r.type ?? r.class,
    });
  }

  // Vineyard/winery/farm POIs first, then by OSM importance.
  candidates.sort((a, b) => rankKind(b.kind) - rankKind(a.kind));
  return candidates.slice(0, 8);
}

function rankKind(kind?: string): number {
  if (!kind) return 0;
  if (/vineyard/i.test(kind)) return 3;
  if (/winery|farm|orchard/i.test(kind)) return 2;
  if (/tourism|attraction/i.test(kind)) return 1;
  return 0;
}

// MARK: - Step B: OSM vineyard parcels

/**
 * Overpass query: ALL vineyard-tagged ways/relations within ~3km of the center, with geometry.
 * Returns every distinct parcel (outer ring) as lat/lng vertices — a real vineyard is often
 * several disjoint blocks. Parcels are sorted nearest-first and capped to keep the payload sane.
 */
async function fetchVineyardParcels(logger: FastifyBaseLogger, center: LatLng): Promise<LatLng[][]> {
  const radiusMeters = 3000;
  const query = `
    [out:json][timeout:25];
    (
      way["landuse"="vineyard"](around:${radiusMeters},${center.lat},${center.lng});
      relation["landuse"="vineyard"](around:${radiusMeters},${center.lat},${center.lng});
    );
    out geom;
  `;

  const response = await fetch(OVERPASS_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded", "User-Agent": USER_AGENT },
    body: `data=${encodeURIComponent(query)}`,
  });
  if (!response.ok) {
    logger.warn({ status: response.status }, "Overpass request failed");
    return [];
  }

  const data = (await response.json()) as {
    elements?: Array<{
      type: string;
      geometry?: Array<{ lat: number; lon: number }>;
      members?: Array<{ role?: string; geometry?: Array<{ lat: number; lon: number }> }>;
    }>;
  };

  const parcels: LatLng[][] = [];
  for (const el of data.elements ?? []) {
    if (el.geometry && el.geometry.length >= 3) {
      parcels.push(el.geometry.map((p) => ({ lat: p.lat, lng: p.lon })));
    } else if (el.members) {
      for (const m of el.members) {
        if (m.role === "outer" && m.geometry && m.geometry.length >= 3) {
          parcels.push(m.geometry.map((p) => ({ lat: p.lat, lng: p.lon })));
        }
      }
    }
  }
  if (parcels.length === 0) return [];

  // Drop slivers (mapping noise).
  const meaningful = parcels.filter((p) => polygonAcres(p) >= 0.25);
  const usable = meaningful.length > 0 ? meaningful : parcels;

  // Keep only the cluster that belongs to THIS vineyard. A 3km search radius can pull in a
  // neighboring vineyard's blocks, which appear as a separate far-away cluster. We grow a single
  // cluster outward from the parcel nearest the chosen center, keeping a parcel only if it is
  // within ~600m of one already in the cluster (single-linkage). Disconnected clusters are dropped.
  const clustered = clusterAroundCenter(usable, center, 600);

  // Observability: if the nearest parcel is far from the chosen point, the chosen POI may be off
  // the vines (e.g. a tasting room) and clustering could be lossy — surface it in logs.
  if (clustered.length > 0 && metersBetween(centroid(clustered[0]), center) > 800) {
    logger.warn(
      { meters: Math.round(metersBetween(centroid(clustered[0]), center)) },
      "Nearest vineyard parcel is far from the chosen location; clustering may be lossy"
    );
  }

  clustered.sort((a, b) => distSq(centroid(a), center) - distSq(centroid(b), center));
  const maxParcels = 16;
  return clustered.slice(0, maxParcels).map(simplifyRing);
}

/** Approx distance in meters between two coordinates (equirectangular; fine at vineyard scale). */
function metersBetween(a: LatLng, b: LatLng): number {
  const mPerLng = METERS_PER_DEGREE_LAT * Math.cos((((a.lat + b.lat) / 2) * Math.PI) / 180);
  const dx = (a.lng - b.lng) * mPerLng;
  const dy = (a.lat - b.lat) * METERS_PER_DEGREE_LAT;
  return Math.hypot(dx, dy);
}

/**
 * Single-linkage cluster grown from the parcel nearest `center`. A parcel joins the cluster if its
 * centroid is within `gapMeters` of ANY parcel already in the cluster. Returns just that cluster,
 * so unrelated vineyards farther away (separate clusters) are excluded.
 */
function clusterAroundCenter(parcels: LatLng[][], center: LatLng, gapMeters: number): LatLng[][] {
  if (parcels.length <= 1) return parcels;
  const centroids = parcels.map(centroid);

  // Seed: parcel nearest the chosen center.
  let seed = 0;
  let best = Infinity;
  for (let i = 0; i < centroids.length; i++) {
    const d = distSq(centroids[i], center);
    if (d < best) {
      best = d;
      seed = i;
    }
  }

  const inCluster = new Array(parcels.length).fill(false);
  inCluster[seed] = true;
  const queue = [seed];
  while (queue.length > 0) {
    const i = queue.pop()!;
    for (let j = 0; j < parcels.length; j++) {
      if (inCluster[j]) continue;
      if (metersBetween(centroids[i], centroids[j]) <= gapMeters) {
        inCluster[j] = true;
        queue.push(j);
      }
    }
  }

  return parcels.filter((_, i) => inCluster[i]);
}

function distSq(a: LatLng, b: LatLng): number {
  return (a.lat - b.lat) ** 2 + (a.lng - b.lng) ** 2;
}

function centroid(poly: LatLng[]): LatLng {
  let lat = 0;
  let lng = 0;
  for (const p of poly) {
    lat += p.lat;
    lng += p.lng;
  }
  return { lat: lat / poly.length, lng: lng / poly.length };
}

// MARK: - Vineyard research (LLM, by name — unverified)

/**
 * Ask the LLM for an info card about the named vineyard: acreage, grape varieties, ownership,
 * founding, region, and a one-line summary. All fields optional; the model is told to use null
 * when unsure. This is REPORTED knowledge shown to the user as context — acreage here never
 * drives device count (the mapped area does). Returns null if not configured.
 */
async function researchVineyard(
  logger: FastifyBaseLogger,
  name: string
): Promise<VineyardResearch | null> {
  const apiKey = process.env.OPENROUTER_API_KEY;
  if (!apiKey) return null;

  const baseUrl = process.env.OPENROUTER_BASE_URL ?? "https://openrouter.ai/api/v1";
  const model = process.env.OPENROUTER_CHAT_MODEL ?? "openai/gpt-4o";

  const prompt =
    `Give a factual profile of the vineyard/winery "${name}". Prefer facts from the vineyard's ` +
    "OWN OFFICIAL WEBSITE (find it; it is usually the most accurate source for acreage, varieties, " +
    "ownership, and history), then reputable wine directories. Use only facts you are reasonably " +
    "confident about; use null for anything you are unsure of (do not guess). If it has multiple " +
    "sites, give the combined planted acreage and note the sites. Provide the official website URL, " +
    "the best-known street address, and approximate coordinates (decimal degrees) of the main site. " +
    "Respond ONLY as compact JSON with this exact shape:\n" +
    '{"reportedAcreage": <number|null>, "acreageNote": <string|null>, ' +
    '"grapeVarieties": <string[]|null>, "ownership": <string|null>, "founded": <string|null>, ' +
    '"region": <string|null>, "officialWebsite": <string|null>, "address": <string|null>, ' +
    '"latitude": <number|null>, "longitude": <number|null>, "summary": <string|null>}\n' +
    "summary is one or two sentences. No prose outside the JSON.";

  try {
    const response = await fetch(`${baseUrl}/chat/completions`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
        "HTTP-Referer": "https://farmalert.local",
        "X-Title": process.env.OPENROUTER_APP_NAME ?? "FarmAlert",
      },
      body: JSON.stringify({
        model,
        temperature: 0,
        messages: [{ role: "user", content: prompt }],
      }),
    });
    if (!response.ok) {
      logger.warn({ status: response.status }, "Vineyard research request failed");
      return null;
    }
    const data = (await response.json()) as { choices?: Array<{ message?: { content?: string } }> };
    const content = data.choices?.[0]?.message?.content?.trim();
    if (!content) return null;
    const match = content.match(/\{[\s\S]*\}/);
    const parsed = JSON.parse(match ? match[0] : content) as Record<string, unknown>;

    const asString = (v: unknown): string | undefined =>
      typeof v === "string" && v.trim().length > 0 ? v.trim() : undefined;
    const asFiniteNumber = (v: unknown): number | undefined => {
      const n = Number(v);
      return Number.isFinite(n) ? n : undefined;
    };
    const acres = Number(parsed.reportedAcreage);
    const varieties = Array.isArray(parsed.grapeVarieties)
      ? parsed.grapeVarieties.filter((v): v is string => typeof v === "string" && v.trim().length > 0)
      : undefined;

    const lat = asFiniteNumber(parsed.latitude);
    const lng = asFiniteNumber(parsed.longitude);
    const validCoords =
      lat !== undefined && lng !== undefined && Math.abs(lat) <= 90 && Math.abs(lng) <= 180;

    const research: VineyardResearch = {
      reportedAcreage: Number.isFinite(acres) && acres > 0 ? acres : undefined,
      acreageNote: asString(parsed.acreageNote),
      grapeVarieties: varieties && varieties.length > 0 ? varieties : undefined,
      ownership: asString(parsed.ownership),
      founded: asString(parsed.founded),
      region: asString(parsed.region),
      officialWebsite: asString(parsed.officialWebsite),
      address: asString(parsed.address),
      latitude: validCoords ? lat : undefined,
      longitude: validCoords ? lng : undefined,
      summary: asString(parsed.summary),
    };
    // Return null only if literally nothing came back.
    const hasAny = Object.values(research).some((v) => v !== undefined);
    return hasAny ? research : null;
  } catch (error) {
    logger.warn({ error }, "Vineyard research failed");
    return null;
  }
}

/** Drop a closing duplicate vertex and cap vertex count so the editable boundary stays manageable. */
function simplifyRing(poly: LatLng[]): LatLng[] {
  let ring = poly;
  const first = ring[0];
  const last = ring[ring.length - 1];
  if (ring.length > 1 && first.lat === last.lat && first.lng === last.lng) {
    ring = ring.slice(0, -1);
  }
  const maxVertices = 24;
  if (ring.length <= maxVertices) return ring;
  const step = ring.length / maxVertices;
  const result: LatLng[] = [];
  for (let i = 0; i < maxVertices; i++) {
    result.push(ring[Math.floor(i * step)]);
  }
  return result;
}

// MARK: - Step C: vision fallback

async function traceBoundaryWithVision(
  logger: FastifyBaseLogger,
  snapshot: VineyardSnapshot
): Promise<LatLng[] | null> {
  const apiKey = process.env.OPENROUTER_API_KEY;
  if (!apiKey) {
    logger.warn("Vision fallback skipped: OPENROUTER_API_KEY not configured");
    return null;
  }

  const baseUrl = process.env.OPENROUTER_BASE_URL ?? "https://openrouter.ai/api/v1";
  const model = process.env.OPENROUTER_CHAT_MODEL ?? "openai/gpt-4o";

  const prompt =
    "This is a satellite image of farmland. Identify the main contiguous VINEYARD area " +
    "(planted grape vines show as regular parallel rows of vegetation). EXCLUDE buildings, " +
    "houses, roads, forest, water, and bare ground. Return ONLY a compact JSON object of the " +
    "form {\"points\":[[x,y],...]} tracing the vineyard's outer boundary as a polygon, where x " +
    "and y are normalized image coordinates in [0,1] (x = left->right, y = top->bottom). " +
    "Use 4 to 12 points in clockwise order. If you cannot identify any vineyard, return " +
    '{"points":[]}. Output JSON only, no prose.';

  const response = await fetch(`${baseUrl}/chat/completions`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      "HTTP-Referer": "https://farmalert.local",
      "X-Title": process.env.OPENROUTER_APP_NAME ?? "FarmAlert",
    },
    body: JSON.stringify({
      model,
      temperature: 0,
      messages: [
        {
          role: "user",
          content: [
            { type: "text", text: prompt },
            { type: "image_url", image_url: { url: snapshot.imageDataUrl } },
          ],
        },
      ],
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    logger.warn({ status: response.status, body }, "Vision boundary request failed");
    return null;
  }

  const data = (await response.json()) as { choices?: Array<{ message?: { content?: string } }> };
  const content = data.choices?.[0]?.message?.content?.trim();
  if (!content) return null;

  const points = parseNormalizedPoints(content);
  if (!points || points.length < 3) return null;

  // Convert normalized [0,1] image coords to geographic coords using the snapshot region.
  // Image y grows downward (top = north), so latitude decreases with y.
  const { centerLat, centerLng, latDelta, lngDelta } = snapshot.region;
  return points.map(([x, y]) => ({
    lat: centerLat + (0.5 - y) * latDelta,
    lng: centerLng + (x - 0.5) * lngDelta,
  }));
}

function parseNormalizedPoints(content: string): Array<[number, number]> | null {
  // Tolerate code fences / surrounding prose by extracting the first {...} block.
  const match = content.match(/\{[\s\S]*\}/);
  const jsonText = match ? match[0] : content;
  try {
    const parsed = JSON.parse(jsonText) as { points?: unknown };
    if (!Array.isArray(parsed.points)) return null;
    const points: Array<[number, number]> = [];
    for (const p of parsed.points) {
      if (Array.isArray(p) && p.length >= 2) {
        const x = Number(p[0]);
        const y = Number(p[1]);
        if (Number.isFinite(x) && Number.isFinite(y)) {
          points.push([clamp01(x), clamp01(y)]);
        }
      }
    }
    return points;
  } catch {
    return null;
  }
}

function clamp01(v: number): number {
  return Math.min(1, Math.max(0, v));
}
