-- Harvest decision support: growers log fruit chemistry over time (Brix, titratable acidity, pH).
-- Harvest is a fruit-composition + tasting + rot decision, not a sensor decision — this gives a
-- place to record and trend the numbers that actually drive the pick.
CREATE TABLE IF NOT EXISTS fruit_samples (
  id TEXT PRIMARY KEY,
  farm_id TEXT NOT NULL REFERENCES farms(id) ON DELETE CASCADE,
  user_id TEXT REFERENCES users(id),
  block_label TEXT,
  sampled_on DATE NOT NULL,
  brix DOUBLE PRECISION,               -- soluble solids (°Bx)
  titratable_acidity DOUBLE PRECISION, -- g/L as tartaric
  ph DOUBLE PRECISION,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_fruit_samples_farm ON fruit_samples(farm_id, sampled_on);
