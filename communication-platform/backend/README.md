# Backend (Communication Platform)

Fastify + TypeScript API scaffold for TestFlight MVP.

## Run locally

```bash
cd communication-platform/backend
cp .env.example .env
docker compose up -d
npm install
npm run migrate
npm run dev
```

Server defaults:

- `http://localhost:4000`
- Health check: `GET /health`

## API endpoints

- `POST /v1/auth/signup` (email + password)
- `POST /v1/auth/login` (email + password; legacy `username` still accepted)
- `GET /v1/auth/me`
- `POST /v1/auth/forgot-password` / `POST /v1/auth/reset-password`
- `POST /v1/auth/verify-email` / `POST /v1/auth/resend-verification`
- `POST /v1/auth/email` (attach an address to a pre-email account; requires current password)
- `GET /v1/admin/farms`, `POST /v1/admin/farms` (staff only)
- `GET /v1/admin/farms/:farmId`, `POST /v1/admin/farms/:farmId/codes`
- `DELETE /v1/admin/farms/:farmId/codes/:codeId`, `DELETE /v1/admin/farms/:farmId/members/:userId`
- `POST /v1/admin/devices/:deviceId/rotate-key`
- `GET /v1/farms` (auth required)
- `POST /v1/farms/claim` (redeem a farm access code)
- `GET|POST /v1/farms/:farmId/codes`, `DELETE /v1/farms/:farmId/codes/:codeId` (owner only)
- `GET /v1/farms/:farmId/members`, `DELETE /v1/farms/:farmId/members/:userId`
- `GET /v1/posts`
- `POST /v1/posts`
- `POST /v1/posts/:postId/upvote`
- `POST /v1/posts/:postId/comments`
- `GET /v1/conversations` (auth required)
- `GET /v1/messages?otherUserId=<id>` (auth required)
- `POST /v1/messages`
- `POST /v1/uploads/create`
- `POST /v1/notifications/register-device`
- `POST /v1/notifications/send`
- `POST /v1/uploads/image` (multipart, auth required)
- `GET /v1/sensors/overview` (auth required)
- `POST /v1/sensors/ingest` (Raspberry Pi ingest, API key required)

## Notes

- Uses Postgres repositories and SQL migrations.
- Seed data is included in `migrations/002_seed.sql`.
- Session tokens are stored in `auth_sessions` (migration `003_auth_sessions.sql`).
- APNs delivery is wired via token-based auth key env vars (see `.env.example`).
- Uploaded images are stored in Cloudflare R2 when `R2_*` env vars are configured.
- Sensor ingest prefers per-device keys (`x-device-key`); the shared `SENSOR_INGEST_API_KEY`
  (`x-sensor-key`) is a legacy fallback limited to the legacy farm.
- Content moderation guard (text + image URLs) can be enabled via OpenRouter env vars.

## APNs setup (for TestFlight)

Set these in `.env`:

- `APNS_KEY_ID`
- `APNS_TEAM_ID`
- `APNS_BUNDLE_ID`
- `APNS_PRIVATE_KEY` (single-line with `\n` escapes)
- `APNS_USE_PRODUCTION=true` for TestFlight/App Store builds

## Cloudflare R2 storage setup

Set these in `.env` (or Railway variables):

- `R2_BUCKET`
- `R2_ENDPOINT` (for example: `https://<accountid>.r2.cloudflarestorage.com`)
- `R2_ACCESS_KEY_ID`
- `R2_SECRET_ACCESS_KEY`
- `R2_PUBLIC_BASE_URL` (for example: `https://<public-r2-url>.r2.dev`)

## OpenRouter moderation guard (optional)

Set these in backend env / Railway variables to enable automatic toxic/sexual content blocking:

- `OPENROUTER_API_KEY`
- `OPENROUTER_MODERATION_MODEL` (recommended: `openai/gpt-4o-mini`)
- `OPENROUTER_BASE_URL` (default: `https://openrouter.ai/api/v1`)
- `OPENROUTER_APP_NAME` (default: `FarmAlert`)

When enabled, the backend moderates:

- Post title/body/crop + post images
- Post comments
- Chat messages

If content is blocked, the API returns:

- `400` with `error: "Content violates platform rule: ..."`

## Raspberry Pi sensor ingestion (beginner setup)

### 1) Configure backend secret

Set this in Railway backend variables:

- `SENSOR_INGEST_API_KEY` = a long random secret string

### 2) Send test payload with curl

```bash
curl -X POST "https://<your-backend-domain>/v1/sensors/ingest" \
  -H "Content-Type: application/json" \
  -H "x-sensor-key: <SENSOR_INGEST_API_KEY>" \
  -d '{
    "deviceId": "pi-node-1",
    "deviceName": "Raspberry Pi Node 1",
    "farmName": "Persephone Farm",
    "locationLabel": "North Plot",
    "status": "online",
    "readings": [
      { "sensorType": "soil_moisture", "value": 37.2, "unit": "%" },
      { "sensorType": "temperature", "value": 24.8, "unit": "C" },
      { "sensorType": "humidity", "value": 62.1, "unit": "%" }
    ]
  }'
```

