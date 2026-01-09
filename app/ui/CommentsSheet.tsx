"use client";
import { useState } from "react";
import { Post } from "../lib/types";
import { CommentIcon, UpvoteIcon } from "./Icons";
import { getUserName, setUserName } from "../lib/storage";

export default function CommentsSheet({
  post, onClose, onUpvote, onAddComment, onMessage,
}: {
  post: Post;
  onClose: () => void;
  onUpvote: () => void;
  onAddComment: (text: string, userName: string) => void;
  onMessage?: (userName: string) => void;
}) {
  const [text, setText] = useState("");
  const [userName] = useState(getUserName());

  return (
    <div className="sheetBackdrop" onClick={onClose}>
      <div className="sheet" onClick={(e) => e.stopPropagation()}>
        <div className="row">
          <div>
            <div className="title" style={{ margin: 0 }}>{post.title}</div>
            <div className="kicker" style={{ marginTop: 8 }}>
              <span className="pill">{post.visibility}</span>
              <span className="pill">{post.crop}</span>
              <span className="pill">{post.category}</span>
              <span className="pill">Severity {post.severity}</span>
              <span 
                className="pill" 
                style={{ cursor: onMessage ? "pointer" : "default", userSelect: "none" }}
                onClick={() => onMessage && onMessage(post.userName)}
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
            </div>
          </div>
          <button className="btn" onClick={onClose}>Close</button>
        </div>

        {post.imageUrl && (
          <div style={{ marginTop: 12, marginBottom: 12, borderRadius: 12, overflow: "hidden" }}>
            <img 
              src={post.imageUrl} 
              alt={post.title}
              style={{ width: "100%", height: "auto", display: "block", maxHeight: "400px", objectFit: "cover" }}
            />
          </div>
        )}

        <p className="body" style={{ marginTop: 12 }}>{post.body}</p>

        <div className="actions" style={{ paddingLeft: 0 }}>
          <button onClick={onUpvote}><UpvoteIcon /> <span>{post.upvotes}</span></button>
          <span className="muted">Upvotes = credit (higher credit → higher visibility)</span>
        </div>

        <div className="field">
          <label>Add a comment</label>
          <textarea
            value={text}
            onChange={(e) => setText(e.target.value)}
            placeholder="What did you see? Where? What action worked?"
          />
          <div className="btnRow">
            <button className="btn" onClick={() => setText("")}>Clear</button>
            <button
              className="btn primary"
              onClick={() => {
                const t = text.trim();
                if (!t) return;
                onAddComment(t, userName);
                setText("");
              }}
            >
              <CommentIcon /> Post
            </button>
          </div>
        </div>

        <div className="kicker" style={{ marginTop: 6 }}>
          <span className="pill">{post.comments.length} comments</span>
          <span className="muted">· newest first</span>
        </div>

        {post.comments.map((c) => (
          <div className="comment" key={c.id}>
            <div className="kicker">
              <span className="pill">Comment</span>
              {c.userName && (
                <span 
                  className="pill" 
                  style={{ cursor: onMessage ? "pointer" : "default", userSelect: "none" }}
                  onClick={() => onMessage && onMessage(c.userName!)}
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
                  👤 {c.userName}
                </span>
              )}
              <span className="muted">{new Date(c.createdAt).toLocaleString()}</span>
            </div>
            <p>{c.text}</p>
          </div>
        ))}
      </div>
    </div>
  );
}