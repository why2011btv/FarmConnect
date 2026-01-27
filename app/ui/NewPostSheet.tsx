"use client";
import { useState, useRef } from "react";
import { Post } from "../lib/types";
import { PlusIcon } from "./Icons";
import { getUserName } from "../lib/storage";

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
  // Get city from coordinates (simplified - in production, use reverse geocoding API)
  const getCityFromCoords = (lat: number, lng: number): string => {
    // Approximate city detection based on coordinates
    if (lat >= 44 && lat <= 45 && lng >= -73 && lng <= -72) return "Montpelier";
    if (lat >= 42 && lat <= 43 && lng >= -71.5 && lng <= -70.5) return "Boston";
    if (lat >= 25 && lat <= 26 && lng >= -80.5 && lng <= -80) return "Miami";
    if (lat >= 40 && lat <= 41 && lng >= -74.5 && lng <= -73.5) return "New York";
    if (lat >= 33 && lat <= 34 && lng >= -118.5 && lng <= -118) return "Los Angeles";
    if (lat >= 41 && lat <= 42 && lng >= -88 && lng <= -87) return "Chicago";
    return "Miami"; // Default
  };

  // Get coordinates from city name
  const getCoordsFromCity = (cityName: string): { lat: number; lng: number } => {
    const cities: Record<string, { lat: number; lng: number }> = {
      "Montpelier": { lat: 44.2601, lng: -72.5754 },
      "Boston": { lat: 42.3601, lng: -71.0589 },
      "Miami": { lat: 25.7742, lng: -80.1936 },
      "New York": { lat: 40.7128, lng: -74.0060 },
      "Los Angeles": { lat: 34.0522, lng: -118.2437 },
      "Chicago": { lat: 41.8781, lng: -87.6298 },
    };
    return cities[cityName] || cities["Miami"];
  };

  const [city, setCity] = useState(getCityFromCoords(defaultLat, defaultLng));
  const [imageUrl, setImageUrl] = useState<string | undefined>();
  const fileInputRef = useRef<HTMLInputElement>(null);

  const useMyLocation = () => {
    if (!navigator.geolocation) return;
    navigator.geolocation.getCurrentPosition((pos) => {
      const detectedCity = getCityFromCoords(pos.coords.latitude, pos.coords.longitude);
      setCity(detectedCity);
    });
  };

  const handleImageUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    if (file.size > 5 * 1024 * 1024) {
      alert("Image too large. Please use an image under 5MB.");
      return;
    }
    const reader = new FileReader();
    reader.onload = (event) => {
      setImageUrl(event.target?.result as string);
    };
    reader.readAsDataURL(file);
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

        <div className="field">
          <label>Image (optional)</label>
          <input
            type="file"
            ref={fileInputRef}
            accept="image/*"
            onChange={handleImageUpload}
            style={{ display: "none" }}
          />
          <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
            <button 
              className="btn" 
              onClick={() => fileInputRef.current?.click()}
              type="button"
            >
              {imageUrl ? "Change Image" : "Upload Image"}
            </button>
            {imageUrl && (
              <>
                <img 
                  src={imageUrl} 
                  alt="Preview" 
                  style={{ 
                    maxHeight: 100, 
                    maxWidth: 150, 
                    borderRadius: 8, 
                    objectFit: "cover",
                    border: "1px solid var(--border)"
                  }} 
                />
                <button 
                  className="btn" 
                  onClick={() => {
                    setImageUrl(undefined);
                    if (fileInputRef.current) fileInputRef.current.value = "";
                  }}
                  type="button"
                >
                  Remove
                </button>
              </>
            )}
          </div>
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
              <option value="Market">Market</option>
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

        <div className="field">
          <label>Location</label>
          <select value={city} onChange={(e) => setCity(e.target.value)}>
            <option>Montpelier</option>
            <option>Boston</option>
            <option>Miami</option>
            <option>New York</option>
            <option>Los Angeles</option>
            <option>Chicago</option>
          </select>
          <div className="row" style={{ marginTop: 8 }}>
            <button className="btn" onClick={useMyLocation} type="button">Detect from my location</button>
          </div>
        </div>

        <div className="btnRow">
          <button className="btn" onClick={onClose}>Cancel</button>
          <button
            className="btn primary"
            onClick={() => {
              const coords = getCoordsFromCity(city);
              const p: Post = {
                id: nid("p_"),
                title: title.trim() || "Untitled report",
                body: body.trim() || "(no description)",
                crop,
                category,
                severity,
                visibility,
                lat: coords.lat,
                lng: coords.lng,
                city: city,
                createdAt: Date.now(),
                upvotes: 0,
                comments: [],
                userName: getUserName(),
                imageUrl,
              };
              onCreate(p);
              onClose();
              setImageUrl(undefined);
              if (fileInputRef.current) fileInputRef.current.value = "";
            }}
          >
            <PlusIcon /> Publish
          </button>
        </div>
      </div>
    </div>
  );
}