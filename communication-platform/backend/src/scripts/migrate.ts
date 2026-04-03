import "dotenv/config";
import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { pool, withTransaction } from "../db.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const migrationsDir = path.resolve(__dirname, "../../migrations");

async function run() {
  const files = (await readdir(migrationsDir))
    .filter((name) => name.endsWith(".sql"))
    .sort();

  await withTransaction(async (client) => {
    await client.query(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version TEXT PRIMARY KEY,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
    `);

    for (const file of files) {
      const { rows } = await client.query<{ version: string }>(
        "SELECT version FROM schema_migrations WHERE version = $1",
        [file]
      );
      if (rows.length > 0) continue;

      const sql = await readFile(path.join(migrationsDir, file), "utf8");
      await client.query(sql);
      await client.query("INSERT INTO schema_migrations(version) VALUES($1)", [file]);
      console.log(`Applied migration: ${file}`);
    }
  });
}

run()
  .then(async () => {
    await pool.end();
    console.log("Migrations complete");
  })
  .catch(async (error) => {
    console.error("Migration failed", error);
    await pool.end();
    process.exit(1);
  });
