ALTER TABLE users
ADD COLUMN IF NOT EXISTS username TEXT;

WITH base AS (
  SELECT
    id,
    LOWER(
      REGEXP_REPLACE(
        REGEXP_REPLACE(TRIM(name), '[^a-zA-Z0-9_]', '_', 'g'),
        '_+',
        '_',
        'g'
      )
    ) AS normalized_name
  FROM users
),
prepared AS (
  SELECT
    id,
    CASE
      WHEN normalized_name IS NULL OR normalized_name = '' THEN 'user'
      ELSE normalized_name
    END AS base_username
  FROM base
),
ranked AS (
  SELECT
    id,
    base_username,
    ROW_NUMBER() OVER (PARTITION BY base_username ORDER BY id) AS rn
  FROM prepared
)
UPDATE users u
SET username = CASE
  WHEN ranked.rn = 1 THEN ranked.base_username
  ELSE ranked.base_username || '_' || ranked.rn
END
FROM ranked
WHERE u.id = ranked.id
  AND (u.username IS NULL OR u.username = '');

ALTER TABLE users
ALTER COLUMN username SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username_unique
  ON users (username);
