# Communication Platform (Native-First)

This directory contains the FarmConnect / Persephone's Basket platform:

- `backend/` — TypeScript API (Fastify + Postgres on Railway)
- `ios-app/` — SwiftUI app (TestFlight / App Store)

## Guides

- **[SHIPPING.md](./SHIPPING.md)** — Provision a customer farm, flash nodes, ship hardware, and onboard customers with access codes
- **[backend/README.md](./backend/README.md)** — API reference, local dev, admin setup, Railway

## Railway SSH (production database)

```bash
railway ssh --project=88eca128-a3e4-4094-9c50-3dcec2779c01 --environment=f1bf40e0-15ea-456e-a8a0-f52546c24666 --service=af43fc9c-0298-40ea-9d72-7adec106f301
```
