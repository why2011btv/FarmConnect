"use client";
import { useMemo } from "react";
import { MessageIcon, CloseIcon } from "./Icons";
import { getUserName, loadPosts } from "../lib/storage";
import { Post } from "../lib/types";

export default function UserMenuSheet({
  userName,
  onClose,
  onStartChat,
}: {
  userName: string;
  onClose: () => void;
  onStartChat: () => void;
}) {
  const currentUser = getUserName();
  const isCurrentUser = userName === currentUser;
  
  const totalUpvotes = useMemo(() => {
    const posts = loadPosts();
    return posts
      .filter((p: Post) => p.userName === userName)
      .reduce((sum: number, p: Post) => sum + p.upvotes, 0);
  }, [userName]);

  return (
    <div className="sheetBackdrop" onClick={onClose}>
      <div className="sheet" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 400 }}>
        <div className="row">
          <div>
            <div className="title" style={{ margin: 0 }}>User Profile</div>
            <div className="muted small" style={{ marginTop: 6 }}>
              {userName}
            </div>
          </div>
          <button className="btn" onClick={onClose}>
            <CloseIcon />
          </button>
        </div>

        <div style={{ marginTop: 20 }}>
          <div style={{
            padding: "16px",
            background: "rgba(255,255,255,.04)",
            borderRadius: 12,
            border: "1px solid var(--border)",
            marginBottom: 16,
          }}>
            <div className="muted small" style={{ marginBottom: 4 }}>Total Upvotes</div>
            <div style={{ fontSize: 24, fontWeight: 700, color: "var(--brand2)" }}>
              {totalUpvotes}
            </div>
          </div>
          
          {!isCurrentUser ? (
            <button
              className="btn primary"
              onClick={() => {
                onStartChat();
                onClose();
              }}
              style={{ width: "100%", justifyContent: "center" }}
            >
              <MessageIcon /> Start Chat
            </button>
          ) : (
            <div className="muted" style={{ textAlign: "center", padding: 20 }}>
              This is your own profile
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

