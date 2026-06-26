import { FastifyBaseLogger } from "fastify";

export type LatLng = { lat: number; lng: number };

export type VineyardSnapshot = {
  imageDataUrl: string;
  region: { centerLat: number; centerLng: number; latDelta: number; lngDelta: number };
};

export type BoundaryResult = {
  center: LatLng;
  /** Vine-area parcels. A real vineyard is often several disjoint blocks, so this is an array
   *  of polygons (each polygon is an array of vertices). May be empty (geocode-only). */
  parcels: LatLng[][];
  /** Acreage MEASURED from the parcels above (shoelace sum). 0 when no parcels. */
  measuredAcreage: number;
  /** Acreage REPORTED by the LLM from public knowledge of the named vineyard. Unverified. */
  reportedAcreage?: number;
  /** Short human note on the reported figure (e.g. "≈24.5 ac across two MA sites"). */
  reportedAcreageNote?: string;
  source: "osm" | "vision" | "geocode-only";
  note?: string;
};

const USER_AGENT = "FarmConnect/1.0 (vineyard boundary lookup; contact admin@farmconnect.local)";
const NOMINATIM_URL = "https://nominatim.openstreetmap.org/search";
const OVERPASS_URL = "https://overpass-api.de/api/interpreter";
const SQUARE_METERS_PER_ACRE = 4046.8564224;
const METERS_PER_DEGREE_LAT = 111_320;

/**
 * Resolve a vineyard name to its vine-area parcels + a researched acreage figure.
 *
 * Strategy:
 *   A. Geocode the name (OSM Nominatim) -> center coordinate.
 *   B. In PARALLEL:
 *      - Collect ALL nearby `landuse=vineyard` polygons (OSM Overpass) -> parcels[].
 *      - Ask the LLM for the vineyard's published acreage by name -> reportedAcreage (unverified).
 *   C. If OSM returns no parcels and a satellite snapshot was supplied, ask the vision LLM to
 *      trace the vine area -> a single parcel.
 *
 * measuredAcreage is always computed from whatever parcels we end up with (the map is the source
 * of truth for device count). reportedAcreage is context only. Throws only if geocoding fails AND
 * no snapshot fallback is available.
 */
export async function resolveVineyardBoundary(
  logger: FastifyBaseLogger,
  name: string,
  snapshot?: VineyardSnapshot
): Promise<BoundaryResult> {
  const center = await geocode(logger, name);
  if (!center) {
    if (snapshot) {
      const reported = await researchAcreage(logger, name).catch(() => null);
      return {
        center: { lat: snapshot.region.centerLat, lng: snapshot.region.centerLng },
        parcels: [],
        measuredAcreage: 0,
        reportedAcreage: reported?.acres,
        reportedAcreageNote: reported?.note,
        source: "geocode-only",
        note: "Could not geocode the vineyard name; using the current map center.",
      };
    }
    throw new Error("Could not locate a place matching that vineyard name.");
  }

  // B — OSM parcels and LLM acreage research, concurrently.
  const [parcelsSettled, reportedSettled] = await Promise.allSettled([
    fetchVineyardParcels(logger, center),
    researchAcreage(logger, name),
  ]);

  const reported = reportedSettled.status === "fulfilled" ? reportedSettled.value : null;
  let parcels =
    parcelsSettled.status === "fulfilled" && parcelsSettled.value ? parcelsSettled.value : [];

  if (parcels.length > 0) {
    return {
      center,
      parcels,
      measuredAcreage: totalAcres(parcels),
      reportedAcreage: reported?.acres,
      reportedAcreageNote: reported?.note,
      source: "osm",
    };
  }

  // C — vision fallback (single parcel) when OSM has nothing mapped.
  if (snapshot) {
    try {
      const visionBoundary = await traceBoundaryWithVision(logger, snapshot);
      if (visionBoundary && visionBoundary.length >= 3) {
        parcels = [visionBoundary];
        return {
          center,
          parcels,
          measuredAcreage: totalAcres(parcels),
          reportedAcreage: reported?.acres,
          reportedAcreageNote: reported?.note,
          source: "vision",
        };
      }
    } catch (error) {
      logger.warn({ error }, "Vision boundary extraction failed; returning geocode-only");
    }
  }

  return {
    center,
    parcels: [],
    measuredAcreage: 0,
    reportedAcreage: reported?.acres,
    reportedAcreageNote: reported?.note,
    source: "geocode-only",
    note: "Found the location but no vine boundary; draw or adjust it on the map.",
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

// MARK: - Step A: geocoding

async function geocode(logger: FastifyBaseLogger, name: string): Promise<LatLng | null> {
  const url = `${NOMINATIM_URL}?format=json&limit=1&q=${encodeURIComponent(name)}`;
  const response = await fetch(url, { headers: { "User-Agent": USER_AGENT, Accept: "application/json" } });
  if (!response.ok) {
    logger.warn({ status: response.status }, "Nominatim geocode failed");
    return null;
  }
  const data = (await response.json()) as Array<{ lat: string; lon: string }>;
  const first = data[0];
  if (!first) return null;
  const lat = Number(first.lat);
  const lng = Number(first.lon);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  return { lat, lng };
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

  // Drop slivers (mapping noise), sort nearest-first, cap the count, simplify each ring.
  const meaningful = parcels.filter((p) => polygonAcres(p) >= 0.25);
  const usable = meaningful.length > 0 ? meaningful : parcels;
  usable.sort((a, b) => distSq(centroid(a), center) - distSq(centroid(b), center));
  const maxParcels = 12;
  return usable.slice(0, maxParcels).map(simplifyRing);
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

// MARK: - Acreage research (LLM, by name — unverified)

/**
 * Ask the LLM for the named vineyard's published planted acreage. Returns null if not configured
 * or unknown. This is a REPORTED figure (the model's knowledge), shown to the user as context and
 * explicitly not used to drive device count.
 */
async function researchAcreage(
  logger: FastifyBaseLogger,
  name: string
): Promise<{ acres: number; note: string } | null> {
  const apiKey = process.env.OPENROUTER_API_KEY;
  if (!apiKey) return null;

  const baseUrl = process.env.OPENROUTER_BASE_URL ?? "https://openrouter.ai/api/v1";
  const model = process.env.OPENROUTER_CHAT_MODEL ?? "openai/gpt-4o";

  const prompt =
    `What is the total planted vineyard acreage of "${name}"? ` +
    "Use only facts you are reasonably confident about. If the vineyard has multiple sites, give the combined total. " +
    'Respond ONLY as compact JSON: {"acres": <number or null>, "note": "<short note, e.g. sites/uncertainty>"}. ' +
    "If you do not know, use null for acres. No prose outside the JSON.";

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
      logger.warn({ status: response.status }, "Acreage research request failed");
      return null;
    }
    const data = (await response.json()) as { choices?: Array<{ message?: { content?: string } }> };
    const content = data.choices?.[0]?.message?.content?.trim();
    if (!content) return null;
    const match = content.match(/\{[\s\S]*\}/);
    const parsed = JSON.parse(match ? match[0] : content) as { acres?: unknown; note?: unknown };
    const acres = Number(parsed.acres);
    if (!Number.isFinite(acres) || acres <= 0) return null;
    const note = typeof parsed.note === "string" ? parsed.note : "";
    return { acres, note };
  } catch (error) {
    logger.warn({ error }, "Acreage research failed");
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
