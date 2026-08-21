import { FastifyInstance } from "fastify";

/**
 * Public legal pages. Served as self-contained HTML (no external assets) so the
 * URL works as an App Store "Privacy Policy URL". Update the effective date and
 * contact address here when the policy changes.
 */

const EFFECTIVE_DATE = "August 18, 2026";
const CONTACT_EMAIL = "alex@persephonesbasket.com";

const PRIVACY_HTML = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Privacy Policy — Persephone's Basket</title>
<style>
  :root { color-scheme: light dark; --bg:#ffffff; --fg:#1c1c1e; --muted:#6b6b70; --line:#e5e5ea; --accent:#2e7d32; }
  @media (prefers-color-scheme: dark) { :root { --bg:#1c1c1e; --fg:#f2f2f7; --muted:#9a9aa0; --line:#38383c; --accent:#66bb6a; } }
  * { box-sizing: border-box; }
  body { margin:0; background:var(--bg); color:var(--fg);
    font:16px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif; }
  .wrap { max-width:680px; margin:0 auto; padding:40px 22px 72px; }
  h1 { font-size:1.9rem; line-height:1.2; margin:0 0 6px; }
  h2 { font-size:1.12rem; margin:30px 0 8px; }
  .eff { color:var(--muted); font-size:.92rem; margin-bottom:14px; }
  p, li { color:var(--fg); }
  .muted { color:var(--muted); font-size:.9rem; }
  a { color:var(--accent); }
  hr { border:none; border-top:1px solid var(--line); margin:26px 0; }
  ul { padding-left:1.2em; }
  li { margin:6px 0; }
</style>
</head>
<body>
<main class="wrap">
  <h1>Privacy Policy</h1>
  <div class="eff">Persephone's Basket (FarmConnect) &middot; Effective ${EFFECTIVE_DATE}</div>
  <p>We build vineyard sensors and the FarmConnect app. This policy explains what we collect and why.
  We collect only what the app needs to work, and we do not sell your data or use it for advertising.</p>

  <h2>What we collect</h2>
  <ul>
    <li><strong>Account:</strong> your email and password (stored only as a salted hash — never in
      readable form), and an optional display name.</li>
    <li><strong>Farm &amp; sensor data:</strong> your farm, its devices, and the readings they report
      (temperature, humidity, and related measurements), plus a device's location if you place it on
      your map.</li>
    <li><strong>Location (optional):</strong> if you choose, we use your device location once to set your
      vineyard's position for local weather. We do not track location in the background.</li>
    <li><strong>Photos (optional):</strong> a photo you attach to the in-app assistant is uploaded to
      answer your request. We do not otherwise access your photo library.</li>
    <li><strong>Basic logs</strong> needed to run and secure the service.</li>
  </ul>
  <p>We do not collect contacts, browsing history, or advertising identifiers, and the app has no
  third-party advertising or analytics.</p>

  <h2>How we use it</h2>
  <p>To run the app (sign-in, showing your data, and weather/disease estimates), to keep the service
  working and secure, and to email you password resets and important notices.</p>

  <h2>Sharing</h2>
  <p>We do not sell your data or share it for advertising. We use a limited number of service providers
  (such as cloud hosting, weather data, email delivery, and the in-app assistant) that process data only
  as needed to provide their service to us.</p>

  <h2>Retention &amp; your rights</h2>
  <p>We keep your data while your account is active and delete or de-identify it within 30 days of
  account deletion, except where law requires otherwise. You can access, correct, or delete your data by
  emailing us; depending on your region you may have additional rights (e.g., GDPR, CCPA), which we honor.
  You control location and notification permissions in iOS Settings.</p>

  <h2>Children</h2>
  <p>FarmConnect is for grape growers and is not directed to children under 13; we do not knowingly
  collect their data.</p>

  <h2>Changes &amp; contact</h2>
  <p>We may update this policy; material changes will carry a new effective date.
  Contact: <a href="mailto:${CONTACT_EMAIL}">${CONTACT_EMAIL}</a></p>

  <hr>
  <p class="muted">© Persephone's Basket.</p>
</main>
</body>
</html>`;

export async function legalRoutes(app: FastifyInstance): Promise<void> {
  app.get("/privacy", async (_req, reply) => {
    reply
      .type("text/html; charset=utf-8")
      .header("cache-control", "public, max-age=3600")
      .send(PRIVACY_HTML);
  });
  // Convenience alias.
  app.get("/privacy-policy", async (_req, reply) => reply.redirect("/privacy"));
}
