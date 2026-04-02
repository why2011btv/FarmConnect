import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var viewModel: ChatViewModel

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
                        VStack(alignment: .leading, spacing: 6) {
                            Text(conversation.participantNames.joined(separator: ", "))
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
