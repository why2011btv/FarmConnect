import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var viewModel: ChatViewModel
    @EnvironmentObject private var session: SessionStore
    @State private var isCreateGroupOpen = false
    @State private var pendingLeave: Conversation?

    var body: some View {
        NavigationStack {
            // Always render the List so `.refreshable` doesn't get cancelled
            // by SwiftUI unmounting it when `isLoading` flips. Loading and
            // empty states are overlays instead of replacements.
            ZStack {
                List {
                    ForEach(viewModel.conversations) { conversation in
                        conversationRow(conversation)
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await viewModel.loadConversations()
                }

                if viewModel.isLoading && viewModel.conversations.isEmpty {
                    ProgressView("Loading chats...")
                } else if !viewModel.isLoading && viewModel.conversations.isEmpty {
                    ContentUnavailableView(
                        "No conversations yet",
                        systemImage: "message",
                        description: Text("Tap an author in the feed to start a direct chat, or create a group.")
                    )
                }

                if let error = viewModel.errorMessage, !viewModel.conversations.isEmpty {
                    VStack {
                        Spacer()
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                    }
                }
            }
            .navigationTitle("Chat")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AccountMenuButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCreateGroupOpen = true
                    } label: {
                        Image(systemName: "person.3.fill")
                    }
                }
            }
            .task {
                await viewModel.loadConversations()
            }
            .sheet(isPresented: $isCreateGroupOpen) {
                CreateGroupView(isOpen: $isCreateGroupOpen)
            }
            .alert(
                leaveAlertTitle,
                isPresented: Binding(
                    get: { pendingLeave != nil },
                    set: { if !$0 { pendingLeave = nil } }
                ),
                presenting: pendingLeave
            ) { conversation in
                Button("Cancel", role: .cancel) { pendingLeave = nil }
                Button(leaveDestructiveLabel(for: conversation), role: .destructive) {
                    let id = conversation.id
                    pendingLeave = nil
                    Task { _ = await viewModel.leaveConversation(id: id) }
                }
            } message: { conversation in
                Text(leaveAlertMessage(for: conversation))
            }
        }
    }

    @ViewBuilder
    private func conversationRow(_ conversation: Conversation) -> some View {
        let myName = session.currentUser?.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let otherNames = conversation.participantNames
            .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != myName }
        let title = conversation.type == "group"
            ? (conversation.groupName ?? "Group chat")
            : (otherNames.isEmpty ? "Unknown user" : otherNames.joined(separator: ", "))
        let otherUserId = conversation.participants.first(where: { $0 != session.currentUser?.id })
            ?? conversation.participants.first ?? ""
        let preview = conversation.lastMessage ?? conversation.messages.last

        NavigationLink {
            ChatThreadView(
                conversationId: conversation.id,
                otherUserId: conversation.type == "direct" ? otherUserId : nil,
                title: title
            )
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title)
                            .font(.headline)
                            .lineLimit(1)
                        if conversation.type == "group" {
                            Text("Group")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1), in: Capsule())
                        }
                        Spacer()
                        Text(TimeFormatting.listPreview(from: conversation.lastMessageAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let preview {
                        let prefix = conversation.type == "group" && preview.fromUserId != session.currentUser?.id
                            ? "\(preview.fromUserName): "
                            : (preview.fromUserId == session.currentUser?.id ? "You: " : "")
                        Text(prefix + preview.text)
                            .font(.subheadline)
                            .foregroundStyle(conversation.unreadCount > 0 ? .primary : .secondary)
                            .fontWeight(conversation.unreadCount > 0 ? .semibold : .regular)
                            .lineLimit(1)
                    } else {
                        Text("No messages yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                }
                if conversation.unreadCount > 0 {
                    Text("\(min(conversation.unreadCount, 99))")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue, in: Capsule())
                        .accessibilityLabel("\(conversation.unreadCount) unread")
                }
            }
            .padding(.vertical, 4)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingLeave = conversation
            } label: {
                Label(conversation.type == "group" ? "Leave" : "Delete", systemImage: "trash")
            }
        }
    }

    private var leaveAlertTitle: String { "Remove conversation?" }

    private func leaveDestructiveLabel(for conversation: Conversation) -> String {
        conversation.type == "group" ? "Leave" : "Delete"
    }

    private func leaveAlertMessage(for conversation: Conversation) -> String {
        conversation.type == "group"
            ? "You'll stop receiving messages from this group."
            : "This conversation will be deleted for both you and the other person."
    }
}

private struct CreateGroupView: View {
    @EnvironmentObject private var chatViewModel: ChatViewModel
    @Binding var isOpen: Bool
    @State private var groupName = ""
    @State private var selectedUserIds = Set<String>()

    var body: some View {
        NavigationStack {
            List {
                Section("Group name") {
                    TextField("e.g. Vineyard team", text: $groupName)
                }
                Section("Members") {
                    ForEach(chatViewModel.users) { user in
                        MultipleSelectionRow(
                            title: user.name,
                            isSelected: selectedUserIds.contains(user.id)
                        ) {
                            if selectedUserIds.contains(user.id) {
                                selectedUserIds.remove(user.id)
                            } else {
                                selectedUserIds.insert(user.id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Group")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { isOpen = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        Task {
                            await chatViewModel.createGroup(name: groupName, memberUserIds: Array(selectedUserIds))
                            isOpen = false
                        }
                    }
                    .disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedUserIds.isEmpty)
                }
            }
            .task {
                await chatViewModel.loadUsers()
            }
        }
    }
}

private struct MultipleSelectionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
        }
        .foregroundStyle(.primary)
    }
}
