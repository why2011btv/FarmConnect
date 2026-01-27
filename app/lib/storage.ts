import { Post, Conversation } from "./types";
const KEY = "farm_alert_posts_v1";
const KEY_USER = "farm_alert_user_name";
const KEY_CONVERSATIONS = "farm_alert_conversations_v1";

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
  if (existing.length) {
    // Get city from coordinates helper
    const getCityFromCoords = (lat: number, lng: number): string => {
      if (lat >= 44 && lat <= 45 && lng >= -73 && lng <= -72) return "Montpelier";
      if (lat >= 42 && lat <= 43 && lng >= -71.5 && lng <= -70.5) return "Boston";
      if (lat >= 25 && lat <= 26 && lng >= -80.5 && lng <= -80) return "Miami";
      if (lat >= 40 && lat <= 41 && lng >= -74.5 && lng <= -73.5) return "New York";
      if (lat >= 33 && lat <= 34 && lng >= -118.5 && lng <= -118) return "Los Angeles";
      if (lat >= 41 && lat <= 42 && lng >= -88 && lng <= -87) return "Chicago";
      return "Miami";
    };

    // Migrate old posts to include userName and city if missing
    const migrated = existing.map((p: any) => {
      // Update posts that were "Current User" or "Anonymous" to "Alex Wang"
      let userName = p.userName || "Anonymous";
      if (userName === "Current User" || userName === "Anonymous") {
        userName = "Alex Wang";
      }
      // Update "Alex Thompson" or "Charles Thompson" to "Charles Zhang" and move to Boston
      if (userName === "Alex Thompson" || userName === "Charles Thompson") {
        userName = "Charles Zhang";
        if (p.id === "p4" || p.imageUrl === "/cornpest_2_0.webp") {
          p.lat = 42.3601;
          p.lng = -71.0589;
        }
      }
      // Add city if missing
      const city = p.city || getCityFromCoords(p.lat || 25.7742, p.lng || -80.1936);
      return {
        ...p,
        userName,
        city,
        imageUrl: p.imageUrl || undefined,
        comments: (p.comments || []).map((c: any) => ({
          ...c,
          userName: c.userName || undefined,
        })),
      };
    });
    
    // Update p1 to belong to "Paris F" and be in Montpelier if it exists
    const p1Index = migrated.findIndex((p: any) => p.id === "p1");
    if (p1Index !== -1) {
      const needsUpdate = migrated[p1Index].userName === "Alex Wang" || 
                         migrated[p1Index].city !== "Montpelier" ||
                         migrated[p1Index].userName === "Paris F" && migrated[p1Index].city !== "Montpelier";
      if (needsUpdate) {
        migrated[p1Index] = {
          ...migrated[p1Index],
          userName: "Paris F",
          city: "Montpelier",
          lat: 44.2601,
          lng: -72.5754,
        };
        localStorage.setItem(KEY, JSON.stringify(migrated));
      }
    }

    // Ensure the new post with image exists (if not already present)
    const hasNewPost = migrated.some((p: any) => p.id === "p4");
    if (!hasNewPost) {
      const newPost: Post = {
        id: "p4",
        title: "Corn pest infestation detected",
        body: "Found significant pest damage in the eastern field. Multiple larvae visible on corn leaves. Immediate treatment recommended.",
        crop: "Corn",
        category: "Pest",
        severity: 5,
        visibility: "Public",
        lat: 42.3601,
        lng: -71.0589,
        city: "Boston",
        createdAt: Date.now() - 1000 * 60 * 120,
        upvotes: 15,
        comments: [],
        userName: "Charles Zhang",
        imageUrl: "/cornpest_2_0.webp",
      };
      migrated.push(newPost);
      localStorage.setItem(KEY, JSON.stringify(migrated));
    } else {
      // Update existing p4 post to have correct name and location
      const p4Index = migrated.findIndex((p: any) => p.id === "p4");
      if (p4Index !== -1) {
        migrated[p4Index] = {
          ...migrated[p4Index],
          userName: "Charles Zhang",
          lat: 42.3601,
          lng: -71.0589,
          city: "Boston",
        };
        localStorage.setItem(KEY, JSON.stringify(migrated));
      }
    }
    
    return migrated;
  }

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
      lat: 44.2601,
      lng: -72.5754,
      city: "Montpelier",
      createdAt: Date.now() - 1000 * 60 * 85,
      upvotes: 18,
      comments: [
        { id: "c1", text: "Seeing similar signs ~12km north. Thanks.", createdAt: Date.now() - 1000 * 60 * 50, userName: "Farmer John" },
      ],
      userName: "Paris F",
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
      city: "Miami",
      createdAt: Date.now() - 1000 * 60 * 180,
      upvotes: 27,
      comments: [],
      userName: "Alex Wang",
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
      city: "Miami",
      createdAt: Date.now() - 1000 * 60 * 30,
      upvotes: 0,
      comments: [],
      userName: "Alex Wang",
    },
    {
      id: "p4",
      title: "Corn pest infestation detected",
      body: "Found significant pest damage in the eastern field. Multiple larvae visible on corn leaves. Immediate treatment recommended.",
      crop: "Corn",
      category: "Pest",
      severity: 5,
      visibility: "Public",
      lat: 42.3601,
      lng: -71.0589,
      city: "Boston",
      createdAt: Date.now() - 1000 * 60 * 120,
      upvotes: 15,
      comments: [],
      userName: "Charles Zhang",
      imageUrl: "/cornpest_2_0.webp",
    },
    {
      id: "p5",
      title: "Fresh blueberries at local market",
      body: "Selling freshly picked organic blueberries at the Saturday farmers market. Limited supply this week.",
      crop: "Blueberries",
      category: "Market",
      severity: 1,
      visibility: "Public",
      lat: 42.3601,
      lng: -71.0589,
      city: "Boston",
      createdAt: Date.now() - 1000 * 60 * 45,
      upvotes: 7,
      comments: [],
      userName: "Alex Wang",
      imageUrl: "/blueberries.jpg",
    },
  ];

  localStorage.setItem(KEY, JSON.stringify(seed));
  return seed;
}

export function savePosts(posts: Post[]) {
  if (typeof window === "undefined") return;
  localStorage.setItem(KEY, JSON.stringify(posts));
}

export function getUserName(): string {
  if (typeof window === "undefined") return "Alex Wang";
  return localStorage.getItem(KEY_USER) || "Alex Wang";
}

export function setUserName(name: string) {
  if (typeof window === "undefined") return;
  localStorage.setItem(KEY_USER, name.trim() || "Anonymous");
}

export function loadConversations(): Conversation[] {
  if (typeof window === "undefined") return [];
  const json = localStorage.getItem(KEY_CONVERSATIONS);
  if (!json) return [];
  try {
    const data = JSON.parse(json);
    return Array.isArray(data) ? data : [];
  } catch {
    return [];
  }
}

export function saveConversations(conversations: Conversation[]) {
  if (typeof window === "undefined") return;
  localStorage.setItem(KEY_CONVERSATIONS, JSON.stringify(conversations));
}