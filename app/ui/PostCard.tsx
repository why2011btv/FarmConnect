"use client";
import { Post } from "../lib/types";
import { CommentIcon, UpvoteIcon } from "./Icons";

function timeAgo(ts: number) {
  const mins = Math.floor((Date.now() - ts) / 60000);
  if (mins < 60) return `${mins}m`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h`;
  return `${Math.floor(hrs / 24)}d`;
}

const CATEGORY_THEME: Record<
  Post["category"],
  { cardBg: string; border: string; pillBg: string; pillText: string }
> = {
  Disease: {
    cardBg: "linear-gradient(135deg, rgba(248,113,113,0.24), rgba(15,23,42,0.96))",
    border: "rgba(248,113,113,0.8)",
    pillBg: "rgba(248,113,113,0.22)",
    pillText: "#fecaca",
  },
  Pest: {
    cardBg: "linear-gradient(135deg, rgba(250,204,21,0.18), rgba(15,23,42,0.96))",
    border: "rgba(250,204,21,0.75)",
    pillBg: "rgba(250,204,21,0.20)",
    pillText: "#fef9c3",
  },
  Weather: {
    cardBg: "linear-gradient(135deg, rgba(59,130,246,0.26), rgba(15,23,42,0.96))",
    border: "rgba(59,130,246,0.8)",
    pillBg: "rgba(59,130,246,0.24)",
    pillText: "#bfdbfe",
  },
  Note: {
    cardBg: "linear-gradient(135deg, rgba(148,163,184,0.20), rgba(15,23,42,0.96))",
    border: "rgba(148,163,184,0.7)",
    pillBg: "rgba(148,163,184,0.20)",
    pillText: "#e5e7eb",
  },
  Market: {
    cardBg: "linear-gradient(135deg, rgba(52,211,153,0.26), rgba(15,23,42,0.96))",
    border: "rgba(52,211,153,0.8)",
    pillBg: "rgba(52,211,153,0.24)",
    pillText: "#bbf7d0",
  },
};

// 重点看这里：必须有 export default
export default function PostCard({
  post, onUpvote, onOpen, onMessage,
}: {
  post: Post;
  onUpvote: (id: string) => void;
  onOpen: (id: string) => void;
  onMessage?: (userName: string) => void;
}) {
  const badge =
    post.visibility === "Private" ? "Private" :
    post.category === "Note" ? "Public" : "Alert";

  const theme = CATEGORY_THEME[post.category];

  return (
    <div
      className="card"
      onClick={() => onOpen(post.id)}
      role="button"
      tabIndex={0}
      style={{
        background: theme.cardBg,
        borderColor: theme.border,
      }}
    >
      <div className="hd">
        <div className="kicker">
          <span className="pill">{badge}</span>
          <span className="pill">{post.crop}</span>
          <span
            className="pill"
            style={{
              borderColor: theme.border,
              background: theme.pillBg,
              color: theme.pillText,
            }}
          >
            {post.category}
          </span>
          <span className="pill">Severity {post.severity}</span>
          <span className="muted">· {timeAgo(post.createdAt)} ago</span>
        </div>
        <div className="title">{post.title}</div>
        {post.imageUrl && (
          <div style={{ marginTop: 8, marginBottom: 8, borderRadius: 12, overflow: "hidden" }}>
            <img 
              src={post.imageUrl} 
              alt={post.title}
              style={{ width: "100%", height: "auto", display: "block", maxHeight: "300px", objectFit: "cover" }}
            />
          </div>
        )}
        <div className="body">{post.body}</div>
        <div className="meta">
          <span 
            className="pill small" 
            style={{ cursor: onMessage ? "pointer" : "default", userSelect: "none" }}
            onClick={(e) => {
              e.stopPropagation();
              if (onMessage) onMessage(post.userName);
            }}
            onMouseEnter={(e) => {
              if (onMessage) {
                e.currentTarget.style.opacity = "0.8";
                e.currentTarget.style.textDecoration = "underline";
              }
            }}
            onMouseLeave={(e) => {
              if (onMessage) {
                e.currentTarget.style.opacity = "1";
                e.currentTarget.style.textDecoration = "none";
              }
            }}
          >
            👤 {post.userName}
          </span>
          <span className="pill small">📍 {post.city || "Unknown"}</span>
        </div>
      </div>

      <div className="actions" onClick={(e) => e.stopPropagation()}>
        <button onClick={() => onUpvote(post.id)} aria-label="Upvote">
          <UpvoteIcon /> <span>{post.upvotes}</span>
        </button>
        <button onClick={() => onOpen(post.id)} aria-label="Comments">
          <CommentIcon /> <span>{post.comments.length}</span>
        </button>
        <span className="muted">Credit = upvotes</span>
      </div>
    </div>
  );
}