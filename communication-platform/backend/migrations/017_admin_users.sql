-- Staff flag, so customer farms can be provisioned from inside the app instead of over SSH.
--
-- Bootstrapping is done with the ADMIN_BOOTSTRAP_EMAILS env var rather than a seeded row: the
-- first admin can then be granted from the Railway dashboard with no database access at all, and
-- the list is auditable in one place.

ALTER TABLE users ADD COLUMN IF NOT EXISTS is_admin BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_users_is_admin ON users(is_admin) WHERE is_admin;
