import { Pool, PoolClient } from "pg";
import {
  generateAccessCode,
  generateSecretToken,
  hashSecret,
  normalizeAccessCode,
} from "../lib/accessCode.js";
import { createId } from "../lib/id.js";

/**
 * Creating a customer: one farm, N pre-registered nodes each with its own ingest key, and one
 * access code for the card in the box.
 *
 * Shared by the `provision` CLI and the in-app admin API so both mint identical, correctly-hashed
 * secrets. Plaintext is returned to the caller once and never stored.
 */

export type ProvisionedNode = {
  id: string;
  name: string;
  locationLabel: string;
  ingestKey: string;
};

export type ProvisionedFarm = {
  farmId: string;
  farmName: string;
  accessCode: string;
  nodes: ProvisionedNode[];
};

export const MAX_NODES = 200;

export async function provisionFarm(
  db: Pool,
  options: { name: string; nodeCount: number; label?: string | null; maxUses?: number | null }
): Promise<ProvisionedFarm> {
  const farmName = options.name.trim();
  const nodeCount = options.nodeCount;

  // Node ids are namespaced by farm id. A bare "pb-node-A1" would collide with the next
  // customer's first node, and device ids are globally unique.
  const farmId = createId("farm");
  const accessCode = generateAccessCode();

  const nodes: ProvisionedNode[] = [];
  for (let i = 1; i <= nodeCount; i += 1) {
    nodes.push({
      id: `${farmId}-A${i}`,
      name: `PB Node A${i}`,
      locationLabel: `Block ${i}`,
      ingestKey: generateSecretToken(),
    });
  }

  const client = await db.connect();
  try {
    await client.query("BEGIN");
    await client.query("INSERT INTO farms(id, name) VALUES ($1, $2)", [farmId, farmName]);
    await insertAccessCode(client, farmId, accessCode, options.label ?? "shipped with hardware", options.maxUses ?? null);

    for (const node of nodes) {
      await client.query(
        `INSERT INTO devices(id, name, farm_name, location_label, status, last_seen_at, farm_id, ingest_key_hash)
         VALUES ($1, $2, $3, $4, 'offline', 0, $5, $6)`,
        [node.id, node.name, farmName, node.locationLabel, farmId, hashSecret(node.ingestKey)]
      );
    }
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }

  return { farmId, farmName, accessCode, nodes };
}

/** Mints an additional access code for an existing farm. Returns the plaintext once. */
export async function issueAccessCode(
  db: Pool,
  farmId: string,
  options: { label?: string | null; maxUses?: number | null; expiresInDays?: number | null } = {}
): Promise<string> {
  const code = generateAccessCode();
  await insertAccessCode(
    db,
    farmId,
    code,
    options.label ?? null,
    options.maxUses ?? null,
    options.expiresInDays ?? null
  );
  return code;
}

/** Replaces a node's ingest key, e.g. after a device is lost or resold. Returns the new key once. */
export async function rotateDeviceKey(db: Pool, deviceId: string): Promise<string | null> {
  const key = generateSecretToken();
  const { rowCount } = await db.query(
    "UPDATE devices SET ingest_key_hash = $2 WHERE id = $1",
    [deviceId, hashSecret(key)]
  );
  return rowCount ? key : null;
}

async function insertAccessCode(
  db: Pool | PoolClient,
  farmId: string,
  code: string,
  label: string | null,
  maxUses: number | null,
  expiresInDays: number | null = null
) {
  const expiresAt = expiresInDays
    ? new Date(Date.now() + expiresInDays * 24 * 60 * 60 * 1000)
    : null;
  await db.query(
    `INSERT INTO farm_access_codes(id, farm_id, code_hash, label, max_uses, expires_at)
     VALUES ($1, $2, $3, $4, $5, $6)`,
    [createId("fac"), farmId, hashSecret(normalizeAccessCode(code)!), label, maxUses, expiresAt]
  );
}
