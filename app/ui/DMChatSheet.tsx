"use client";
import { useState, useEffect, useRef } from "react";
import { Conversation, Message } from "../lib/types";
import { MessageIcon, CloseIcon } from "./Icons";
import { getUserName, loadConversations, saveConversations } from "../lib/storage";

function nid(prefix: string) {
  return prefix + Math.random().toString(16).slice(2) + Date.now().toString(16);
}

function getConversationId(user1: string, user2: string): string {
  const sorted = [user1, user2].sort();
  return `conv_${sorted[0]}_${sorted[1]}`;
}

export default function DMChatSheet({
  otherUserName,
  onClose,
}: {
  otherUserName: string;
  onClose: () => void;
}) {
  const currentUser = getUserName();
  const [conversations, setConversations] = useState<Conversation[]>(loadConversations());
  const [text, setText] = useState("");
  const messagesEndRef = useRef<HTMLDivElement>(null);

  const conversationId = getConversationId(currentUser, otherUserName);
  const conversation = conversations.find((c) => c.id === conversationId);

  useEffect(() => {
    setConversations(loadConversations());
  }, []);

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [conversation?.messages]);

  const sendMessage = () => {
    const t = text.trim();
    if (!t) return;

    const newMessage: Message = {
      id: nid("msg_"),
      fromUserName: currentUser,
      toUserName: otherUserName,
      text: t,
      createdAt: Date.now(),
      read: false,
    };

    let updated = [...conversations];
    let conv = updated.find((c) => c.id === conversationId);

    if (!conv) {
      conv = {
        id: conversationId,
        participants: [currentUser, otherUserName].sort(),
        messages: [],
        lastMessageAt: Date.now(),
      };
      updated.push(conv);
    }

    conv.messages.push(newMessage);
    conv.lastMessageAt = Date.now();
    conv.messages.sort((a, b) => a.createdAt - b.createdAt);

    setConversations(updated);
    saveConversations(updated);
    setText("");
  };

  const messages = conversation?.messages || [];

  return (
    <div className="sheetBackdrop" onClick={onClose}>
      <div className="sheet" onClick={(e) => e.stopPropagation()} style={{ maxHeight: "80vh", display: "flex", flexDirection: "column" }}>
        <div className="row">
          <div>
            <div className="title" style={{ margin: 0 }}>Direct Message</div>
            <div className="muted small" style={{ marginTop: 6 }}>
              Chat with <b>{otherUserName}</b>
            </div>
          </div>
          <button className="btn" onClick={onClose}>
            <CloseIcon />
          </button>
        </div>

        <div style={{ 
          flex: 1, 
          overflowY: "auto", 
          marginTop: 16, 
          marginBottom: 16,
          padding: "12px 0",
          borderTop: "1px solid var(--border)",
          borderBottom: "1px solid var(--border)"
        }}>
          {messages.length === 0 ? (
            <div className="muted" style={{ textAlign: "center", padding: 20 }}>
              No messages yet. Start the conversation!
            </div>
          ) : (
            messages.map((msg) => {
              const isFromMe = msg.fromUserName === currentUser;
              return (
                <div
                  key={msg.id}
                  style={{
                    marginBottom: 12,
                    display: "flex",
                    flexDirection: "column",
                    alignItems: isFromMe ? "flex-end" : "flex-start",
                  }}
                >
                  <div
                    style={{
                      maxWidth: "70%",
                      padding: "10px 14px",
                      borderRadius: 14,
                      background: isFromMe
                        ? "rgba(43,191,94,.2)"
                        : "rgba(255,255,255,.04)",
                      border: `1px solid ${isFromMe ? "rgba(43,191,94,.5)" : "var(--border)"}`,
                    }}
                  >
                    <div className="small muted" style={{ marginBottom: 4 }}>
                      {isFromMe ? "You" : msg.fromUserName}
                    </div>
                    <div>{msg.text}</div>
                    <div className="small muted" style={{ marginTop: 4, fontSize: 10 }}>
                      {new Date(msg.createdAt).toLocaleTimeString()}
                    </div>
                  </div>
                </div>
              );
            })
          )}
          <div ref={messagesEndRef} />
        </div>

        <div className="field" style={{ margin: 0 }}>
          <div style={{ display: "flex", gap: 8 }}>
            <input
              value={text}
              onChange={(e) => setText(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter" && !e.shiftKey) {
                  e.preventDefault();
                  sendMessage();
                }
              }}
              placeholder="Type a message..."
              style={{ flex: 1 }}
            />
            <button className="btn primary" onClick={sendMessage}>
              <MessageIcon /> Send
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

