# Customer shipping & sensor onboarding

This guide explains how to provision a customer farm, flash field nodes, and ship hardware so the customer sees their devices in the Persephone's Basket app.

For API details and admin setup, see [backend/README.md](./backend/README.md).

---

## How the pieces fit together

```
Staff (you)                          Customer
──────────                           ────────
Provision farm + N nodes      →      Sign up / log in with email
Print 1 access code on card   →      Enter access code (once)
Flash each node with its id           Open app → Sensors tab
         + per-device ingest key              sees their nodes
```

Three separate concepts link together:

| Piece | Purpose |
|-------|---------|
| **Farm** | The customer's vineyard (tenant boundary in the database) |
| **Access code** | Lets a **user account** join that farm (one code per farm, not per device) |
| **Device id + ingest key** | Lets each **physical node** send sensor data into that farm |

The access code and device ingest keys are **independent**:

- The customer gets the **access code** (printed on a card).
- The customer **never** gets ingest keys — those are flashed onto the hardware only.

---

## Example: customer orders 2 devices

### Step 1 — Provision the farm (before shipping)

Use the **Admin tab** in the app (staff-only), or the CLI.

**In the app:** Admin → Provision farm → enter farm name and node count **2**.

**CLI (local, with `DATABASE_URL`):**

```bash
cd communication-platform/backend
npm run provision -- --farm "Smith Vineyard" --nodes 2
```

**CLI (on Railway, where the database lives):**

```bash
railway ssh --project=88eca128-a3e4-4094-9c50-3dcec2779c01 \
  --environment=f1bf40e0-15ea-456e-a8a0-f52546c24666 \
  --service=af43fc9c-0298-40ea-9d72-7adec106f301 \
  'cd /app && npm run provision -- --farm "Smith Vineyard" --nodes 2'
```

Provisioning creates:

| | Node 1 | Node 2 |
|--|--------|--------|
| **Device id** | `{farmId}-A1` (e.g. `farm_abc123-A1`) | `{farmId}-A2` |
| **Display name** | `PB Node A1` | `PB Node A2` |
| **Location label** | `Block 1` | `Block 2` |
| **Ingest key** | unique secret (shown **once**) | unique secret (shown **once**) |

Plus **one access code** for the entire farm, formatted like:

`PB-XXXX-XXXX-XXXX-XXXX`

**Save the provisioning output immediately.** Only hashes are stored in the database. Lost secrets must be **reissued**, not recovered.

---

### Step 2 — How devices are named (don't invent your own)

Provisioning assigns names automatically. You do **not** pick arbitrary device ids.

| Field | Pattern | Example |
|-------|---------|---------|
| Device id | `{farmId}-A{n}` | `farm_abc123-A1` |
| Display name | `PB Node A{n}` | `PB Node A1` |
| Location label | `Block {n}` | `Block 1` |

Device ids are **globally unique** and namespaced by farm id so two customers never collide (e.g. both having `pb-node-A1`).

For **N nodes**, ids run `A1` … `A{N}` (up to 200 per farm).

---

### Step 3 — Flash each node before shipping

Each node must POST readings to `POST /v1/sensors/ingest` with:

**Header:**

```
x-device-key: <that node's ingest key from provisioning>
```

**Body (example for node 1):**

```json
{
  "deviceId": "farm_abc123-A1",
  "deviceName": "PB Node A1",
  "farmName": "Smith Vineyard",
  "locationLabel": "Block 1",
  "status": "online",
  "readings": [
    { "sensorType": "temperature", "value": 22.5, "unit": "C" },
    { "sensorType": "humidity", "value": 61.0, "unit": "%" },
    { "sensorType": "soil_moisture", "value": 38.0, "unit": "%" }
  ]
}
```

Important:

- Use the **exact** `deviceId` and `x-device-key` from provisioning output.
- `farm_id` is set at provisioning time and **cannot** be changed by the device payload.
- Prefer `x-device-key` (per-device). The shared `SENSOR_INGEST_API_KEY` (`x-sensor-key`) is **legacy only** for nodes already in the field before multi-tenancy.

---

### Step 4 — What goes in the box

| Item | Notes |
|------|--------|
| Device 1 | Flashed with `{farmId}-A1` + its ingest key |
| Device 2 | Flashed with `{farmId}-A2` + its ingest key |
| **One** access code card | Same code works for the whole farm |
| Ingest keys | **Never** include these in the box — firmware only |

You do **not** need two access codes for two devices. **One code = one farm = all devices on that farm.**

---

### Step 5 — What the customer does in the app

1. **Sign up or log in** (email + password).
2. If they belong to no farm yet, the app shows the **Connect** / access-code screen.
3. They enter the code from the card: `PB-XXXX-XXXX-XXXX-XXXX`.
4. The app calls `POST /v1/farms/claim`, which adds them to `farm_members`.
5. The main app opens. On the **Sensors** tab (Demo mode), the app loads `GET /v1/sensors/overview`.
6. The API returns **only devices** whose `farm_id` matches farms the user has joined.

The access code is an **enrollment credential**, not a password:

