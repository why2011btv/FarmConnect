"use client";
import { useEffect, useMemo, useState } from "react";
import { loadPosts, savePosts } from "./lib/storage";
import { Post } from "./lib/types";
import PostCard from "./ui/PostCard";
import CommentsSheet from "./ui/CommentsSheet";
import MapView from "./ui/MapView";
import NewPostSheet from "./ui/NewPostSheet";
import { FeedIcon, MapPinIcon, PlusIcon } from "./ui/Icons";

function nid(prefix: string) {
  return prefix + Math.random().toString(16).slice(2) + Date.now().toString(16);
}

export default function Home() {
  const [mode, setMode] = useState<"feed" | "map">("feed");
  const [posts, setPosts] = useState<Post[]>([]);
  const [query, setQuery] = useState("");
  const [openPostId, setOpenPostId] = useState<string | null>(null);
  const [isNewOpen, setIsNewOpen] = useState(false);
  const [center, setCenter] = useState({ lat: 25.7742, lng: -80.1936 });

  useEffect(() => setPosts(loadPosts()), []);
  useEffect(() => { if (posts.length) savePosts(posts); }, [posts]);

  useEffect(() => {
    if (!navigator.geolocation) return;
    navigator.geolocation.getCurrentPosition(
      (pos) => setCenter({ lat: pos.coords.latitude, lng: pos.coords.longitude }),
      () => {},
      { timeout: 2500 }
    );
  }, []);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    const list = posts.slice().sort((a, b) => b.createdAt - a.createdAt);
    if (!q) return list;
    return list.filter((p) =>
      [p.title, p.body, p.crop, p.category].some((x) => x.toLowerCase().includes(q))
    );
  }, [posts, query]);

  const openPost = useMemo(() => posts.find((p) => p.id === openPostId) || null, [posts, openPostId]);

  const onUpvote = (pid: string) =>
    setPosts((prev) => prev.map((p) => (p.id === pid ? { ...p, upvotes: p.upvotes + 1 } : p)));

  const onAddComment = (pid: string, text: string) =>
    setPosts((prev) =>
      prev.map((p) =>
        p.id === pid ? { ...p, comments: [{ id: nid("c_"), text, createdAt: Date.now() }, ...p.comments] } : p
      )
    );

  const createPost = (p: Post) => {
    setPosts((prev) => [p, ...prev]);
    if (p.visibility === "Public") setMode("map");
  };

  return (
    <main className="container">
      <div className="topbar">
        <div className="brand">
          <div className="logo">FA</div>
          <div>
            <div style={{ fontWeight: 800 }}>Farm Alert</div>
            <div className="muted small">Feed ↔ Map · Comments + Upvotes (credit)</div>
          </div>
        </div>

        <div className="search">
          <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search disease/pest/crop…" />
        </div>

        <div className="seg">
          <button className={mode === "feed" ? "active" : ""} onClick={() => setMode("feed")}>
            <FeedIcon /> Feed
          </button>
          <button className={mode === "map" ? "active" : ""} onClick={() => setMode("map")}>
            <MapPinIcon /> Map
          </button>
        </div>
      </div>

      {mode === "feed" ? (
        <div className="grid">
          {filtered.map((p) => (
            <PostCard key={p.id} post={p} onUpvote={onUpvote} onOpen={setOpenPostId} />
          ))}
        </div>
      ) : (
        <div>
          <MapView posts={posts} selectedId={openPostId} onSelect={setOpenPostId} center={center} />
          <div className="muted small" style={{ marginTop: 10 }}>
            Map shows <b>public</b> posts only. Private posts stay local and never appear on the map.
          </div>
        </div>
      )}

      <button className="fab" aria-label="New post" onClick={() => setIsNewOpen(true)}>
        <PlusIcon />
      </button>

      {openPost && (
        <CommentsSheet
          post={openPost}
          onClose={() => setOpenPostId(null)}
          onUpvote={() => onUpvote(openPost.id)}
          onAddComment={(t) => onAddComment(openPost.id, t)}
        />
      )}

      {isNewOpen && (
        <NewPostSheet
          defaultLat={center.lat}
          defaultLng={center.lng}
          onClose={() => setIsNewOpen(false)}
          onCreate={createPost}
        />
      )}
    </main>
  );
}