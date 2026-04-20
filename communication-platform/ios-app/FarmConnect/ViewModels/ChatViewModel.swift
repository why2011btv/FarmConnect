import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var messages: [Message] = []
    @Published var users: [UserProfile] = []
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

    func loadMessages(conversationId: String) async {
        do {
            messages = try await APIClient.shared.getMessages(conversationId: conversationId)
        } catch {
            errorMessage = "Failed to load messages: \(error.localizedDescription)"
        }
    }

    func sendMessage(toUserId: String? = nil, conversationId: String? = nil, text: String) async -> Bool {
        errorMessage = nil
        do {
            try await APIClient.shared.sendMessage(toUserId: toUserId, conversationId: conversationId, text: text)
            if let conversationId {
                await loadMessages(conversationId: conversationId)
            } else if let toUserId {
                await loadMessages(otherUserId: toUserId)
            }
            await loadConversations()
            return true
        } catch {
            errorMessage = "Failed to send message: \(error.localizedDescription)"
            return false
        }
    }

    func loadUsers() async {
        do {
            users = try await APIClient.shared.listUsers()
        } catch {
            errorMessage = "Failed to load users: \(error.localizedDescription)"
        }
    }

    func createGroup(name: String, memberUserIds: [String]) async {
        do {
            _ = try await APIClient.shared.createGroupConversation(name: name, memberUserIds: memberUserIds)
            await loadConversations()
        } catch {
            errorMessage = "Failed to create group: \(error.localizedDescription)"
        }
    }
}
