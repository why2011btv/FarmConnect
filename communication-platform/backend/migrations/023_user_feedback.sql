-- In-app product feedback. The user reference is nullable so feedback remains useful
-- after account deletion without retaining the deleted user's identity.
CREATE TABLE IF NOT EXISTS user_feedback (
  id TEXT PRIMARY KEY,
  user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
  category TEXT NOT NULL CHECK (category IN ('Bug', 'Idea', 'Question', 'Other')),
  rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
  message TEXT NOT NULL,
  app_version TEXT,
  build_number TEXT,
  os_version TEXT,
  device_model TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_feedback_created
  ON user_feedback(created_at DESC);
