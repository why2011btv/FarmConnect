import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Temporary local identity for scaffold. Replace with authenticated session user.
    var currentUserId: String = "u1"

    func loadConversations() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            conversations = try await APIClient.shared.getConversations(userId: currentUserId)
        } catch {
            errorMessage = "Failed to load chats: \(error.localizedDescription)"
        }
    }
}
