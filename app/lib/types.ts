export type Comment = { id: string; text: string; createdAt: number };

export type Post = {
  id: string;
  title: string;
  body: string;
  crop: string;
  category: "Disease" | "Pest" | "Weather" | "Note";
  severity: 1 | 2 | 3 | 4 | 5;
  visibility: "Public" | "Private";
  lat: number;
  lng: number;
  createdAt: number;
  upvotes: number;        // credit
  comments: Comment[];
};