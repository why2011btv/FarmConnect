-- Multi-tenancy for shipped hardware.
--
-- Until now every signed-in user could read every device in the database, which was harmless
-- while all devices were ours. Once nodes ship to customers, a farm is the unit of ownership:
-- devices belong to exactly one farm, users join a farm by redeeming an access code, and sensor
-- reads are scoped through farm_members.

CREATE TABLE IF NOT EXISTS farms (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS farm_members (
  farm_id TEXT NOT NULL REFERENCES farms(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'member')),
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (farm_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_farm_members_user ON farm_members(user_id);

-- Access codes are high-entropy random strings (80 bits), so we store a plain SHA-256 of the
-- normalized code rather than bcrypt: bcrypt's work factor exists to protect low-entropy human
-- passwords, and it would force a full table scan since you cannot look up a row by bcrypt hash.
-- The plaintext is shown exactly once, at generation time, and never persisted.
CREATE TABLE IF NOT EXISTS farm_access_codes (
  id TEXT PRIMARY KEY,
  farm_id TEXT NOT NULL REFERENCES farms(id) ON DELETE CASCADE,
  code_hash TEXT NOT NULL UNIQUE,
  label TEXT,
  max_uses INT,
  use_count INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_farm_access_codes_farm ON farm_access_codes(farm_id);

ALTER TABLE devices ADD COLUMN IF NOT EXISTS farm_id TEXT REFERENCES farms(id) ON DELETE CASCADE;

-- Per-device ingest secret (SHA-256). Replaces the single global SENSOR_INGEST_API_KEY so that a
-- key recovered from one node in a field cannot be used to write readings for another customer.
ALTER TABLE devices ADD COLUMN IF NOT EXISTS ingest_key_hash TEXT;

CREATE INDEX IF NOT EXISTS idx_devices_farm ON devices(farm_id);

ALTER TABLE users ADD COLUMN IF NOT EXISTS email TEXT;

-- Email is the login identifier going forward; username is kept for display/@-mentions.
-- Nullable so pre-existing accounts keep working until they add one; partial index so a deleted
-- account's scrubbed row never blocks re-registration of that address.
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email_unique
  ON users (LOWER(email))
  WHERE email IS NOT NULL AND deleted_at IS NULL;

-- Backfill: everything that exists right now is our own deployment. Put it in one legacy farm and
-- make every existing user a member, so the current app keeps working across this migration.
INSERT INTO farms(id, name) VALUES ('farm_legacy', 'Persephone Farm')
ON CONFLICT (id) DO NOTHING;

UPDATE devices SET farm_id = 'farm_legacy' WHERE farm_id IS NULL;

-- Joined as 'member', not 'owner'. These accounts include TestFlight testers, and they could
-- already see every device before this migration, so membership is not a new grant — but owner
-- would be: it allows minting access codes and removing other people. Promote your own account
-- by hand afterwards:
--   UPDATE farm_members SET role='owner' WHERE farm_id='farm_legacy' AND user_id='<your id>';
INSERT INTO farm_members(farm_id, user_id, role)
SELECT 'farm_legacy', id, 'member' FROM users WHERE deleted_at IS NULL
ON CONFLICT (farm_id, user_id) DO NOTHING;

ALTER TABLE devices ALTER COLUMN farm_id SET NOT NULL;

-- Safety net for the rollout window. The schema is migrated before the new code ships, and the
-- currently-running ingest handler inserts devices without a farm_id — without a default, a node
-- reporting for the first time in that gap would fail to register. New code always sets farm_id
-- explicitly, so this only ever catches the old path.
ALTER TABLE devices ALTER COLUMN farm_id SET DEFAULT 'farm_legacy';
