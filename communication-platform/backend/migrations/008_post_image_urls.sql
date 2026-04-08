ALTER TABLE posts
ADD COLUMN IF NOT EXISTS image_urls TEXT[] NOT NULL DEFAULT '{}';

UPDATE posts
SET image_urls = ARRAY[image_url]
WHERE image_url IS NOT NULL
  AND image_url <> ''
  AND (image_urls IS NULL OR cardinality(image_urls) = 0);
