import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var viewModel: ChatViewModel
    @EnvironmentObject private var session: SessionStore

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
                        let title = conversation.participantNames.joined(separator: ", ")
                        let otherUserId = conversation.participants.first(where: { $0 != session.currentUser?.id }) ?? conversation.participants.first ?? ""
                        NavigationLink {
                            ChatThreadView(otherUserId: otherUserId, title: title)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(title)
                                    .font(.headline)
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
            .task {
                await viewModel.loadConversations()
            }
        }
    }
}
