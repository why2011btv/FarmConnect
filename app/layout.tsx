import type { Metadata } from "next";
import "./globals.css";
import ServiceWorkerRegister from "./ui/ServiceWorkerRegister";

export const metadata: Metadata = {
  title: "Farm Alert (Demo)",
  description: "Twitter-like feed + map for local farm alerts (PWA demo).",
  manifest: "/manifest.webmanifest",
  themeColor: "#1e7b3a",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <head>
        {/* Leaflet CSS (no API key needed) */}
        <link
          rel="stylesheet"
          href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"
          integrity="sha256-p4NxAoJBhIIN+hmNHrzRCf9tD/miZyoHS5obTRR9BMY="
          crossOrigin=""
        />
      </head>
      <body>
        <ServiceWorkerRegister />
        {children}
      </body>
    </html>
  );
}