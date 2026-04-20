import { FastifyBaseLogger } from "fastify";

type ModerationResult = {
  allowed: boolean;
  reason?: string;
};

type ModerationPayload = {
  text: string;
  imageUrls?: string[];
};

type OpenRouterMessageContentPart =
  | { type: "text"; text: string }
  | { type: "image_url"; image_url: { url: string } };

function readConfig() {
  return {
    apiKey: process.env.OPENROUTER_API_KEY,
    baseUrl: process.env.OPENROUTER_BASE_URL ?? "https://openrouter.ai/api/v1",
    model: process.env.OPENROUTER_MODERATION_MODEL ?? "openai/gpt-4o-mini",
    appName: process.env.OPENROUTER_APP_NAME ?? "FarmAlert",
  };
}

function tryParseJsonResult(content: string): ModerationResult | null {
  const trimmed = content.trim();
  try {
    const parsed = JSON.parse(trimmed) as { allowed?: boolean; reason?: string };
    if (typeof parsed.allowed === "boolean") {
      return { allowed: parsed.allowed, reason: parsed.reason };
    }
  } catch {
    // ignore and try extracting first JSON object block
  }

  const match = trimmed.match(/\{[\s\S]*\}/);
  if (!match) return null;
  try {
    const parsed = JSON.parse(match[0]) as { allowed?: boolean; reason?: string };
    if (typeof parsed.allowed === "boolean") {
      return { allowed: parsed.allowed, reason: parsed.reason };
    }
  } catch {
    return null;
  }
  return null;
}

export async function moderateUserContent(
  logger: FastifyBaseLogger,
  payload: ModerationPayload
): Promise<ModerationResult> {
  const cfg = readConfig();
  if (!cfg.apiKey) {
    // If key is not configured, run in permissive mode.
    return { allowed: true };
  }

  const userText = payload.text.trim();
  const imageUrls = (payload.imageUrls ?? []).filter((v) => v.trim().length > 0).slice(0, 5);

  const instruction = [
    "You are a strict safety moderation classifier for a farming social app.",
    "Decide whether the user content should be allowed.",
    "Block if content is sexual/explicit/pornographic, hateful/harassing/toxic/abusive, self-harm encouragement, violent threats, or illegal exploitation.",
    "Return ONLY JSON in this exact format: {\"allowed\": true|false, \"reason\": \"short reason\"}.",
    "If uncertain, choose allowed=false with a short reason.",
  ].join(" ");

  const content: OpenRouterMessageContentPart[] = [
    { type: "text", text: `${instruction}\n\nUser text:\n${userText || "(empty)"}` },
    ...imageUrls.map((url) => ({ type: "image_url", image_url: { url } } as const)),
  ];

  try {
    const response = await fetch(`${cfg.baseUrl}/chat/completions`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${cfg.apiKey}`,
        "Content-Type": "application/json",
        "HTTP-Referer": "https://farmalert.local",
        "X-Title": cfg.appName,
      },
      body: JSON.stringify({
        model: cfg.model,
        temperature: 0,
        response_format: { type: "json_object" },
        messages: [{ role: "user", content }],
      }),
    });

    if (!response.ok) {
      const body = await response.text();
      logger.warn({ status: response.status, body }, "Moderation request failed; allowing content");
      return { allowed: true };
    }

    const data = (await response.json()) as {
      choices?: Array<{ message?: { content?: string } }>;
    };
    const rawContent = data.choices?.[0]?.message?.content;
    if (!rawContent) {
      logger.warn("Moderation response missing content; allowing content");
      return { allowed: true };
    }

    const parsed = tryParseJsonResult(rawContent);
    if (!parsed) {
      logger.warn({ rawContent }, "Failed to parse moderation JSON; allowing content");
      return { allowed: true };
    }
    return parsed;
  } catch (error) {
    logger.warn({ error }, "Moderation call crashed; allowing content");
    return { allowed: true };
  }
}
