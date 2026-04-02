import Foundation

enum Category: String, Codable, CaseIterable, Identifiable {
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

struct Comment: Codable, Identifiable {
    let id: String
    let postId: String
    let text: String
    let userId: String
    let userName: String
    let createdAt: Int64
}

struct Post: Codable, Identifiable {
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
    let imageUrl: String?
}

struct Message: Codable, Identifiable {
    let id: String
    let conversationId: String
    let fromUserId: String
    let fromUserName: String
    let toUserId: String
    let text: String
    let createdAt: Int64
    let read: Bool
}

struct Conversation: Codable, Identifiable {
    let id: String
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
