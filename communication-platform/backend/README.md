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

## Notes

- Uses Postgres repositories and SQL migrations.
- Seed data is included in `migrations/002_seed.sql`.
- Session tokens are stored in `auth_sessions` (migration `003_auth_sessions.sql`).
- Notification routes are APNs stubs; integrate a queue worker in production.
- Uploaded images are stored locally in `backend/uploads/` and served under `/uploads/*`.
