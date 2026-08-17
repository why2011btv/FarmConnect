import { createHash, randomBytes, randomInt } from "node:crypto";

/**
 * Crockford base32: the standard alphabet minus I, L, O and U. Customers read these codes off a
 * printed card and type them on a phone, so the alphabet must not contain characters that are
 * ambiguous in print (1/I/l, 0/O) or that can form unfortunate words (U).
 */
const ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

const CODE_LENGTH = 16; // 16 * log2(32) = 80 bits
const DISPLAY_PREFIX = "PB";
const GROUP_SIZE = 4;

/** Characters a human might type in place of an alphabet character. */
const LOOKALIKES: Record<string, string> = { I: "1", L: "1", O: "0", U: "V" };

/**
 * Generates a fresh access code in display form, e.g. `PB-4K7M-9XQR-2W8T-H3NF`.
 *
 * Uses `randomInt`, which rejection-samples internally, rather than `randomBytes(n) % 32` —
 * 256 is not a multiple of 32 here only by luck, and the modulo habit silently biases other
 * alphabet sizes.
 */
export function generateAccessCode(): string {
  let body = "";
  do {
    body = "";
    for (let i = 0; i < CODE_LENGTH; i += 1) {
      body += ALPHABET[randomInt(ALPHABET.length)];
    }
    // Never mint a body that itself starts with the display prefix. Otherwise "PBPB…" and "PB…"
    // are ambiguous to any client that strips the prefix while the user is still typing, and the
    // customer would be left with a code that simply never works. Costs ~0.1% of an 80-bit space.
  } while (body.startsWith(DISPLAY_PREFIX));

  const groups: string[] = [];
  for (let i = 0; i < body.length; i += GROUP_SIZE) {
    groups.push(body.slice(i, i + GROUP_SIZE));
  }
  return `${DISPLAY_PREFIX}-${groups.join("-")}`;
}

/**
 * Reduces any form a user might type — with or without the `PB-` prefix, dashes, spaces, lowercase,
 * or look-alike characters — to the canonical 16-character body. Returns null if the result is not
 * a well-formed code, so callers can reject without touching the database.
 */
export function normalizeAccessCode(raw: string): string | null {
  let value = raw
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "")
    .replace(/[ILOU]/g, (char) => LOOKALIKES[char]);

  // Only strip the prefix when the length says one is present: a legitimate body can itself
  // start with "PB", and blindly stripping would corrupt it.
  if (value.length === CODE_LENGTH + DISPLAY_PREFIX.length && value.startsWith(DISPLAY_PREFIX)) {
    value = value.slice(DISPLAY_PREFIX.length);
  }

  if (value.length !== CODE_LENGTH) return null;
  for (const char of value) {
    if (!ALPHABET.includes(char)) return null;
  }
  return value;
}

/** Formats a canonical body back into the printable form. */
export function formatAccessCode(body: string): string {
  const groups: string[] = [];
  for (let i = 0; i < body.length; i += GROUP_SIZE) {
    groups.push(body.slice(i, i + GROUP_SIZE));
  }
  return `${DISPLAY_PREFIX}-${groups.join("-")}`;
}

/**
 * Short human-typeable code for emailed reset/verification flows, e.g. `4K7M9XQR`.
 *
 * 8 characters is 40 bits — far weaker than an access code, which is why these are paired with a
 * short expiry, single use, and rate limiting on the endpoints that consume them.
 */
export function generateShortCode(length = 8): string {
  let code = "";
  for (let i = 0; i < length; i += 1) {
    code += ALPHABET[randomInt(ALPHABET.length)];
  }
  return code;
}

/** Normalizes an emailed short code the same way as an access code, without the length check. */
export function normalizeShortCode(raw: string): string {
  return raw
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "")
    .replace(/[ILOU]/g, (char) => LOOKALIKES[char]);
}

/** SHA-256 of a high-entropy secret. Never store the plaintext of anything passed here. */
export function hashSecret(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

/** 256-bit URL-safe token for reset/verification links and per-device ingest keys. */
export function generateSecretToken(): string {
  return randomBytes(32).toString("base64url");
}
