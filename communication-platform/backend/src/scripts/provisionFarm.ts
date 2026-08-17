import "dotenv/config";
import { pool } from "../db.js";
import { MAX_NODES, issueAccessCode, provisionFarm } from "../services/provisioningService.js";

/**
 * Command-line provisioning, for when the admin screen in the app isn't handy.
 *
 * Shares `provisioningService` with the in-app admin API, so both produce identical secrets.
 * Everything printed here is stored only as a hash — if the output is lost, reissue rather than
 * attempt to recover.
 *
 *   npm run provision -- --farm "Smith Vineyard" --nodes 8
 *   npm run provision -- --farm-id farm_ab12cd --add-code --label "second card"
 */

type Args = Record<string, string | boolean>;

function parseArgs(argv: string[]): Args {
  const args: Args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith("--")) continue;
    const key = token.slice(2);
    const next = argv[i + 1];
    if (next && !next.startsWith("--")) {
      args[key] = next;
      i += 1;
    } else {
      args[key] = true;
    }
  }
  return args;
}

function requireString(args: Args, key: string): string {
  const value = args[key];
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`Missing required argument --${key}`);
  }
  return value.trim();
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const label = typeof args.label === "string" ? args.label : null;
  const maxUses = typeof args["max-uses"] === "string" ? Number(args["max-uses"]) : null;

  if (args["add-code"] === true) {
    const farmId = requireString(args, "farm-id");
    const code = await issueAccessCode(pool, farmId, { label, maxUses });
    console.log(`\nNew access code for ${farmId}:  ${code}\n`);
    return;
  }

  const farmName = requireString(args, "farm");
  const nodeCount = Number(args.nodes ?? 8);
  if (!Number.isInteger(nodeCount) || nodeCount < 1 || nodeCount > MAX_NODES) {
    throw new Error(`--nodes must be an integer between 1 and ${MAX_NODES}`);
  }

  const result = await provisionFarm(pool, { name: farmName, nodeCount, label, maxUses });

  console.log(`
Provisioned "${result.farmName}"

  Farm id:      ${result.farmId}
  Access code:  ${result.accessCode}      <- print this on the card in the box

Per-node ingest keys (flash each node with its own; they are not recoverable later):
`);
  for (const node of result.nodes) {
    console.log(`  ${node.name.padEnd(12)} deviceId=${node.id}`);
    console.log(`  ${" ".repeat(12)} x-device-key=${node.ingestKey}\n`);
  }

  console.log(
    "The first user to redeem the access code joins as a member. Promote them to owner with:\n" +
      `  UPDATE farm_members SET role = 'owner' WHERE farm_id = '${result.farmId}' AND user_id = '<user id>';\n`
  );
}

main()
  .then(async () => {
    await pool.end();
  })
  .catch(async (error) => {
    console.error("Provisioning failed:", error instanceof Error ? error.message : error);
    await pool.end();
    process.exit(1);
  });
