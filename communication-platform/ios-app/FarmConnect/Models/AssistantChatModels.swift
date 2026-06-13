import Foundation

enum AssistantMessageRole: String, Codable {
    case user
    case assistant
}

struct AssistantChatMessage: Identifiable, Codable, Equatable {
    let id: String
    let role: AssistantMessageRole
    var text: String
    var imageUrls: [String]
    let createdAt: Date
    /// Local-only image bytes for optimistic messages before upload completes.
    var localImageData: Data?

    init(
        id: String,
        role: AssistantMessageRole,
        text: String,
        imageUrls: [String] = [],
        createdAt: Date,
        localImageData: Data? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.imageUrls = imageUrls
        self.createdAt = createdAt
        self.localImageData = localImageData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        role = try container.decode(AssistantMessageRole.self, forKey: .role)
        text = try container.decode(String.self, forKey: .content)
        imageUrls = try container.decodeIfPresent([String].self, forKey: .imageUrls) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(text, forKey: .content)
        try container.encode(imageUrls, forKey: .imageUrls)
        try container.encode(createdAt, forKey: .createdAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, content, imageUrls, createdAt
    }
}

struct AssistantChatSession: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var messages: [AssistantChatMessage]
    let createdAt: Date
    var updatedAt: Date
    var preview: String?

    init(
        id: String,
        title: String,
        messages: [AssistantChatMessage] = [],
        createdAt: Date,
        updatedAt: Date,
        preview: String? = nil
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.preview = preview
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        messages = try container.decodeIfPresent([AssistantChatMessage].self, forKey: .messages) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        preview = try container.decodeIfPresent(String.self, forKey: .preview)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, messages, createdAt, updatedAt, preview
    }

    var displayPreview: String {
        if let preview, !preview.isEmpty {
            return preview
        }
        if let last = messages.last(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return last.text
        }
        if messages.contains(where: { !$0.imageUrls.isEmpty }) {
            return "Image"
        }
        return "No messages yet"
    }
}

struct AssistantSessionListResponse: Decodable {
    let items: [AssistantChatSession]
}

struct AssistantSessionResponse: Decodable {
    let item: AssistantChatSession
}

struct AssistantChatSendRequest: Encodable {
    let sessionId: String?
    let text: String
    let imageUrls: [String]?

    enum CodingKeys: String, CodingKey {
        case sessionId, text, imageUrls
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(sessionId, forKey: .sessionId)
        try container.encode(text, forKey: .text)
        if let imageUrls, !imageUrls.isEmpty {
            try container.encode(imageUrls, forKey: .imageUrls)
        }
    }
}

struct AssistantChatSendResponse: Decodable {
    let session: AssistantChatSession?
    let userMessage: AssistantChatMessage
    let assistantMessage: AssistantChatMessage
    let reply: String
}

struct CreateAssistantSessionRequest: Encodable {
    let title: String?
}

struct CreateAssistantSessionResponse: Decodable {
    let item: AssistantChatSession
}
