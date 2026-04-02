import apn from "apn";

type ApnsConfig = {
  keyId: string;
  teamId: string;
  bundleId: string;
  privateKey: string;
  production: boolean;
};

let provider: apn.Provider | null = null;
let config: ApnsConfig | null = null;

function readConfig(): ApnsConfig | null {
  const keyId = process.env.APNS_KEY_ID?.trim();
  const teamId = process.env.APNS_TEAM_ID?.trim();
  const bundleId = process.env.APNS_BUNDLE_ID?.trim();
  const privateKeyRaw = process.env.APNS_PRIVATE_KEY?.trim();
  const production = process.env.APNS_USE_PRODUCTION === "true";

  if (!keyId || !teamId || !bundleId || !privateKeyRaw) return null;
  return {
    keyId,
    teamId,
    bundleId,
    privateKey: privateKeyRaw.replace(/\\n/g, "\n"),
    production,
  };
}

function getProvider() {
  if (provider) return provider;
  config = readConfig();
  if (!config) return null;

  provider = new apn.Provider({
    token: {
      key: config.privateKey,
      keyId: config.keyId,
      teamId: config.teamId,
    },
    production: config.production,
  });
  return provider;
}

export async function sendApnsPush(
  deviceTokens: string[],
  title: string,
  body: string,
  payload: Record<string, unknown> = {}
) {
  const p = getProvider();
  if (!p || !config) {
    return { sent: 0, failed: deviceTokens.length, skipped: true };
  }

  const note = new apn.Notification();
  note.topic = config.bundleId;
  note.alert = { title, body };
  note.sound = "default";
  note.payload = payload;

  const result = await p.send(note, deviceTokens);
  return {
    sent: result.sent.length,
    failed: result.failed.length,
    skipped: false,
    failedDetails: result.failed.map((f) =>
      typeof f === "string" ? { device: f, reason: "unknown" } : { device: f.device, reason: String(f.response?.reason ?? f.error?.message ?? "unknown") }
    ),
  };
}
