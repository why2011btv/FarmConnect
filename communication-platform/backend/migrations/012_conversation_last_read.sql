-- Track the last time each participant opened a conversation so we can
-- compute unread counts on the server instead of shipping every message
-- to the client just to count unread ones.
ALTER TABLE conversation_participants
  ADD COLUMN IF NOT EXISTS last_read_at BIGINT NOT NULL DEFAULT 0;

-- Seed existing rows so users aren't drowned in fake "unread" counts
-- the moment they upgrade. After this, new messages naturally become
-- unread because they have created_at > last_read_at.
UPDATE conversation_participants
SET last_read_at = EXTRACT(EPOCH FROM NOW())::BIGINT * 1000
WHERE last_read_at = 0;

-- Useful when computing per-user unread counts by conversation.
CREATE INDEX IF NOT EXISTS idx_messages_conversation_created
  ON messages(conversation_id, created_at);
