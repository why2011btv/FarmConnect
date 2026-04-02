import SwiftUI

struct ChatThreadView: View {
    let otherUserId: String
    let title: String

    @EnvironmentObject private var chatViewModel: ChatViewModel
    @State private var draft = ""

    var body: some View {
        VStack {
            List(chatViewModel.messages) { message in
                HStack {
                    if message.toUserId == otherUserId {
                        Spacer()
                    }
                    Text(message.text)
                        .padding(10)
                        .background(
                            (message.toUserId == otherUserId ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15)),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                    if message.toUserId != otherUserId {
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
                        await chatViewModel.sendMessage(toUserId: otherUserId, text: text)
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
            await chatViewModel.loadMessages(otherUserId: otherUserId)
        }
    }
}
