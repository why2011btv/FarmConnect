-- Rename the device metric formerly stored as "soil_moisture" to "leaf_wetness".
-- The hardware reports leaf wetness; it was mislabeled. The app already displayed this value as
-- "Leaf wetness" in block detail, so this aligns the sensor_type string with reality. New readings
-- are normalized on ingest (see routes/sensors.ts), so this backfills existing rows.
UPDATE sensor_readings SET sensor_type = 'leaf_wetness' WHERE sensor_type = 'soil_moisture';
