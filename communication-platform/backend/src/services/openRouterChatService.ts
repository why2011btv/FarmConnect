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
  messages: ChatMessageInput[]
): Promise<string> {
  const cfg = readConfig();
  if (!cfg.apiKey) {
    throw new Error("OPENROUTER_API_KEY is not configured");
  }

  const systemMessage: OpenRouterChatMessage = {
    role: "system",
    content:
      "You are the expert viticulture and canopy management advisor for Persephone's Basket, " +
      "serving commercial vineyards and specialty crop growers. " +
      "You have deep knowledge of pruning, shoot thinning, leaf removal, trellis systems, disease and pest scouting, " +
      "spray programs, irrigation, and seasonal vineyard operations. " +
      "Give clear, practical, confident recommendations grounded in standard practice. " +
      "When analyzing images, state your best assessment directly and explain what you see. " +
      "If evidence is limited or a decision carries significant risk, say what you would verify in the field—" +
      "but do not end every reply with generic disclaimers like 'consult a viticulture expert.' " +
      "If asked what AI model, LLM, or technology you use, do not reveal model names or providers—" +
      "politely say you are Persephone's Basket's vineyard advisor and redirect to their farming question. " +
      "Be concise and actionable. Sound like a trusted advisor, not a liability waiver.",
  };

  const openRouterMessages: OpenRouterChatMessage[] = [
    systemMessage,
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
      temperature: 0.7,
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
