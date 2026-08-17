import { FastifyBaseLogger } from "fastify";

/**
 * Transactional email via Resend's HTTP API.
 *
 * Uses plain `fetch` rather than an SDK to avoid another dependency — the API is one POST.
 * When RESEND_API_KEY is unset (local dev), messages are logged instead of sent so the reset and
 * verification flows are fully testable without a verified sending domain.
 */

type SendArgs = {
  to: string;
  subject: string;
  text: string;
  logger: FastifyBaseLogger;
};

function readConfig() {
  return {
    apiKey: process.env.RESEND_API_KEY,
    from: process.env.MAIL_FROM ?? "Persephone's Basket <onboarding@resend.dev>",
    appName: process.env.MAIL_APP_NAME ?? "Persephone's Basket",
  };
}

export function isMailConfigured(): boolean {
  return Boolean(readConfig().apiKey);
}

async function send({ to, subject, text, logger }: SendArgs): Promise<boolean> {
  const { apiKey, from } = readConfig();

  if (!apiKey) {
    // Dev fallback. Logged at warn so it is obvious in production logs that mail is misconfigured,
    // and so the code is recoverable from the console while testing locally.
    logger.warn({ to, subject, text }, "RESEND_API_KEY not set — email not sent, logging instead");
    return false;
  }

  try {
    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ from, to, subject, text }),
    });

    if (!response.ok) {
      const body = await response.text();
      logger.error({ status: response.status, body, to }, "Email send failed");
      return false;
    }
    return true;
  } catch (error) {
    logger.error({ error, to }, "Email send threw");
    return false;
  }
}

export async function sendPasswordResetEmail(
  to: string,
  code: string,
  logger: FastifyBaseLogger
): Promise<boolean> {
  const { appName } = readConfig();
  return send({
    to,
    subject: `${appName} password reset code`,
    text: [
      `Your ${appName} password reset code is:`,
      "",
      `    ${code}`,
      "",
      "It expires in 30 minutes and can only be used once.",
      "If you did not request a password reset, you can ignore this email — your password has not changed.",
    ].join("\n"),
    logger,
  });
}

export async function sendEmailVerificationEmail(
  to: string,
  code: string,
  logger: FastifyBaseLogger
): Promise<boolean> {
  const { appName } = readConfig();
  return send({
    to,
    subject: `Confirm your ${appName} email address`,
    text: [
      `Welcome to ${appName}.`,
      "",
      "Confirm your email address with this code:",
      "",
      `    ${code}`,
      "",
      "It expires in 24 hours.",
    ].join("\n"),
    logger,
  });
}