- It is exchanged **once** for permanent membership.
- It is **not** stored on the phone after redemption.
- Revoking a code later does **not** remove users who already joined.

---

### Step 6 — What they see on the vineyard map (Demo mode)

In **Demo**, live sensor nodes map to map blocks by the **A-number** in the device name/id:

| Device | Map block |
|--------|-----------|
| `PB Node A1` / `{farmId}-A1` | Block 1 |
| `PB Node A2` / `{farmId}-A2` | Block 2 |
| `PB Node A3` … `A8` | Blocks 3 … 8 |

Metric cards use:

- **Green** — live field sensor data (temperature, humidity, leaf wetness / soil moisture)
- **Blue** — local weather API for the remaining metrics

Blocks without a reporting node show weather-only data.

---

## Staff admin access

Set `ADMIN_BOOTSTRAP_EMAILS` (comma-separated) in Railway. Listed addresses become staff on next sign-in.

Staff see an **Admin** tab to:

- Provision new customer farms
- View node online/offline status
- Issue or revoke access codes
- Remove farm members
- Rotate a node's ingest key

Admin API routes return **404** to non-staff (invisible, not just locked).

To grant admin manually:

```sql
UPDATE users SET is_admin = TRUE WHERE LOWER(email) = 'you@example.com';
```

---

## After the customer redeems a code

First redeemer joins as **`member`**. To let them manage access codes and crew:

```sql
UPDATE farm_members SET role = 'owner'
WHERE farm_id = '<farmId>' AND user_id = '<userId>';
```

---

## Issuing a replacement access code

If the card is lost (the code cannot be recovered from the database):

```bash
npm run provision -- --farm-id farm_abc123 --add-code --label "replacement card"
```

Or use **Admin → farm detail → Issue code** in the app.

---

## Rotating a node's ingest key

If a device is lost, compromised, or reflashed without the original key:

- **Admin tab** → farm → select node → **Rotate key**
- Or `POST /v1/admin/devices/:deviceId/rotate-key` (staff only)

The new key is shown once. Reflash the node with the new key.

---

## Troubleshooting: customer can't see devices

| Check | Requirement |
|-------|-------------|
| Farm provisioned? | Admin or CLI ran with correct `--nodes` count |
| Access code redeemed? | Customer entered code after sign-in |
| Correct account? | Same email they used to claim the code |
| Node reporting? | Device uses matching `deviceId` + `x-device-key` |
| Recent data? | `last_seen_at` within **7 days** (API filter) |
| Same farm? | Device `farm_id` matches the farm from the access code |

### Common mistakes

| Mistake | Result |
|---------|--------|
| Using old ids like `pb-node-A1` without provisioning | Device belongs to legacy farm, not customer's |
| Using shared `SENSOR_INGEST_API_KEY` for new customers | Legacy path only; won't attach to new farm |
| Two access codes for two devices | Unnecessary — one code covers the whole farm |
| Customer signed in but skipped code entry | Stuck on access-code screen or empty sensors |
| Lost provisioning output | Must reissue code or rotate keys — cannot recover plaintext |

---

## Verify in the database

**Latest reading per device:**

```sql
SELECT DISTINCT ON (d.id, sr.sensor_type)
  d.id, d.name, d.farm_id, sr.sensor_type, sr.value, sr.unit,
  to_timestamp(sr.created_at / 1000.0) AT TIME ZONE 'America/New_York' AS sent_at
FROM sensor_readings sr
JOIN devices d ON d.id = sr.device_id
ORDER BY d.id, sr.sensor_type, sr.created_at DESC;
```

**Who has access to a farm:**

```sql
SELECT u.email, u.username, m.role, m.joined_at
FROM farm_members m
JOIN users u ON u.id = m.user_id
WHERE m.farm_id = '<farmId>';
```

**Active access codes for a farm:**

```sql
SELECT id, label, use_count, max_uses, expires_at, revoked_at
FROM farm_access_codes
WHERE farm_id = '<farmId>'
ORDER BY created_at DESC;
```

---

## Pre-shipment checklist

- [ ] Provision farm with correct name and node count
- [ ] Save access code and all ingest keys (shown once)
- [ ] Print access code on card for the box
- [ ] Flash node 1 with `{farmId}-A1` + ingest key 1
- [ ] Flash node 2 with `{farmId}-A2` + ingest key 2
- [ ] (Repeat for A3…A{N} if more nodes)
- [ ] Verify each node reports (check Admin tab or SQL)
- [ ] Ship hardware + access code card (no ingest keys in the box)
- [ ] Tell customer to sign up, enter code, open Sensors tab

---

## Quick reference

| Question | Answer |
|----------|--------|
| How many access codes per farm? | **One** (covers all nodes) |
| How to name devices? | Auto: `{farmId}-A1`, `PB Node A1`, `Block 1` |
| Which code goes to the customer? | The `PB-XXXX-…` from provisioning |
| When do they see sensor data? | After redeeming code **and** nodes reporting |
| Where is tenancy enforced? | `farm_members` (users) + `devices.farm_id` (nodes) |
