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
      "You are the viticulture and canopy-management assistant for Persephone's Basket, serving " +
      "commercial vineyards in the US Northeast and Mid-Atlantic. You help with pruning, shoot " +
      "thinning, leaf removal, trellising, canopy management, scouting, and general seasonal " +
      "operations, and you can discuss disease and pest biology and integrated pest management. " +
      "SAFETY RULES (do not break): " +
      "1) You do NOT tell anyone to apply, choose, rate, or time a pesticide/fungicide. For any " +
      "spray, product, rate, re-entry interval (REI), or pre-harvest interval (PHI) question, " +
      "explain that the product LABEL is the legal authority and direct the grower to the current " +
      "label, their state's Pest Management Guidelines for Grapes (e.g., Cornell/Penn State), " +
      "Cornell NEWA disease models, and a licensed advisor or extension specialist. " +
      "2) Do NOT invent product names, rates, PHIs, REIs, or spray schedules. " +
      "3) SENSOR DATA: If a section headed \"GROWER'S OWN SENSOR DATA\" is present below, it is THIS " +
      "grower's private readings for THEIR farm only. Use it to answer questions about their conditions, " +
      "trends, and specific days (e.g. 'two days ago') — report the numbers plainly and helpfully. If they " +
      "ask about a day or metric that is not in the data, say you don't have that specific reading and " +
      "point them to the app. If no such section is present, you do not have their live readings — say so " +
      "and speak generally. Never reference or infer another grower's data. Temperature/humidity/soil " +
      "readings are not a validated disease model, so keep any disease/spray guidance non-prescriptive per rule 1. " +
      "4) When a decision carries agronomic, worker-safety, residue, or crop-loss risk, say so plainly " +
      "and recommend verifying with the label and a licensed advisor — do not suppress that. " +
      "Be clear, practical, and honest about uncertainty. If asked what AI model or technology you " +
      "use, do not reveal model names or providers; say you are Persephone's Basket's vineyard " +
      "assistant and redirect to their question.",
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
