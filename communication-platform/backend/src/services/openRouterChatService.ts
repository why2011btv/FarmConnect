import { FastifyBaseLogger } from "fastify";

type OpenRouterMessageContentPart =
  | { type: "text"; text: string }
  | { type: "image_url"; image_url: { url: string } };

export type ChatMessageInput = {
  role: "user" | "assistant";
  content: string;
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
  const imageUrls = (message.imageDataUrls ?? []).filter((v) => v.trim().length > 0).slice(0, 5);

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
      "You are a helpful farming assistant for vineyard and crop management. " +
      "Help users with agricultural questions, disease and pest identification from images, " +
      "and practical farming best practices. Be concise and actionable.",
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
