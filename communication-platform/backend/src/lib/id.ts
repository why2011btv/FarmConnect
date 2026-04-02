export function createId(prefix: string) {
  return `${prefix}_${Math.random().toString(16).slice(2)}${Date.now().toString(16)}`;
}

export function getConversationId(a: string, b: string) {
  return [a, b].sort().join("_");
}
