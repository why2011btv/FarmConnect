export type Comment = { id: string; text: string; createdAt: number; userName?: string };

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
  city: string;            // City name (e.g., "Boston", "Miami")
  createdAt: number;
  upvotes: number;        // credit
  comments: Comment[];
  userName: string;
  imageUrl?: string;      // base64 data URL for images
};

export type Message = {
  id: string;
  fromUserName: string;
  toUserName: string;
  text: string;
  createdAt: number;
  read: boolean;
};

export type Conversation = {
  id: string;
  participants: string[];  // [user1, user2] sorted alphabetically
  messages: Message[];
  lastMessageAt: number;
};