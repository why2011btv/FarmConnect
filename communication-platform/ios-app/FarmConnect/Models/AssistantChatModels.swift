import Foundation

enum AssistantMessageRole: String, Codable {
    case user
    case assistant
}

struct AssistantChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: AssistantMessageRole
    var text: String
    var imageDataUrls: [String]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        role: AssistantMessageRole,
        text: String,
        imageDataUrls: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.imageDataUrls = imageDataUrls
        self.createdAt = createdAt
    }
}

struct AssistantChatSession: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var messages: [AssistantChatMessage]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "New chat",
        messages: [AssistantChatMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var preview: String {
        if let last = messages.last(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return last.text
        }
        if messages.contains(where: { !$0.imageDataUrls.isEmpty }) {
            return "Image"
        }
        return "No messages yet"
    }
}

struct AssistantChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
        let imageDataUrls: [String]?
    }

    let messages: [Message]
}

struct AssistantChatResponse: Decodable {
    let reply: String
}
