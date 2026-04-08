CREATE TABLE IF NOT EXISTS notification_preferences (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  enabled BOOLEAN NOT NULL DEFAULT TRUE,
  radius_miles INT NOT NULL DEFAULT 10,
  categories TEXT[] NOT NULL DEFAULT ARRAY['Disease', 'Pest', 'Weather', 'Note', 'Market'],
  quiet_hours_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  quiet_start TEXT NOT NULL DEFAULT '22:00',
  quiet_end TEXT NOT NULL DEFAULT '07:00',
  timezone_offset_minutes INT NOT NULL DEFAULT 0,
  location_lat DOUBLE PRECISION,
  location_lng DOUBLE PRECISION,
  updated_at BIGINT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_notification_preferences_enabled
  ON notification_preferences(enabled);
