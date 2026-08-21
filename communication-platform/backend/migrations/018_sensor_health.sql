-- Sensor health / anomaly monitoring, so the Persephone's Basket team is alarmed when a shipped
-- node reports something that looks like a fault rather than real microclimate.

-- Device coordinates, so a reading can be compared against the weather API at that exact spot.
-- Populated when the customer places the device on their vineyard map.
ALTER TABLE devices ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;

-- One row per (device, anomaly kind) while the condition persists. Kept open until the condition
-- clears, so a single ongoing fault does not re-alarm on every check.
CREATE TABLE IF NOT EXISTS sensor_health_alerts (
  id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  farm_id TEXT,
  kind TEXT NOT NULL,                 -- 'out_of_range' | 'flatline' | 'went_silent' | 'weather_divergence'
  sensor_type TEXT,                   -- 'temperature' | 'humidity' | 'soil_moisture' | null
  severity TEXT NOT NULL CHECK (severity IN ('warning', 'critical')),
  detail TEXT NOT NULL,
  sensor_value DOUBLE PRECISION,
  reference_value DOUBLE PRECISION,   -- e.g. the weather-API value it diverged from
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  notified_at TIMESTAMPTZ,            -- when the ops team was emailed
  resolved_at TIMESTAMPTZ             -- when the condition cleared
);

-- At most one OPEN alert per device+kind+sensor_type. `sensor_type` may be NULL, and NULLs don't
-- collide in a UNIQUE index, so coalesce it to '' for the uniqueness guarantee.
CREATE UNIQUE INDEX IF NOT EXISTS idx_sensor_health_open
  ON sensor_health_alerts (device_id, kind, COALESCE(sensor_type, ''))
  WHERE resolved_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_sensor_health_open_list
  ON sensor_health_alerts (resolved_at, created_at DESC);
