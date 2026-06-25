import { FastifyBaseLogger } from "fastify";

export type LatLng = { lat: number; lng: number };

export type VineyardSnapshot = {
  imageDataUrl: string;
  region: { centerLat: number; centerLng: number; latDelta: number; lngDelta: number };
};

export type BoundaryResult = {
  center: LatLng;
  boundary: LatLng[];
  source: "osm" | "vision" | "geocode-only";
  note?: string;
};

const USER_AGENT = "FarmConnect/1.0 (vineyard boundary lookup; contact admin@farmconnect.local)";
const NOMINATIM_URL = "https://nominatim.openstreetmap.org/search";
const OVERPASS_URL = "https://overpass-api.de/api/interpreter";

/**
 * Resolve a vineyard name to a best-effort vine-area boundary.
 *
 * Strategy, in order:
 *   A. Geocode the name (OSM Nominatim) -> center coordinate.
 *   B. Look for a nearby `landuse=vineyard` polygon (OSM Overpass) -> boundary.
 *   C. If no polygon and a satellite snapshot was supplied, ask the vision LLM to trace the
 *      vine boundary -> boundary.
 * Throws only if geocoding fails AND no snapshot fallback is available. Otherwise returns
 * `source: "geocode-only"` with an empty boundary so the client can seed an editable default box.
 */
export async function resolveVineyardBoundary(
  logger: FastifyBaseLogger,
  name: string,
  snapshot?: VineyardSnapshot
): Promise<BoundaryResult> {
  const center = await geocode(logger, name);
  if (!center) {
    // Fall back to the snapshot region center if geocoding fails entirely.
    if (snapshot) {
      return {
        center: { lat: snapshot.region.centerLat, lng: snapshot.region.centerLng },
        boundary: [],
        source: "geocode-only",
        note: "Could not geocode the vineyard name; using the current map center.",
      };
    }
    throw new Error("Could not locate a place matching that vineyard name.");
  }

  // B — OSM vineyard polygon near the geocoded center.
  try {
    const osmBoundary = await fetchVineyardPolygon(logger, center);
    if (osmBoundary && osmBoundary.length >= 3) {
      return { center, boundary: osmBoundary, source: "osm" };
    }
  } catch (error) {
    logger.warn({ error }, "Overpass vineyard polygon lookup failed; continuing to fallbacks");
  }

  // C — vision fallback (only if the client sent a satellite snapshot).
  if (snapshot) {
    try {
      const visionBoundary = await traceBoundaryWithVision(logger, snapshot);
      if (visionBoundary && visionBoundary.length >= 3) {
        return { center, boundary: visionBoundary, source: "vision" };
      }
    } catch (error) {
      logger.warn({ error }, "Vision boundary extraction failed; returning geocode-only");
    }
  }

  return {
    center,
    boundary: [],
    source: "geocode-only",
    note: "Found the location but no vine boundary; draw or adjust it on the map.",
  };
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

// MARK: - Step B: OSM vineyard polygon

/**
 * Overpass query: vineyard-tagged ways/relations within ~1.5km of the center, with geometry.
 * Returns the polygon (outer ring) closest to the center, as lat/lng vertices.
 */
async function fetchVineyardPolygon(logger: FastifyBaseLogger, center: LatLng): Promise<LatLng[] | null> {
  const radiusMeters = 1500;
  const query = `
    [out:json][timeout:20];
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
    return null;
  }

  const data = (await response.json()) as {
    elements?: Array<{
      type: string;
      geometry?: Array<{ lat: number; lon: number }>;
      members?: Array<{ role?: string; geometry?: Array<{ lat: number; lon: number }> }>;
    }>;
  };

  const candidates: LatLng[][] = [];
  for (const el of data.elements ?? []) {
    if (el.geometry && el.geometry.length >= 3) {
      candidates.push(el.geometry.map((p) => ({ lat: p.lat, lng: p.lon })));
    } else if (el.members) {
      for (const m of el.members) {
        if (m.role === "outer" && m.geometry && m.geometry.length >= 3) {
          candidates.push(m.geometry.map((p) => ({ lat: p.lat, lng: p.lon })));
        }
      }
    }
  }
  if (candidates.length === 0) return null;

  // Pick the polygon whose centroid is nearest the geocoded center.
  let best = candidates[0];
  let bestDist = Number.POSITIVE_INFINITY;
  for (const poly of candidates) {
    const c = centroid(poly);
    const d = (c.lat - center.lat) ** 2 + (c.lng - center.lng) ** 2;
    if (d < bestDist) {
      bestDist = d;
      best = poly;
    }
  }
  return simplifyRing(best);
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
