"use client";
import { useEffect, useMemo, useState } from "react";
import { loadPosts, savePosts, getUserName } from "./lib/storage";
import { Post } from "./lib/types";
import PostCard from "./ui/PostCard";
import CommentsSheet from "./ui/CommentsSheet";
import MapView from "./ui/MapView";
import NewPostSheet from "./ui/NewPostSheet";
import DMChatSheet from "./ui/DMChatSheet";
import UserMenuSheet from "./ui/UserMenuSheet";
import ConversationsList from "./ui/ConversationsList";
import { FeedIcon, MapPinIcon, PlusIcon, NotesIcon, MessageIcon } from "./ui/Icons";

function nid(prefix: string) {
  return prefix + Math.random().toString(16).slice(2) + Date.now().toString(16);
}

type TimeFilter = "1d" | "3d" | "1w" | "3w" | "all";

function getTimeFilterCutoff(filter: TimeFilter): number {
  const now = Date.now();
  switch (filter) {
    case "1d": return now - 24 * 60 * 60 * 1000;
    case "3d": return now - 3 * 24 * 60 * 60 * 1000;
    case "1w": return now - 7 * 24 * 60 * 60 * 1000;
    case "3w": return now - 21 * 24 * 60 * 60 * 1000;
    case "all": return 0;
  }
}

export default function Home() {
  const [mode, setMode] = useState<"feed" | "map" | "notes" | "messages">("feed");
  const [posts, setPosts] = useState<Post[]>([]);
  const [query, setQuery] = useState("");
  const [timeFilter, setTimeFilter] = useState<TimeFilter>("all");
  const [openPostId, setOpenPostId] = useState<string | null>(null);
  const [isNewOpen, setIsNewOpen] = useState(false);
  const [dmUserName, setDmUserName] = useState<string | null>(null);
  const [selectedUserName, setSelectedUserName] = useState<string | null>(null);
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
    const cutoff = getTimeFilterCutoff(timeFilter);
    let list = posts.slice();
    
    // Apply time filter
    if (timeFilter !== "all") {
      list = list.filter((p) => p.createdAt >= cutoff);
    }
    
    // Sort by most recent
    list.sort((a, b) => b.createdAt - a.createdAt);
    
    // Apply search query
    if (!q) return list;
    return list.filter((p) =>
      [p.title, p.body, p.crop, p.category].some((x) => x.toLowerCase().includes(q))
    );
  }, [posts, query, timeFilter]);

  const filteredNotes = useMemo(() => {
    const currentUser = getUserName();
    const cutoff = getTimeFilterCutoff(timeFilter);
    let list = posts.filter((p) => p.visibility === "Private" && p.userName === currentUser);
    
    // Apply time filter
    if (timeFilter !== "all") {
      list = list.filter((p) => p.createdAt >= cutoff);
    }
    
    // Sort by most recent
    list.sort((a, b) => b.createdAt - a.createdAt);
    
    return list;
  }, [posts, timeFilter]);

  const openPost = useMemo(() => posts.find((p) => p.id === openPostId) || null, [posts, openPostId]);

  const onUpvote = (pid: string) =>
    setPosts((prev) => prev.map((p) => (p.id === pid ? { ...p, upvotes: p.upvotes + 1 } : p)));

  const onAddComment = (pid: string, text: string, userName: string) =>
    setPosts((prev) =>
      prev.map((p) =>
        p.id === pid ? { ...p, comments: [{ id: nid("c_"), text, createdAt: Date.now(), userName }, ...p.comments] } : p
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

        <div className="timeFilter">
          <select 
            value={timeFilter} 
            onChange={(e) => setTimeFilter(e.target.value as TimeFilter)}
            style={{
              padding: "8px 12px",
              borderRadius: "14px",
              border: "1px solid var(--border)",
              background: "rgba(255,255,255,.04)",
              color: "var(--text)",
              outline: "none",
              fontSize: "14px",
              cursor: "pointer"
            }}
          >
            <option value="1d">Last 1 day</option>
            <option value="3d">Last 3 days</option>
            <option value="1w">Last 1 week</option>
            <option value="3w">Last 3 weeks</option>
            <option value="all">All time</option>
          </select>
        </div>

        <div className="seg">
          <button className={mode === "feed" ? "active" : ""} onClick={() => setMode("feed")}>
            <FeedIcon /> Feed
          </button>
          <button className={mode === "map" ? "active" : ""} onClick={() => setMode("map")}>
            <MapPinIcon /> Map
          </button>
          <button className={mode === "notes" ? "active" : ""} onClick={() => setMode("notes")}>
            <NotesIcon /> Notes
          </button>
          <button className={mode === "messages" ? "active" : ""} onClick={() => setMode("messages")}>
            <MessageIcon /> Chat
          </button>
        </div>
      </div>

      {mode === "feed" ? (
        <div className="grid">
          {filtered.map((p) => (
            <PostCard 
              key={p.id} 
              post={p} 
              onUpvote={onUpvote} 
              onOpen={setOpenPostId}
              onMessage={(userName) => {
                setSelectedUserName(userName);
              }}
            />
          ))}
        </div>
      ) : mode === "map" ? (
        <div>
          <MapView posts={filtered} selectedId={openPostId} onSelect={setOpenPostId} center={center} />
          <div className="muted small" style={{ marginTop: 10 }}>
            Map shows <b>public</b> posts only. Private posts stay local and never appear on the map.
          </div>
        </div>
      ) : mode === "notes" ? (
        <div className="grid">
          {filteredNotes.length === 0 ? (
            <div className="muted" style={{ textAlign: "center", padding: 40 }}>
              No private notes yet. Create a private post to see it here.
            </div>
          ) : (
            filteredNotes.map((p) => (
              <PostCard 
                key={p.id} 
                post={p} 
                onUpvote={onUpvote} 
                onOpen={setOpenPostId}
                onMessage={(userName) => {
                  setSelectedUserName(userName);
                }}
              />
            ))
          )}
        </div>
      ) : mode === "messages" ? (
        <ConversationsList onClose={() => setMode("feed")} />
      ) : null}

      <button className="fab" aria-label="New post" onClick={() => setIsNewOpen(true)}>
        <PlusIcon />
      </button>

      {openPost && (
        <CommentsSheet
          post={openPost}
          onClose={() => setOpenPostId(null)}
          onUpvote={() => onUpvote(openPost.id)}
          onAddComment={(t, userName) => onAddComment(openPost.id, t, userName)}
          onMessage={(userName) => {
            setSelectedUserName(userName);
          }}
        />
      )}

      {selectedUserName && (
        <UserMenuSheet
          userName={selectedUserName}
          onClose={() => setSelectedUserName(null)}
          onStartChat={() => {
            setDmUserName(selectedUserName);
            setSelectedUserName(null);
          }}
        />
      )}

      {dmUserName && (
        <DMChatSheet
          otherUserName={dmUserName}
          onClose={() => setDmUserName(null)}
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