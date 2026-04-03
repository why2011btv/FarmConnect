ALTER TABLE conversations
  ADD COLUMN IF NOT EXISTS conversation_type TEXT NOT NULL DEFAULT 'direct',
  ADD COLUMN IF NOT EXISTS group_name TEXT;

ALTER TABLE messages
  ALTER COLUMN to_user_id DROP NOT NULL;

UPDATE conversations
SET conversation_type = 'group'
WHERE group_name IS NOT NULL;
