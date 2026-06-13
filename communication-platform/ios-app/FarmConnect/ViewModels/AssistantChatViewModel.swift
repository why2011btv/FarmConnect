import Foundation

@MainActor
final class AssistantChatViewModel: ObservableObject {
    @Published private(set) var sessions: [AssistantChatSession] = []
    @Published var selectedSessionId: String?
    @Published var isLoading = false
    @Published var isSending = false
    @Published var errorMessage: String?

    var selectedSession: AssistantChatSession? {
        guard let selectedSessionId else { return nil }
        return sessions.first(where: { $0.id == selectedSessionId })
    }

    func loadSessions() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let items = try await APIClient.shared.getAssistantSessions()
            sessions = items
            if let selectedSessionId,
               sessions.contains(where: { $0.id == selectedSessionId }) {
                await loadSessionMessages(sessionId: selectedSessionId)
            } else {
                selectedSessionId = sessions.first?.id
                if let selectedSessionId {
                    await loadSessionMessages(sessionId: selectedSessionId)
                }
            }
            if sessions.isEmpty {
                _ = try await createNewSession()
            }
        } catch {
            if isCancellationError(error) { return }
            errorMessage = friendlyChatErrorMessage(for: error)
        }
    }

    func loadSessionMessages(sessionId: String) async {
        do {
            let session = try await APIClient.shared.getAssistantSession(id: sessionId)
            if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
                sessions[index] = session
            } else {
                sessions.insert(session, at: 0)
            }
        } catch {
            if isCancellationError(error) { return }
            errorMessage = friendlyChatErrorMessage(for: error)
        }
    }

    @discardableResult
    func createNewSession() async throws -> AssistantChatSession {
        if let selectedSessionId,
           let index = sessions.firstIndex(where: { $0.id == selectedSessionId }),
           sessions[index].messages.isEmpty {
            return sessions[index]
        }

        let session = try await APIClient.shared.createAssistantSession()
        sessions.insert(session, at: 0)
        selectedSessionId = session.id
        errorMessage = nil
        return session
    }

    func selectSession(_ id: String) {
        selectedSessionId = id
        Task {
            if let index = sessions.firstIndex(where: { $0.id == id }),
               sessions[index].messages.isEmpty {
                await loadSessionMessages(sessionId: id)
            }
        }
    }

    func deleteSession(_ id: String) async {
        do {
            try await APIClient.shared.deleteAssistantSession(id: id)
            sessions.removeAll { $0.id == id }
            if selectedSessionId == id {
                selectedSessionId = sessions.first?.id
            }
            if sessions.isEmpty {
                _ = try await createNewSession()
            }
        } catch {
            if isCancellationError(error) { return }
            errorMessage = friendlyChatErrorMessage(for: error)
        }
    }

    func sendMessage(text: String, imageData: Data? = nil) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || imageData != nil else { return }

        errorMessage = nil
        isSending = true
        defer { isSending = false }

        var sessionId = selectedSessionId

        do {
            if sessionId == nil {
                let session = try await createNewSession()
                sessionId = session.id
            }
            guard let sessionId,
                  let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }

            let pendingId = "pending-\(UUID().uuidString)"
            sessions[index].messages.append(
                AssistantChatMessage(
                    id: pendingId,
                    role: .user,
                    text: trimmed,
                    createdAt: Date(),
                    localImageData: imageData
                )
            )
            sessions[index].updatedAt = Date()
            if sessions[index].title == "New chat", !trimmed.isEmpty {
                sessions[index].title = deriveTitle(from: trimmed)
            }

            var imageUrls: [String] = []
            if let imageData {
                imageUrls.append(
                    try await APIClient.shared.uploadImage(
                        data: imageData,
                        fileName: "chat-\(UUID().uuidString).jpg",
                        mimeType: "image/jpeg"
                    )
                )
            }

            let response = try await APIClient.shared.sendAssistantChat(
                sessionId: sessionId,
                text: trimmed,
                imageUrls: imageUrls.isEmpty ? nil : imageUrls
            )

            if let session = response.session,
               let index = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[index] = session
            } else if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
                sessions[index].messages.removeAll { $0.id.hasPrefix("pending-") }
                sessions[index].messages.append(response.userMessage)
                sessions[index].messages.append(response.assistantMessage)
                sessions[index].updatedAt = response.assistantMessage.createdAt
            }

            resortSessions()
        } catch {
            if isCancellationError(error) { return }
            if let sessionId,
               let index = sessions.firstIndex(where: { $0.id == sessionId }) {
                sessions[index].messages.removeAll { $0.id.hasPrefix("pending-") }
            }
            if let sessionId {
                await loadSessionMessages(sessionId: sessionId)
            }
            errorMessage = friendlyChatErrorMessage(for: error)
        }
    }

    private func resortSessions() {
        sessions.sort { $0.updatedAt > $1.updatedAt }
    }

    private func deriveTitle(from text: String) -> String {
        let maxLength = 40
        return text.count > maxLength ? String(text.prefix(maxLength)) + "…" : text
    }

    private func friendlyChatErrorMessage(for error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.localizedDescription
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .networkConnectionLost, .notConnectedToInternet:
                return "Connection lost. Check your network and try again."
            case .timedOut:
                return "The request timed out. Please try again."
            default:
                return urlError.localizedDescription
            }
        }
        return error.localizedDescription
    }
}
