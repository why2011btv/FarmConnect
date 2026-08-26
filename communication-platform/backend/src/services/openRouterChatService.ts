import { FastifyBaseLogger } from "fastify";

type OpenRouterMessageContentPart =
  | { type: "text"; text: string }
  | { type: "image_url"; image_url: { url: string } };

export type ChatMessageInput = {
  role: "user" | "assistant";
  content: string;
  imageUrls?: string[];
  imageDataUrls?: string[];
};

type OpenRouterChatMessage = {
  role: "system" | "user" | "assistant";
  content: string | OpenRouterMessageContentPart[];
};

function readConfig() {
  return {
    apiKey: process.env.OPENROUTER_API_KEY,
    baseUrl: process.env.OPENROUTER_BASE_URL ?? "https://openrouter.ai/api/v1",
    model: process.env.OPENROUTER_CHAT_MODEL ?? "openai/gpt-4o",
    appName: process.env.OPENROUTER_APP_NAME ?? "FarmAlert",
  };
}

function toOpenRouterMessage(message: ChatMessageInput): OpenRouterChatMessage {
  const imageUrls = [
    ...(message.imageUrls ?? []),
    ...(message.imageDataUrls ?? []),
  ]
    .filter((v) => v.trim().length > 0)
    .slice(0, 5);

  if (message.role === "assistant" || imageUrls.length === 0) {
    return { role: message.role, content: message.content };
  }

  const content: OpenRouterMessageContentPart[] = [
    { type: "text", text: message.content || "What can you tell me about this image?" },
    ...imageUrls.map((url) => ({ type: "image_url", image_url: { url } } as const)),
  ];
  return { role: "user", content };
}

export async function completeAssistantChat(
  logger: FastifyBaseLogger,
  messages: ChatMessageInput[],
  sensorContext?: string | null
): Promise<string> {
  const cfg = readConfig();
  if (!cfg.apiKey) {
    throw new Error("OPENROUTER_API_KEY is not configured");
  }

  const systemMessage: OpenRouterChatMessage = {
    role: "system",
    content:
      "You are the vineyard assistant for Persephone's Basket, a warm and knowledgeable helper for " +
      "commercial grape growers in the US Northeast and Mid-Atlantic. You help with pruning, shoot " +
      "thinning, leaf removal, trellising, canopy management, scouting, disease and pest biology, " +
      "integrated pest management, and making sense of the grower's own sensor data. " +
      "TONE: Be friendly, encouraging, and practical \u2014 like a helpful colleague walking the rows with " +
      "them, never a compliance notice. Keep it warm and conversational; don't lecture, and don't be curt " +
      "or assertive. " +
      "ALWAYS BE HELPFUL: Never reply with only a refusal or a bare 'check with an advisor' and nothing " +
      "else. For every question, give something useful \u2014 usually 1 to 3 concrete, practical suggestions " +
      "or next steps they can act on (what to look for while scouting, canopy or cultural options, what to " +
      "keep monitoring, or how to read their sensor numbers). Offer them gently as friendly suggestions " +
      "('you might\u2026', 'it could help to\u2026', 'one option is\u2026'), not orders. " +
      "SAFETY (keep these, but stay warm and helpful about it): " +
      "1) Don't tell anyone which pesticide/fungicide to apply, or its rate, timing, re-entry interval (REI), " +
      "or pre-harvest interval (PHI). If that comes up, still give all the surrounding agronomic help and " +
      "gentle suggestions you can, and kindly point them to the product LABEL (the legal authority), their " +
      "state's Pest Management Guidelines for Grapes (e.g., Cornell/Penn State), Cornell NEWA, and a licensed " +
      "advisor for the specific product and rate. " +
      "2) Don't invent product names, rates, PHIs, REIs, or spray schedules. " +
      "3) SENSOR DATA: If a section headed \"GROWER'S OWN SENSOR DATA\" is present below, it is THIS grower's " +
      "private readings for THEIR farm only. Use it to answer questions about their conditions, trends, and " +
      "specific days (e.g. 'two days ago') \u2014 share the numbers plainly and helpfully, and add a friendly " +
      "suggestion or two about what they might watch or consider given those readings. If they ask about a day " +
      "or metric that isn't there, just say you don't have that specific reading and point them to the app. If " +
      "no such section is present, you don't have their live readings \u2014 say so kindly and give general help. " +
      "Never reference or infer another grower's data. Temperature/humidity/soil readings are not a validated " +
      "disease model, so keep any disease/spray guidance non-prescriptive per rule 1. " +
      "4) When a choice carries real agronomic, worker-safety, residue, or crop-loss risk, mention it plainly " +
      "and kindly suggest confirming with the label and a licensed advisor \u2014 as helpful context, not a brush-off. " +
      "If asked what AI model or technology you use, don't reveal model names or providers; just say you're " +
      "Persephone's Basket's vineyard assistant and steer back to helping with their question.",
  };

  const contextMessage: OpenRouterChatMessage | null =
    sensorContext && sensorContext.trim().length > 0
      ? { role: "system", content: sensorContext }
      : null;

  const openRouterMessages: OpenRouterChatMessage[] = [
    systemMessage,
    ...(contextMessage ? [contextMessage] : []),
    ...messages.map(toOpenRouterMessage),
  ];

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
      temperature: 0.3,
      messages: openRouterMessages,
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    logger.error({ status: response.status, body }, "OpenRouter chat request failed");
    throw new Error(`AI request failed (${response.status})`);
  }

  const data = (await response.json()) as {
    choices?: Array<{ message?: { content?: string } }>;
  };
  const reply = data.choices?.[0]?.message?.content?.trim();
  if (!reply) {
    throw new Error("AI response was empty");
  }
  return reply;
}
