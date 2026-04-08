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

- `POST /v1/auth/login`
- `GET /v1/auth/me`
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
- Sensor ingest endpoint uses `SENSOR_INGEST_API_KEY` header auth (`x-sensor-key`).

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
