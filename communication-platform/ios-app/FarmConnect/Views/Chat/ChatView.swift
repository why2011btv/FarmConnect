import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var viewModel: ChatViewModel
    @EnvironmentObject private var session: SessionStore
    @State private var isCreateGroupOpen = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading chats...")
                } else if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                } else if viewModel.conversations.isEmpty {
                    ContentUnavailableView("No conversations", systemImage: "message")
                } else {
                    List(viewModel.conversations) { conversation in
                        let myName = session.currentUser?.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                        let otherNames = conversation.participantNames
                            .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != myName }
                        let title = conversation.type == "group"
                            ? (conversation.groupName ?? "Group chat")
                            : (otherNames.isEmpty ? "Unknown user" : otherNames.joined(separator: ", "))
                        let otherUserId = conversation.participants.first(where: { $0 != session.currentUser?.id }) ?? conversation.participants.first ?? ""
                        NavigationLink {
                            ChatThreadView(
                                conversationId: conversation.id,
                                otherUserId: conversation.type == "direct" ? otherUserId : nil,
                                title: title
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(title)
                                    .font(.headline)
                                Text(conversation.type == "group" ? "Group" : "Direct")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if let last = conversation.messages.last {
                                    Text(last.text)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
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
        }
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
