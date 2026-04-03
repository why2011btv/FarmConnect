CREATE TABLE IF NOT EXISTS devices (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  farm_name TEXT NOT NULL,
  location_label TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('online', 'offline')),
  last_seen_at BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS sensor_readings (
  id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  sensor_type TEXT NOT NULL,
  value DOUBLE PRECISION NOT NULL,
  unit TEXT NOT NULL,
  created_at BIGINT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_sensor_readings_device_time ON sensor_readings(device_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sensor_readings_type ON sensor_readings(sensor_type);

INSERT INTO devices(id, name, farm_name, location_label, status, last_seen_at) VALUES
  ('d1', 'Field Node A', 'Persephone Farm', 'North Block', 'online', (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT - 120000),
  ('d2', 'Greenhouse Node', 'Persephone Farm', 'Greenhouse 2', 'offline', (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT - 5400000)
ON CONFLICT (id) DO NOTHING;

INSERT INTO sensor_readings(id, device_id, sensor_type, value, unit, created_at) VALUES
  ('r1', 'd1', 'temperature', 26.4, 'C', (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT - 120000),
  ('r2', 'd1', 'humidity', 63.2, '%', (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT - 120000),
  ('r3', 'd1', 'soil_moisture', 41.8, '%', (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT - 120000),
  ('r4', 'd2', 'temperature', 31.1, 'C', (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT - 5400000),
  ('r5', 'd2', 'humidity', 47.3, '%', (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT - 5400000),
  ('r6', 'd2', 'soil_moisture', 22.5, '%', (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT - 5400000)
ON CONFLICT (id) DO NOTHING;
