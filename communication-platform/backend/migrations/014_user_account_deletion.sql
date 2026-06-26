-- Account deletion (Apple Guideline 5.1.1(v)): we anonymize-in-place rather than hard-delete,
-- because posts/comments/messages reference users(id) without ON DELETE CASCADE. A deleted account
-- has its PII scrubbed and login permanently disabled; its content stays attributed to a
-- "[deleted user]" placeholder so other users' threads/feeds don't break.
ALTER TABLE users
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
