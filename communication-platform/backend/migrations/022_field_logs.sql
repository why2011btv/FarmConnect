-- Shared spray and scouting records. These belong to a farm, not one phone.
CREATE TABLE IF NOT EXISTS field_logs (
  id TEXT PRIMARY KEY,
  farm_id TEXT NOT NULL REFERENCES farms(id) ON DELETE CASCADE,
  user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
  kind TEXT NOT NULL CHECK (kind IN ('Spray', 'Scouting', 'General')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  block_id TEXT,
  block_name TEXT,
  location_detail TEXT NOT NULL,
  grape_variety TEXT NOT NULL DEFAULT '',
  title TEXT NOT NULL,
  notes TEXT NOT NULL DEFAULT '',
  product TEXT,
  application_rate TEXT,
  issue_type TEXT,
  severity INTEGER CHECK (severity IS NULL OR severity BETWEEN 1 AND 5)
);

CREATE INDEX IF NOT EXISTS idx_field_logs_farm_created ON field_logs(farm_id, created_at DESC);
