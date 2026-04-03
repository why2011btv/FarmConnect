INSERT INTO users (id, name) VALUES
  ('u1', 'Alex Wang'),
  ('u2', 'Paris F'),
  ('u3', 'Charles Zhang')
ON CONFLICT (id) DO NOTHING;

INSERT INTO posts (
  id, title, body, crop, category, severity, visibility, lat, lng, city, created_at, upvotes, user_id, image_url
) VALUES
  ('p1', 'Possible corn rust spotted', 'Leaves show orange pustules. If you grow corn nearby, please scout your field.', 'Corn', 'Disease', 3, 'Public', 44.2601, -72.5754, 'Montpelier', (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT - 5100000, 18, 'u2', NULL),
  ('p2', 'Fall armyworm pressure increasing', 'Larvae found in whorls. Check early morning; track severity over the week.', 'Corn', 'Pest', 4, 'Public', 25.7617, -80.1918, 'Miami', (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT - 10800000, 27, 'u1', NULL),
  ('p3', 'Private note: irrigation check', 'North block looks dry. Inspect drip lines tomorrow.', 'Mixed', 'Note', 1, 'Private', 25.7800, -80.2100, 'Miami', (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT - 1800000, 0, 'u1', NULL),
  ('p4', 'Corn pest infestation detected', 'Found significant pest damage in the eastern field. Immediate treatment recommended.', 'Corn', 'Pest', 5, 'Public', 42.3601, -71.0589, 'Boston', (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT - 7200000, 15, 'u3', NULL),
  ('p5', 'Fresh blueberries at local market', 'Selling freshly picked organic blueberries at the Saturday farmers market.', 'Blueberries', 'Market', 1, 'Public', 42.3601, -71.0589, 'Boston', (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT - 2700000, 7, 'u1', NULL)
ON CONFLICT (id) DO NOTHING;
