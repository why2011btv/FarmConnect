import { Pool, PoolClient } from "pg";

export type FarmRole = "owner" | "member";

/** Farm ids the user belongs to. Empty means they have not redeemed an access code yet. */
export async function getUserFarmIds(db: Pool, userId: string): Promise<string[]> {
  const { rows } = await db.query<{ farm_id: string }>(
    "SELECT farm_id FROM farm_members WHERE user_id = $1",
    [userId]
  );
  return rows.map((r) => r.farm_id);
}

/** The user's role in a farm, or null if they are not a member. */
export async function getFarmRole(
  db: Pool | PoolClient,
  userId: string,
  farmId: string
): Promise<FarmRole | null> {
  const { rows } = await db.query<{ role: FarmRole }>(
    "SELECT role FROM farm_members WHERE user_id = $1 AND farm_id = $2 LIMIT 1",
    [userId, farmId]
  );
  return rows[0]?.role ?? null;
}

/**
 * Resolves a farm the caller owns, or null.
 *
 * Non-membership and non-ownership are deliberately indistinguishable to the caller, so probing
 * farm ids cannot be used to learn which ones exist.
 */
export async function requireFarmOwner(
  db: Pool,
  userId: string,
  farmId: string
): Promise<boolean> {
  return (await getFarmRole(db, userId, farmId)) === "owner";
}
