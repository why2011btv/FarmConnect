-- One shared vineyard map per farm. The JSON document contains the map profile, device-backed
-- block rectangles, and per-block settings used by the iOS app.
CREATE TABLE IF NOT EXISTS vineyard_layouts (
  farm_id TEXT PRIMARY KEY REFERENCES farms(id) ON DELETE CASCADE,
  layout JSONB NOT NULL,
  updated_by TEXT REFERENCES users(id) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
