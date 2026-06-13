CREATE TABLE IF NOT EXISTS assistant_chat_sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title TEXT NOT NULL DEFAULT 'New chat',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS assistant_chat_messages (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES assistant_chat_sessions(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
  content TEXT NOT NULL DEFAULT '',
  image_urls JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_assistant_chat_sessions_user_updated
  ON assistant_chat_sessions(user_id, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_assistant_chat_messages_session_created
  ON assistant_chat_messages(session_id, created_at ASC);
