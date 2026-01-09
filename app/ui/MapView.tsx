"use client";
import { useEffect, useMemo, useRef } from "react";
import { Post } from "../lib/types";

declare global { interface Window { L: any } }

export default function MapView({
  posts, selectedId, onSelect, center,
}: {
  posts: Post[];
  selectedId: string | null;
  onSelect: (id: string) => void;
  center: { lat: number; lng: number };
}) {
  const mapDivRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<any>(null);
  const markersRef = useRef<Map<string, any>>(new Map());

  const publicPosts = useMemo(() => posts.filter((p) => p.visibility === "Public"), [posts]);

  useEffect(() => {
    if (!mapDivRef.current) return;

    const ensureLeaflet = async () => {
      if (window.L) return window.L;
      await new Promise<void>((resolve, reject) => {
        const s = document.createElement("script");
        s.src = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.js";
        s.integrity = "sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo=";
        s.crossOrigin = "";
        s.onload = () => resolve();
        s.onerror = () => reject(new Error("Failed to load Leaflet"));
        document.head.appendChild(s);
      });
      return window.L;
    };

    (async () => {
      const L = await ensureLeaflet();

      if (!mapRef.current) {
        const m = L.map(mapDivRef.current).setView([center.lat, center.lng], 11);
        L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
          attribution: "&copy; OpenStreetMap contributors",
          maxZoom: 19,
        }).addTo(m);
        mapRef.current = m;
      }

      markersRef.current.forEach((mk) => mk.remove());
      markersRef.current.clear();

      publicPosts.forEach((p) => {
        const mk = window.L.marker([p.lat, p.lng], { title: p.title });
        mk.addTo(mapRef.current);
        
        // Unified handler for both mouse and touch events
        const handleSelect = (e: any) => {
          if (e && e.originalEvent) {
            // Prevent map from panning when clicking/touching marker
            e.originalEvent.stopPropagation();
            // For touch events, prevent default to avoid double-tap zoom
            if (e.originalEvent.type === 'touchend') {
              e.originalEvent.preventDefault();
            }
          }
          // Directly call onSelect
          onSelect(p.id);
        };
        
        // Register multiple event types for maximum compatibility
        mk.on("click", handleSelect);
        mk.on("touchend", handleSelect);
        
        // Prevent map panning when touching the marker
        mk.on("touchstart", (e: any) => {
          if (e.originalEvent) {
            e.originalEvent.stopPropagation();
          }
        });
        
        markersRef.current.set(p.id, mk);
      });
    })();
  }, [publicPosts, onSelect, center.lat, center.lng]);

  useEffect(() => {
    if (!selectedId) return;
    const mk = markersRef.current.get(selectedId);
    if (!mk || !mapRef.current) return;
    mapRef.current.setView(mk.getLatLng(), Math.max(mapRef.current.getZoom(), 12), { animate: true });
  }, [selectedId]);

  return <div className="mapWrap" ref={mapDivRef} />;
}