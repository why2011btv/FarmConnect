import Foundation

enum Category: String, Codable, CaseIterable, Identifiable, Hashable {
    case disease = "Disease"
    case pest = "Pest"
    case weather = "Weather"
    case note = "Note"
    case market = "Market"

    var id: String { rawValue }
}

enum TimeFilter: String, Codable, CaseIterable, Identifiable {
    case oneHour = "1h"
    case fiveHours = "5h"
    case oneDay = "1d"
    case threeDays = "3d"
    case oneWeek = "1w"
    case threeWeeks = "3w"
    case all = "all"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneHour: return "Last 1 hour"
        case .fiveHours: return "Last 5 hours"
        case .oneDay: return "Last 1 day"
        case .threeDays: return "Last 3 days"
        case .oneWeek: return "Last 1 week"
        case .threeWeeks: return "Last 3 weeks"
        case .all: return "All time"
        }
    }
}

struct Comment: Codable, Identifiable, Hashable {
    let id: String
    let postId: String
    let text: String
    let userId: String
    let userName: String
    let createdAt: Int64
}

struct Post: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let body: String
    let crop: String
    let category: Category
    let severity: Int
    let visibility: String
    let lat: Double
    let lng: Double
    let city: String
    let createdAt: Int64
    let upvotes: Int
    let comments: [Comment]
    let userId: String
    let userName: String
    let imageUrls: [String]

    var imageUrl: String? { imageUrls.first }

    private enum CodingKeys: String, CodingKey {
        case id, title, body, crop, category, severity, visibility, lat, lng, city, createdAt, upvotes, comments, userId, userName, imageUrl, imageUrls
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        crop = try container.decode(String.self, forKey: .crop)
        category = try container.decode(Category.self, forKey: .category)
        severity = try container.decode(Int.self, forKey: .severity)
        visibility = try container.decode(String.self, forKey: .visibility)
        lat = try container.decode(Double.self, forKey: .lat)
        lng = try container.decode(Double.self, forKey: .lng)
        city = try container.decode(String.self, forKey: .city)
        createdAt = try container.decode(Int64.self, forKey: .createdAt)
        upvotes = try container.decode(Int.self, forKey: .upvotes)
        comments = try container.decode([Comment].self, forKey: .comments)
        userId = try container.decode(String.self, forKey: .userId)
        userName = try container.decode(String.self, forKey: .userName)

        let multi = try container.decodeIfPresent([String].self, forKey: .imageUrls) ?? []
        let normalizedMulti = multi
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !normalizedMulti.isEmpty {
            imageUrls = normalizedMulti
        } else if let single = try container.decodeIfPresent(String.self, forKey: .imageUrl)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !single.isEmpty {
            imageUrls = [single]
        } else {
            imageUrls = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(body, forKey: .body)
        try container.encode(crop, forKey: .crop)
        try container.encode(category, forKey: .category)
        try container.encode(severity, forKey: .severity)
        try container.encode(visibility, forKey: .visibility)
        try container.encode(lat, forKey: .lat)
        try container.encode(lng, forKey: .lng)
        try container.encode(city, forKey: .city)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(upvotes, forKey: .upvotes)
        try container.encode(comments, forKey: .comments)
        try container.encode(userId, forKey: .userId)
        try container.encode(userName, forKey: .userName)
        try container.encode(imageUrls, forKey: .imageUrls)
        try container.encodeIfPresent(imageUrl, forKey: .imageUrl)
    }
}

struct Message: Codable, Identifiable {
    let id: String
    let conversationId: String
    let fromUserId: String
    let fromUserName: String
    let toUserId: String?
    let text: String
    let createdAt: Int64
    let read: Bool
}

struct Conversation: Codable, Identifiable {
    let id: String
    let type: String
    let groupName: String?
    let participants: [String]
    let participantNames: [String]
    let messages: [Message]
    let lastMessageAt: Int64
}

struct PostListResponse: Codable {
    let items: [Post]
}

struct ConversationListResponse: Codable {
    let items: [Conversation]
}

struct MessageListResponse: Codable {
    let items: [Message]
}

struct UserProfile: Codable, Identifiable {
    let id: String
    let name: String
}

struct AuthResponse: Codable {
    let token: String
    let user: UserProfile
    let expiresAt: String
}

struct AuthMeResponse: Codable {
    let user: UserProfile
}

struct UserListResponse: Codable {
    let items: [UserProfile]
}

struct SensorReading: Codable {
    let sensorType: String
    let value: Double
    let unit: String
    let createdAt: Int64
}

struct SensorDeviceOverview: Codable, Identifiable {
    let id: String
    let name: String
    let farmName: String
    let locationLabel: String
    let status: String
    let lastSeenAt: Int64
    let readings: [SensorReading]
}

struct SensorInsight: Codable, Identifiable {
    let id: String
    let title: String
    let message: String
    let severity: String
    let deviceId: String?
    let createdAt: Int64
}

struct SensorOverviewResponse: Codable {
    let items: [SensorDeviceOverview]
    let insights: [SensorInsight]
}

struct NotificationPreferences: Codable {
    var enabled: Bool
    var radiusMiles: Int
    var categories: [Category]
    var quietHoursEnabled: Bool
    var quietStart: String
    var quietEnd: String
    var timezoneOffsetMinutes: Int
    var locationLat: Double?
    var locationLng: Double?
}

struct NotificationPreferencesResponse: Codable {
    let item: NotificationPreferences
}
