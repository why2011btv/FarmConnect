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

- `GET /v1/posts`
- `POST /v1/posts`
- `POST /v1/posts/:postId/upvote`
- `POST /v1/posts/:postId/comments`
- `GET /v1/conversations?userId=<id>`
- `GET /v1/messages?userA=<id>&userB=<id>`
- `POST /v1/messages`
- `POST /v1/uploads/create`
- `POST /v1/notifications/register-device`
- `POST /v1/notifications/send`

## Notes

- Uses Postgres repositories and SQL migrations.
- Seed data is included in `migrations/002_seed.sql`.
- Notification routes are APNs stubs; integrate a queue worker in production.
