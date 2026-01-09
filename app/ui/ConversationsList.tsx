"use client";
import { useState, useMemo, useEffect } from "react";
import { Conversation, Message } from "../lib/types";
import { MessageIcon, CloseIcon } from "./Icons";
import { getUserName, loadConversations } from "../lib/storage";
import DMChatSheet from "./DMChatSheet";

function timeAgo(ts: number) {
  const mins = Math.floor((Date.now() - ts) / 60000);
  if (mins < 60) return `${mins}m`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h`;
  return `${Math.floor(hrs / 24)}d`;
}

export default function ConversationsList({
  onClose,
}: {
  onClose: () => void;
}) {
  const currentUser = getUserName();
  const [conversations, setConversations] = useState<Conversation[]>(loadConversations());
  const [selectedUserName, setSelectedUserName] = useState<string | null>(null);

  // Refresh conversations periodically
  useEffect(() => {
    const interval = setInterval(() => {
      setConversations(loadConversations());
    }, 1000);
    return () => clearInterval(interval);
  }, []);

  const sortedConversations = useMemo(() => {
    return [...conversations].sort((a, b) => b.lastMessageAt - a.lastMessageAt);
  }, [conversations]);

  const getOtherUser = (conv: Conversation): string => {
    return conv.participants.find((p) => p !== currentUser) || conv.participants[0];
  };

  const getLastMessage = (conv: Conversation): Message | null => {
    if (conv.messages.length === 0) return null;
    return conv.messages[conv.messages.length - 1];
  };

  const getUnreadCount = (conv: Conversation): number => {
    return conv.messages.filter(
      (m) => m.toUserName === currentUser && !m.read
    ).length;
  };

  return (
    <>
      <div className="sheetBackdrop" onClick={onClose}>
        <div className="sheet" onClick={(e) => e.stopPropagation()} style={{ maxHeight: "80vh", display: "flex", flexDirection: "column" }}>
          <div className="row">
            <div>
              <div className="title" style={{ margin: 0 }}>Messages</div>
              <div className="muted small" style={{ marginTop: 6 }}>
                Your conversations
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
            padding: "12px 0",
            borderTop: "1px solid var(--border)"
          }}>
            {sortedConversations.length === 0 ? (
              <div className="muted" style={{ textAlign: "center", padding: 40 }}>
                No conversations yet. Start chatting with someone!
              </div>
            ) : (
              sortedConversations.map((conv) => {
                const otherUser = getOtherUser(conv);
                const unreadCount = getUnreadCount(conv);

                return (
                  <div
                    key={conv.id}
                    onClick={() => setSelectedUserName(otherUser)}
                    style={{
                      padding: "14px 16px",
                      borderBottom: "1px solid var(--border)",
                      cursor: "pointer",
                      display: "flex",
                      alignItems: "center",
                      gap: 12,
                    }}
                    onMouseEnter={(e) => {
                      e.currentTarget.style.background = "rgba(255,255,255,.04)";
                    }}
                    onMouseLeave={(e) => {
                      e.currentTarget.style.background = "transparent";
                    }}
                  >
                    <div style={{
                      width: 44,
                      height: 44,
                      borderRadius: "50%",
                      background: "linear-gradient(135deg,var(--brand),var(--brand2))",
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "center",
                      fontWeight: 800,
                      fontSize: 18,
                      color: "white",
                    }}>
                      {otherUser.charAt(0).toUpperCase()}
                    </div>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                        <div style={{ fontWeight: 600, fontSize: 16 }}>{otherUser}</div>
                        {unreadCount > 0 && (
                          <span style={{
                            background: "rgba(43,191,94,.3)",
                            color: "var(--brand2)",
                            padding: "2px 8px",
                            borderRadius: 999,
                            fontSize: 11,
                            fontWeight: 600,
                          }}>
                            {unreadCount}
                          </span>
                        )}
                      </div>
                    </div>
                  </div>
                );
              })
            )}
          </div>
        </div>
      </div>

      {selectedUserName && (
        <DMChatSheet
          otherUserName={selectedUserName}
          onClose={() => setSelectedUserName(null)}
        />
      )}
    </>
  );
}

