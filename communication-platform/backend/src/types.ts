export type Category = "Disease" | "Pest" | "Weather" | "Note" | "Market";

export type TimeFilter = "1h" | "5h" | "1d" | "3d" | "1w" | "3w" | "all";

export type Comment = {
  id: string;
  postId: string;
  text: string;
  userId: string;
  userName: string;
  createdAt: number;
};

export type Post = {
  id: string;
  title: string;
  body: string;
  crop: string;
  category: Category;
  severity: 1 | 2 | 3 | 4 | 5;
  visibility: "Public" | "Private";
  lat: number;
  lng: number;
  city: string;
  createdAt: number;
  upvotes: number;
  comments: Comment[];
  userId: string;
  userName: string;
  imageUrl?: string;
};

export type Message = {
  id: string;
  conversationId: string;
  fromUserId: string;
  fromUserName: string;
  toUserId?: string;
  text: string;
  createdAt: number;
  read: boolean;
};

export type Conversation = {
  id: string;
  type: "direct" | "group";
  groupName?: string;
  participants: string[];
  participantNames: string[];
  messages: Message[];
  lastMessageAt: number;
};

export type User = {
  id: string;
  name: string;
};

export type SensorReading = {
  sensorType: string;
  value: number;
  unit: string;
  createdAt: number;
};

export type SensorDeviceOverview = {
  id: string;
  name: string;
  farmName: string;
  locationLabel: string;
  status: "online" | "offline";
  lastSeenAt: number;
  readings: SensorReading[];
};
