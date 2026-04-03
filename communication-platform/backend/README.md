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

## Notes

- Uses Postgres repositories and SQL migrations.
- Seed data is included in `migrations/002_seed.sql`.
- Session tokens are stored in `auth_sessions` (migration `003_auth_sessions.sql`).
- APNs delivery is wired via token-based auth key env vars (see `.env.example`).
- Uploaded images are stored locally in `backend/uploads/` and served under `/uploads/*`.

## APNs setup (for TestFlight)

Set these in `.env`:

- `APNS_KEY_ID`
- `APNS_TEAM_ID`
- `APNS_BUNDLE_ID`
- `APNS_PRIVATE_KEY` (single-line with `\n` escapes)
- `APNS_USE_PRODUCTION=true` for TestFlight/App Store builds
