import SwiftUI

struct ChatThreadView: View {
    let conversationId: String?
    let otherUserId: String?
    let title: String

    @EnvironmentObject private var chatViewModel: ChatViewModel
    @EnvironmentObject private var session: SessionStore
    @State private var draft = ""

    var body: some View {
        VStack {
            List(chatViewModel.messages) { message in
                HStack {
                    if message.fromUserId == session.currentUser?.id {
                        Spacer()
                    }
                    Text(message.text)
                        .padding(10)
                        .background(
                            (message.fromUserId == session.currentUser?.id ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15)),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                    if message.fromUserId != session.currentUser?.id {
                        Spacer()
                    }
                }
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)

            HStack {
                TextField("Message", text: $draft)
                    .textFieldStyle(.roundedBorder)
                Button("Send") {
                    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    Task {
                        await chatViewModel.sendMessage(toUserId: otherUserId, conversationId: conversationId, text: text)
                        draft = ""
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let conversationId {
                await chatViewModel.loadMessages(conversationId: conversationId)
            } else if let otherUserId {
                await chatViewModel.loadMessages(otherUserId: otherUserId)
            }
        }
    }
}
