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

// 重点看这里：必须有 export default
export default function PostCard({
  post, onUpvote, onOpen,
}: {
  post: Post;
  onUpvote: (id: string) => void;
  onOpen: (id: string) => void;
}) {
  const badge =
    post.visibility === "Private" ? "Private" :
    post.category === "Note" ? "Public" : "Alert";

  return (
    <div className="card" onClick={() => onOpen(post.id)} role="button" tabIndex={0}>
      <div className="hd">
        <div className="kicker">
          <span className="pill">{badge}</span>
          <span className="pill">{post.crop}</span>
          <span className="pill">{post.category}</span>
          <span className="pill">Severity {post.severity}</span>
          <span className="muted">· {timeAgo(post.createdAt)} ago</span>
        </div>
        <div className="title">{post.title}</div>
        <div className="body">{post.body}</div>
        <div className="meta">
          <span className="pill small">📍 {post.lat.toFixed(3)}, {post.lng.toFixed(3)}</span>
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