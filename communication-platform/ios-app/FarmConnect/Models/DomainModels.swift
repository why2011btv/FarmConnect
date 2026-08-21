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
    /// From the list endpoint this contains only the most recent message (or
    /// is empty). Use the dedicated messages endpoint for the full thread.
    let messages: [Message]
    let lastMessage: Message?
    let lastMessageAt: Int64
    /// Number of messages the current user hasn't read yet. Always 0 for
    /// messages the user sent themselves. Declared `var` so the view model
    /// can optimistically clear it on open without a full refresh.
    var unreadCount: Int

    enum CodingKeys: String, CodingKey {
        case id, type, groupName, participants, participantNames, messages
        case lastMessage, lastMessageAt, unreadCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decode(String.self, forKey: .type)
        groupName = try c.decodeIfPresent(String.self, forKey: .groupName)
        participants = try c.decode([String].self, forKey: .participants)
        participantNames = try c.decode([String].self, forKey: .participantNames)
        messages = try c.decodeIfPresent([Message].self, forKey: .messages) ?? []
        lastMessage = try c.decodeIfPresent(Message.self, forKey: .lastMessage)
        lastMessageAt = try c.decode(Int64.self, forKey: .lastMessageAt)
        // Keep backward compat with older responses that didn't send unread counts.
        unreadCount = try c.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(groupName, forKey: .groupName)
        try c.encode(participants, forKey: .participants)
        try c.encode(participantNames, forKey: .participantNames)
        try c.encode(messages, forKey: .messages)
        try c.encodeIfPresent(lastMessage, forKey: .lastMessage)
        try c.encode(lastMessageAt, forKey: .lastMessageAt)
        try c.encode(unreadCount, forKey: .unreadCount)
    }
}

struct PostListResponse: Codable {
    let items: [Post]
    let nextCursor: String?
}

struct PostPage {
    let items: [Post]
    let nextCursor: Int64?
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
    let email: String?
    let emailVerified: Bool?
    let isAdmin: Bool?

    /// Older builds of the API returned only id/name, so the newer fields decode as optional.
    init(id: String, name: String, email: String? = nil, emailVerified: Bool? = nil, isAdmin: Bool? = nil) {
        self.id = id
        self.name = name
        self.email = email
        self.emailVerified = emailVerified
        self.isAdmin = isAdmin
    }
}

// MARK: - Harvest fruit samples

struct FruitSample: Codable, Identifiable {
    let id: String
    let blockLabel: String?
    let sampledOn: String    // "yyyy-MM-dd"
    let brix: Double?
    let titratableAcidity: Double?
    let ph: Double?
    let notes: String?
}

struct FruitSampleList: Codable { let items: [FruitSample] }

// MARK: - Disease risk (validated models)

struct PhenologyContext: Codable {
    let hasBloomDate: Bool
    let weeksSinceBloom: Double?
    let stage: String
    let inCriticalWindow: Bool
    let fruitSusceptibleBlackRot: Bool
    let inPhomopsisWindow: Bool
    let note: String
}

struct DiseaseAction: Codable, Identifiable {
    let category: String   // "scout" | "cultural" | "protect"
    let action: String
    let reason: String
    var id: String { category + action }
}

struct DiseaseRisk: Codable, Identifiable {
    let key: String
    let name: String
    let level: String   // "low" | "moderate" | "high" | "not-applicable"
    let headline: String
    let detail: String
    let actions: [DiseaseAction]?
    var id: String { key }
}

struct DiseaseAssessment: Codable {
    let updatedAt: Double
    let gddBase50FromApr1: Int
    let phenology: PhenologyContext
    let diseases: [DiseaseRisk]
    let disclaimer: String
}

// MARK: - Admin (staff only)

struct AdminFarmSummary: Codable, Identifiable {
    let id: String
    let name: String
    let createdAt: String
    let deviceCount: Int
    let memberCount: Int
    let onlineCount: Int
    let activeCodeCount: Int
    let lastSeenAt: Double?
}

struct AdminFarmListResponse: Codable {
    let items: [AdminFarmSummary]
}

/// A node's ingest key, returned exactly once at provisioning or rotation time.
struct AdminProvisionedNode: Codable, Identifiable {
    let id: String
    let name: String
    let locationLabel: String
    let ingestKey: String
}

struct AdminProvisionResponse: Codable {
    struct FarmRef: Codable { let id: String; let name: String }
    let farm: FarmRef
    let accessCode: String
    let nodes: [AdminProvisionedNode]
}

struct AdminDevice: Codable, Identifiable {
    let id: String
    let name: String
    let locationLabel: String
    let status: String
    let lastSeenAt: Double
    let hasIngestKey: Bool
}

struct AdminMember: Codable, Identifiable {
    let id: String
    let name: String
    let email: String?
    let role: String
    let joinedAt: String
}

struct AdminCode: Codable, Identifiable {
    let id: String
    let label: String?
    let maxUses: Int?
    let useCount: Int
    let createdAt: String
    let expiresAt: String?
    let revokedAt: String?

    var isActive: Bool { revokedAt == nil }
}

struct AdminFarmDetail: Codable {
    struct FarmRef: Codable { let id: String; let name: String; let createdAt: String }
    let farm: FarmRef
    let devices: [AdminDevice]
    let members: [AdminMember]
    let codes: [AdminCode]
}

struct AdminCodeResponse: Codable {
    let code: String
}

struct AdminRotateKeyResponse: Codable {
    let deviceId: String
    let ingestKey: String
}

/// A customer site. Devices belong to a farm; a user sees a farm's sensors only after redeeming
/// the access code that shipped with the hardware.
struct Farm: Codable, Identifiable {
    let id: String
    let name: String
    let role: String
    let joinedAt: String?
    let deviceCount: Int?

    var isOwner: Bool { role == "owner" }
}

struct FarmListResponse: Codable {
    let items: [Farm]
}

struct ClaimedFarm: Codable {
    let id: String
    let name: String
    let role: String
    let alreadyMember: Bool
}

struct ClaimFarmResponse: Codable {
    let farm: ClaimedFarm
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

struct BlockWeatherPoint: Codable {
    let blockId: String
    let latitude: Double
    let longitude: Double
}

struct BlockWeatherBatchRequest: Codable {
    let points: [BlockWeatherPoint]
}

struct BlockWeatherReadingDTO: Codable {
    let blockId: String
    let airTemperatureF: Double
    let relativeHumidityPct: Double
    let leafWetnessHours: Double
    let soilMoisturePct: Double
    let soilTemperatureF: Double
    let rainfallInches24h: Double
    let solarExposureMJ: Double
    let windSpeedMph: Double
    let windDirectionDegrees: Double
    let fetchedAt: Int64

    var canopyReading: VineyardCanopyReading {
        VineyardCanopyReading(
            airTemperatureF: airTemperatureF,
            relativeHumidityPct: relativeHumidityPct,
            leafWetnessHours: leafWetnessHours,
            soilMoisturePct: soilMoisturePct,
            soilTemperatureF: soilTemperatureF,
            rainfallInches24h: rainfallInches24h,
            solarExposureMJ: solarExposureMJ,
            windSpeedMph: windSpeedMph,
            windDirectionDegrees: windDirectionDegrees
        )
    }
}

struct BlockWeatherBatchResponse: Codable {
    let items: [BlockWeatherReadingDTO]
}
