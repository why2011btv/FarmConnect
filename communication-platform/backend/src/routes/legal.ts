import { FastifyInstance } from "fastify";

/**
 * Public legal pages. Served as self-contained HTML (no external assets) so the
 * URL works as an App Store "Privacy Policy URL". Update the effective date and
 * contact address here when the policy changes.
 */

const EFFECTIVE_DATE = "August 18, 2026";
const CONTACT_EMAIL = "support@persephonesbasket.com";

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
  .wrap { max-width:720px; margin:0 auto; padding:40px 22px 80px; }
  h1 { font-size:1.9rem; line-height:1.2; margin:0 0 6px; }
  h2 { font-size:1.15rem; margin:34px 0 8px; }
  .eff { color:var(--muted); font-size:.92rem; margin-bottom:8px; }
  .lead { color:var(--fg); }
  p, li { color:var(--fg); }
  .muted { color:var(--muted); font-size:.9rem; }
  a { color:var(--accent); }
  hr { border:none; border-top:1px solid var(--line); margin:28px 0; }
  ul { padding-left:1.2em; }
  li { margin:6px 0; }
  .card { border:1px solid var(--line); border-radius:12px; padding:14px 16px; margin-top:14px; }
  code { background:rgba(127,127,127,.15); padding:1px 5px; border-radius:5px; font-size:.9em; }
</style>
</head>
<body>
<main class="wrap">
  <h1>Privacy Policy</h1>
  <div class="eff">Persephone's Basket (FarmConnect) &middot; Effective ${EFFECTIVE_DATE}</div>
  <p class="lead">Persephone's Basket builds vineyard microclimate sensors and the FarmConnect app.
  This policy explains what the app and our service collect, why, and the choices you have. We keep
  data collection to what the product needs to work; we do not sell your data or use it for advertising.</p>

  <h2>Who this covers</h2>
  <p>This policy applies to the FarmConnect iOS app and the backend service it talks to. If you
  received sensor hardware from us, it also covers the readings those sensors send to your farm's account.</p>

  <h2>What we collect</h2>
  <ul>
    <li><strong>Account information.</strong> Your email address and a password (stored only as a salted
      hash — we never store your password in readable form), and a display name if you provide one.
      Used to sign you in and associate you with your farm.</li>
    <li><strong>Farm and sensor data.</strong> The farm you belong to, the sensor devices assigned to it,
      and the readings those devices report (temperature, humidity, and related environmental
      measurements), including a device's location if you place it on your vineyard map.</li>
    <li><strong>Approximate location (optional).</strong> If you choose to set your vineyard's position or
      use "current location," we use your device's location once to place your farm for local weather.
      We do not track your location in the background.</li>
    <li><strong>Photos you choose to share (optional).</strong> If you attach a photo to a message to the
      in-app assistant, that image is uploaded to answer your request. We do not access your photo
      library otherwise.</li>
    <li><strong>Support and diagnostic information.</strong> Basic logs needed to operate the service
      (for example, error records and sensor-health checks).</li>
  </ul>
  <p>We do <strong>not</strong> collect contacts, browsing history, or advertising identifiers, and the app
  contains no third-party advertising or analytics SDKs.</p>

  <h2>How we use your information</h2>
  <ul>
    <li>To provide the app: authenticate you, show your farm's sensor data, and compute weather and
      disease-risk estimates.</li>
    <li>To operate and protect the service: detect malfunctioning sensors, prevent abuse, and fix problems.</li>
    <li>To communicate with you: send password-reset codes and important service notices to your email.</li>
  </ul>
  <p>We do not sell personal data or share it for cross-context behavioral advertising.</p>

  <h2>Service providers we use</h2>
  <p>We rely on a small set of processors to run the service. They handle data only to provide their
  function to us:</p>
  <ul>
    <li><strong>Railway</strong> — application and database hosting.</li>
    <li><strong>Open-Meteo</strong> — weather data. We send approximate coordinates to retrieve local
      forecast and historical weather; we do not send your identity.</li>
    <li><strong>OpenRouter / OpenAI</strong> — powers the in-app assistant. Messages (and any photo you
      attach) you send to the assistant are processed to generate a reply.</li>
    <li><strong>Apple Push Notification service</strong> — to deliver notifications you enable.</li>
    <li><strong>Email delivery provider</strong> — to send password-reset and service emails.</li>
    <li><strong>Object storage (Cloudflare R2)</strong> — to store images you upload.</li>
  </ul>

  <h2>Disease-risk and agronomic information</h2>
  <div class="card">The app's weather and disease-risk estimates are <strong>decision support, not a spray
  recommendation</strong>. They are estimates from published models and may be wrong. The product label
  is the legal authority on any pesticide use, and you should confirm with Cornell NEWA and a licensed
  advisor before acting. We are not responsible for crop decisions made from this information.</div>

  <h2>Data retention</h2>
  <p>We keep account and farm data for as long as your account is active. Sensor readings are retained to
  provide season-over-season history. When you delete your account, we delete or de-identify your personal
  data within 30 days, except where we must retain records to comply with law.</p>

  <h2>Your choices and rights</h2>
  <ul>
    <li><strong>Access and correction:</strong> contact us to access or correct your information.</li>
    <li><strong>Deletion:</strong> you can request deletion of your account and personal data at the email
      below. Depending on your region (e.g., EU/UK GDPR, California CCPA/CPRA), you may have additional
      rights to access, port, or delete your data and to object to certain processing; we honor these
      requests.</li>
    <li><strong>Location and notifications:</strong> you control these in iOS Settings at any time.</li>
  </ul>

  <h2>Children</h2>
  <p>FarmConnect is a tool for commercial and hobby grape growers and is not directed to children under 13.
  We do not knowingly collect data from children.</p>

  <h2>Changes</h2>
  <p>We may update this policy. Material changes will be reflected by a new effective date, and significant
  changes will be communicated in the app or by email.</p>

  <h2>Contact</h2>
  <p>Persephone's Basket<br>
  Email: <a href="mailto:${CONTACT_EMAIL}">${CONTACT_EMAIL}</a></p>

  <hr>
  <p class="muted">© Persephone's Basket. This page is served by the FarmConnect backend.</p>
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