If successful, app sensor dashboard (`/v1/sensors/overview`) will show latest values.

### 3) Raspberry Pi Python example

Install dependency:

```bash
pip install requests
```

Example script (`send_sensor_data.py`):

```python
import time
import random
import requests

BACKEND_URL = "https://<your-backend-domain>/v1/sensors/ingest"
INGEST_KEY = "<SENSOR_INGEST_API_KEY>"

def read_sensors():
    # Replace this block with real sensor reads
    return {
        "soil_moisture": round(random.uniform(20, 60), 1),
        "temperature": round(random.uniform(18, 32), 1),
        "humidity": round(random.uniform(35, 80), 1),
    }

while True:
    values = read_sensors()
    payload = {
        "deviceId": "pi-node-1",
        "deviceName": "Raspberry Pi Node 1",
        "farmName": "Persephone Farm",
        "locationLabel": "North Plot",
        "status": "online",
        "readings": [
            {"sensorType": "soil_moisture", "value": values["soil_moisture"], "unit": "%"},
            {"sensorType": "temperature", "value": values["temperature"], "unit": "C"},
            {"sensorType": "humidity", "value": values["humidity"], "unit": "%"},
        ],
    }

    try:
        r = requests.post(
            BACKEND_URL,
            json=payload,
            headers={"x-sensor-key": INGEST_KEY},
            timeout=10,
        )
        print(r.status_code, r.text)
    except Exception as e:
        print("send failed:", e)

    time.sleep(60)  # send every 60 seconds
```

## Multi-tenancy: farms, access codes and device keys

**→ Full shipping & onboarding guide: [../SHIPPING.md](../SHIPPING.md)**

Devices belong to a **farm**. Users join a farm by redeeming an **access code**, and
`GET /v1/sensors/overview` returns only devices from farms the caller has joined. A user with no
membership sees nothing — this is the boundary that keeps one customer out of another's vineyard.

### Provisioning a customer before shipping

Normally you do this from the **Admin tab in the app** — it is staff-only and does exactly what the
CLI does. See "Admin access" below.

The CLI remains for scripting and for when the app isn't handy:

```bash
npm run provision -- --farm "Smith Vineyard" --nodes 8
```

It has to run where `DATABASE_URL` resolves, i.e. on the Railway container:

```bash
railway ssh --project=<project> --environment=<env> --service=<service> \
  'cd /app && npm run provision -- --farm "Smith Vineyard" --nodes 8'
```

This prints, once and never again:

- the **access code** (`PB-XXXX-XXXX-XXXX-XXXX`) to print on the card in the box, and
- a **per-node ingest key** to flash onto each node.

Only hashes are stored, so lost secrets must be reissued rather than recovered:

```bash
npm run provision -- --farm-id farm_ab12cd --add-code --label "replacement card"
```

The first person to redeem a code joins as `member`. Promote them so they can manage codes and
remove crew members:

```sql
UPDATE farm_members SET role = 'owner' WHERE farm_id = '<farm>' AND user_id = '<user>';
```

### Admin access

Set `ADMIN_BOOTSTRAP_EMAILS` (comma-separated) in the Railway dashboard. Any listed address is
granted staff on its next sign-in — so the first admin is created without touching the database.
Removing an address does not demote an existing admin; clear the flag explicitly:

```sql
UPDATE users SET is_admin = FALSE WHERE LOWER(email) = 'someone@example.com';
```

Staff see an **Admin** tab in the app with every customer farm, node status, who has access, and
buttons to provision a farm, issue or revoke access codes, remove a member, and rotate a node key.
Admin endpoints answer `404` to everyone else, so the surface is invisible rather than merely
locked. Secrets are displayed once, on a screen that requires an explicit acknowledgement before it
can be dismissed.

### Access code design

- 16 characters of Crockford base32 (no `I`/`L`/`O`/`U`) = 80 bits, printed as `PB-XXXX-…`.
- Stored as SHA-256 of the normalized code. Fast hash rather than bcrypt is correct here: the input
  is high entropy, and an indexable exact lookup is required.
- It is an **enrollment** credential, not a password. It is exchanged once for durable membership,
  so it never lives on the customer's phone, and revoking it does not evict people who already
  joined.
- Redemption is rate limited and every failure mode returns the same flat `404`, so the endpoint
  cannot be used to probe for real farms.

### Node ingest keys

Each shipped node has its own key, checked against the pre-provisioned `devices` row. A key
recovered from a node in one field cannot write another customer's readings and cannot invent new
device ids. The shared `SENSOR_INGEST_API_KEY` remains only so nodes already deployed keep
reporting; it can write only to the legacy farm. Retire it once every node is reflashed.

### Email

Login is by email; `username` is retained for display and @-mentions. Accounts created before
email login have none, so they keep signing in by username and are prompted in-app to add an
address — until they do, they have no way to reset a forgotten password. Password reset and address
verification send short codes via Resend (`RESEND_API_KEY`, `MAIL_FROM`). With no API key
configured, codes are logged instead of sent, so the flows are testable locally.
