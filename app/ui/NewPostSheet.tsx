"use client";
import { useState } from "react";
import { Post } from "../lib/types";
import { PlusIcon } from "./Icons";

function nid(prefix: string) {
  return prefix + Math.random().toString(16).slice(2) + Date.now().toString(16);
}

export default function NewPostSheet({
  defaultLat, defaultLng, onClose, onCreate,
}: {
  defaultLat: number;
  defaultLng: number;
  onClose: () => void;
  onCreate: (p: Post) => void;
}) {
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [crop, setCrop] = useState("Corn");
  const [category, setCategory] = useState<Post["category"]>("Disease");
  const [severity, setSeverity] = useState<Post["severity"]>(3);
  const [visibility, setVisibility] = useState<Post["visibility"]>("Public");
  const [lat, setLat] = useState(defaultLat.toFixed(5));
  const [lng, setLng] = useState(defaultLng.toFixed(5));

  const useMyLocation = () => {
    if (!navigator.geolocation) return;
    navigator.geolocation.getCurrentPosition((pos) => {
      setLat(pos.coords.latitude.toFixed(5));
      setLng(pos.coords.longitude.toFixed(5));
    });
  };

  return (
    <div className="sheetBackdrop" onClick={onClose}>
      <div className="sheet" onClick={(e) => e.stopPropagation()}>
        <div className="row">
          <div>
            <div className="title" style={{ margin: 0 }}>Create a post</div>
            <div className="muted small" style={{ marginTop: 6 }}>
              Public posts show in feed + map. Private posts stay on your device.
            </div>
          </div>
          <button className="btn" onClick={onClose}>Close</button>
        </div>

        <div className="field">
          <label>Title</label>
          <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="e.g., Powdery mildew spotted" />
        </div>

        <div className="field">
          <label>Description</label>
          <textarea value={body} onChange={(e) => setBody(e.target.value)} placeholder="What did you see? Where? Any action taken?" />
        </div>

        <div className="grid">
          <div className="field">
            <label>Crop</label>
            <select value={crop} onChange={(e) => setCrop(e.target.value)}>
              <option>Corn</option><option>Wheat</option><option>Apple</option>
              <option>Grape</option><option>Vegetables</option><option>Mixed</option>
            </select>
          </div>

          <div className="field">
            <label>Category</label>
            <select value={category} onChange={(e) => setCategory(e.target.value as any)}>
              <option value="Disease">Disease</option>
              <option value="Pest">Pest</option>
              <option value="Weather">Weather</option>
              <option value="Note">Note</option>
            </select>
          </div>

          <div className="field">
            <label>Severity</label>
            <select value={severity} onChange={(e) => setSeverity(Number(e.target.value) as any)}>
              <option value={1}>1</option><option value={2}>2</option><option value={3}>3</option>
              <option value={4}>4</option><option value={5}>5</option>
            </select>
          </div>

          <div className="field">
            <label>Visibility</label>
            <select value={visibility} onChange={(e) => setVisibility(e.target.value as any)}>
              <option value="Public">Public</option>
              <option value="Private">Private</option>
            </select>
          </div>
        </div>

        <div className="grid">
          <div className="field"><label>Latitude</label><input value={lat} onChange={(e) => setLat(e.target.value)} /></div>
          <div className="field"><label>Longitude</label><input value={lng} onChange={(e) => setLng(e.target.value)} /></div>
        </div>

        <div className="row" style={{ marginTop: 6 }}>
          <button className="btn" onClick={useMyLocation}>Use my location</button>
          <span className="muted small">Tip: later you can blur location for privacy.</span>
        </div>

        <div className="btnRow">
          <button className="btn" onClick={onClose}>Cancel</button>
          <button
            className="btn primary"
            onClick={() => {
              const p: Post = {
                id: nid("p_"),
                title: title.trim() || "Untitled report",
                body: body.trim() || "(no description)",
                crop,
                category,
                severity,
                visibility,
                lat: Number(lat),
                lng: Number(lng),
                createdAt: Date.now(),
                upvotes: 0,
                comments: [],
              };
              onCreate(p);
              onClose();
            }}
          >
            <PlusIcon /> Publish
          </button>
        </div>
      </div>
    </div>
  );
}