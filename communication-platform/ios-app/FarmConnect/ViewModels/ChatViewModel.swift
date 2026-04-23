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
            if isCancellationError(error) { return }
            errorMessage = "Failed to load chats: \(error.localizedDescription)"
        }
    }

    func loadMessages(otherUserId: String) async {
        errorMessage = nil
        do {
            messages = try await APIClient.shared.getMessages(otherUserId: otherUserId)
        } catch {
            if isCancellationError(error) { return }
            errorMessage = "Failed to load messages: \(error.localizedDescription)"
        }
    }

    func loadMessages(conversationId: String) async {
        errorMessage = nil
        do {
            messages = try await APIClient.shared.getMessages(conversationId: conversationId)
        } catch {
            if isCancellationError(error) { return }
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

    /// Tells the server that the user just opened this conversation, so the
    /// unread badge in the list view clears on the next refresh. Failures are
    /// silent — a stale badge is not worth surfacing an error for.
    func markRead(conversationId: String) async {
        do {
            try await APIClient.shared.markConversationRead(conversationId: conversationId)
            if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
                conversations[index].unreadCount = 0
            }
        } catch {
            if isCancellationError(error) { return }
            // Don't surface — stale unread badge beats a scary error toast.
        }
    }

    /// Leaves (or deletes, for direct chats) a conversation. Removes it from
    /// the local list immediately so the UI feels responsive.
    func leaveConversation(id: String) async -> Bool {
        do {
            try await APIClient.shared.leaveConversation(conversationId: id)
            conversations.removeAll { $0.id == id }
            return true
        } catch {
            if isCancellationError(error) { return false }
            errorMessage = "Failed to leave conversation: \(error.localizedDescription)"
            return false
        }
    }
}
