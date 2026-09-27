# Fertilizer partner data demo

## What is included

- A read-only dashboard at `/partner`
- Pseudonymized `Farm 1` and `Farm 2` views
- Raw temperature, humidity, and leaf-wetness readings
- Daily aggregates and latest per-device readings
- Transparent, evidence-linked decision-support recommendations
- Per-farm sensor and recommendation CSV exports
- A protected JSON API and OpenAPI description

The authorized ranges begin on:

- Farm 1: August 20, 2026
- Farm 2: September 14, 2026

The API never returns those internal farm IDs or customer-facing farm names. Partner responses use
only `farm-1`, `farm-2`, `Farm 1`, and `Farm 2`.

## Authentication

Send the partner key in either form:

```http
x-partner-api-key: YOUR_KEY
```

```http
Authorization: Bearer YOUR_KEY
```

Only the SHA-256 digest is stored in the production environment as `PARTNER_API_KEY_HASH`. The raw
key is stored locally outside the repository with file permissions restricted to the Mac user.

## API

```text
GET /v1/partner/farms
GET /v1/partner/farms/{farmKey}/summary
GET /v1/partner/farms/{farmKey}/readings?from={epochMs}&to={epochMs}&limit=1000&offset=0
GET /v1/partner/farms/{farmKey}/recommendations?from={epochMs}&to={epochMs}
GET /v1/partner/farms/{farmKey}/readings.csv
GET /v1/partner/farms/{farmKey}/recommendations.csv
GET /v1/partner/openapi.json
```

`from` and `to` are optional epoch-millisecond bounds. The server always clamps `from` to the
authorized start date. Raw JSON results are paginated; CSV exports contain the entire authorized
range up to the server-side safety limit.

## Recommendation methodology

Recommendations are deterministic records derived from daily sensor aggregates. Each record contains
the measured evidence that caused it. They support scouting, monitoring, and sensor-health decisions.
They are not fertilizer-rate or pesticide recommendations.

Temperature, humidity, and leaf-wetness sensors do not measure soil nutrients. Any fertilizer decision
should incorporate soil/tissue tests, crop stage, field observations, product labels, and qualified
agronomic advice.

Historical disease-risk screens were calculated on demand and were not archived before this partner
feature. The exported recommendation file therefore represents reproducible recommendations generated
from the stored readings using the current documented rules; it must not be described as an immutable
audit log of every message previously displayed in the mobile apps.

## Local verification

```bash
cd backend
npm run build
```

After deployment, verify authentication, both summaries, CSV downloads, and the OpenAPI document.
