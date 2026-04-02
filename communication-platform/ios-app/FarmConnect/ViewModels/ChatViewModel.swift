import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var messages: [Message] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadConversations() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            conversations = try await APIClient.shared.getConversations()
        } catch {
            errorMessage = "Failed to load chats: \(error.localizedDescription)"
        }
    }

    func loadMessages(otherUserId: String) async {
        do {
            messages = try await APIClient.shared.getMessages(otherUserId: otherUserId)
        } catch {
            errorMessage = "Failed to load messages: \(error.localizedDescription)"
        }
    }

    func sendMessage(toUserId: String, text: String) async {
        do {
            try await APIClient.shared.sendMessage(toUserId: toUserId, text: text)
            await loadMessages(otherUserId: toUserId)
            await loadConversations()
        } catch {
            errorMessage = "Failed to send message: \(error.localizedDescription)"
        }
    }
}
