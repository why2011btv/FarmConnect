import Foundation

@MainActor
final class AssistantChatViewModel: ObservableObject {
    @Published private(set) var sessions: [AssistantChatSession] = []
    @Published var selectedSessionId: UUID?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let storageKey = "assistant_chat_sessions_v1"

    init() {
        loadSessions()
        if sessions.isEmpty {
            createNewSession()
        } else if selectedSessionId == nil {
            selectedSessionId = sessions.first?.id
        }
    }

    var selectedSession: AssistantChatSession? {
        guard let selectedSessionId else { return nil }
        return sessions.first(where: { $0.id == selectedSessionId })
    }

    func createNewSession() {
        let session = AssistantChatSession()
        sessions.insert(session, at: 0)
        selectedSessionId = session.id
        persistSessions()
    }

    func selectSession(_ id: UUID) {
        selectedSessionId = id
    }

    func deleteSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        if selectedSessionId == id {
            selectedSessionId = sessions.first?.id
        }
        if sessions.isEmpty {
            createNewSession()
        }
        persistSessions()
    }

    func sendMessage(text: String, imageDataUrls: [String] = []) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !imageDataUrls.isEmpty else { return }
        guard let sessionId = selectedSessionId,
              let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }

        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        let userMessage = AssistantChatMessage(
            role: .user,
            text: trimmed,
            imageDataUrls: imageDataUrls
        )
        sessions[index].messages.append(userMessage)
        sessions[index].updatedAt = Date()
        updateTitleIfNeeded(at: index, from: trimmed)
        persistSessions()

        do {
            let history = sessions[index].messages.map { message in
                AssistantChatRequest.Message(
                    role: message.role.rawValue,
                    content: message.text,
                    imageDataUrls: message.imageDataUrls.isEmpty ? nil : message.imageDataUrls
                )
            }
            let reply = try await APIClient.shared.sendAssistantChat(messages: history)
            let assistantMessage = AssistantChatMessage(role: .assistant, text: reply)
            sessions[index].messages.append(assistantMessage)
            sessions[index].updatedAt = Date()
            persistSessions()
        } catch {
            if isCancellationError(error) { return }
            errorMessage = error.localizedDescription
        }
    }

    private func updateTitleIfNeeded(at index: Int, from text: String) {
        guard sessions[index].title == "New chat" else { return }
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let maxLength = 40
        sessions[index].title = title.count > maxLength
            ? String(title.prefix(maxLength)) + "…"
            : title
    }

    private func loadSessions() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([AssistantChatSession].self, from: data) else { return }
        sessions = decoded.sorted { $0.updatedAt > $1.updatedAt }
        selectedSessionId = sessions.first?.id
    }

    private func persistSessions() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(sessions) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
