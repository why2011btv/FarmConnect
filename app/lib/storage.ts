import { Post } from "./types";
const KEY = "farm_alert_posts_v1";

function safeParse(json: string | null): Post[] {
  if (!json) return [];
  try {
    const data = JSON.parse(json);
    return Array.isArray(data) ? data : [];
  } catch {
    return [];
  }
}

export function loadPosts(): Post[] {
  if (typeof window === "undefined") return [];
  const existing = safeParse(localStorage.getItem(KEY));
  if (existing.length) return existing;

  // Seed posts (Miami-ish coordinates by default)
  const seed: Post[] = [
    {
      id: "p1",
      title: "Possible corn rust spotted",
      body: "Leaves show orange pustules. If you grow corn nearby, please scout your field.",
      crop: "Corn",
      category: "Disease",
      severity: 3,
      visibility: "Public",
      lat: 25.7742,
      lng: -80.1936,
      createdAt: Date.now() - 1000 * 60 * 85,
      upvotes: 18,
      comments: [
        { id: "c1", text: "Seeing similar signs ~12km north. Thanks.", createdAt: Date.now() - 1000 * 60 * 50 },
      ],
    },
    {
      id: "p2",
      title: "Fall armyworm pressure increasing",
      body: "Larvae found in whorls. Check early morning; track severity over the week.",
      crop: "Corn",
      category: "Pest",
      severity: 4,
      visibility: "Public",
      lat: 25.7617,
      lng: -80.1918,
      createdAt: Date.now() - 1000 * 60 * 180,
      upvotes: 27,
      comments: [],
    },
    {
      id: "p3",
      title: "Private note: irrigation check",
      body: "North block looks dry. Inspect drip lines tomorrow.",
      crop: "Mixed",
      category: "Note",
      severity: 1,
      visibility: "Private",
      lat: 25.78,
      lng: -80.21,
      createdAt: Date.now() - 1000 * 60 * 30,
      upvotes: 0,
      comments: [],
    },
  ];

  localStorage.setItem(KEY, JSON.stringify(seed));
  return seed;
}

export function savePosts(posts: Post[]) {
  if (typeof window === "undefined") return;
  localStorage.setItem(KEY, JSON.stringify(posts));
}