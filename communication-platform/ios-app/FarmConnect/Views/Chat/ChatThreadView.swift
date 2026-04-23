import SwiftUI

struct ChatThreadView: View {
    let conversationId: String?
    let otherUserId: String?
    let title: String

    @EnvironmentObject private var chatViewModel: ChatViewModel
    @EnvironmentObject private var session: SessionStore
    @State private var draft = ""
    @State private var pollTask: Task<Void, Never>?

    /// How often we refetch messages while this view is on screen. Short
    /// enough to feel live, long enough to not hammer the API.
    private let pollInterval: UInt64 = 5_000_000_000

    var body: some View {
        VStack(spacing: 0) {
            messagesList

            HStack {
                TextField("Message", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                Button("Send") {
                    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    Task {
                        let didSend = await chatViewModel.sendMessage(
                            toUserId: otherUserId,
                            conversationId: conversationId,
                            text: text
                        )
                        if didSend {
                            draft = ""
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()

            if let errorMessage = chatViewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await initialLoad()
        }
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
    }

    @ViewBuilder
    private var messagesList: some View {
        ScrollViewReader { proxy in
            List(chatViewModel.messages) { message in
                messageBubble(message)
                    .id(message.id)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            }
            .listStyle(.plain)
            .refreshable {
                await refreshMessages()
            }
            // Auto-scroll to the newest message whenever the list grows. We
            // key off count rather than identity to also handle messages that
            // arrive via polling.
            .onChange(of: chatViewModel.messages.count) { _, _ in
                scrollToLatest(proxy: proxy)
            }
            .onAppear {
                scrollToLatest(proxy: proxy, animated: false)
            }
        }
    }

    @ViewBuilder
    private func messageBubble(_ message: Message) -> some View {
        let isMine = message.fromUserId == session.currentUser?.id
        HStack(alignment: .bottom, spacing: 8) {
            if isMine { Spacer(minLength: 40) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
                if !isMine {
                    Text(message.fromUserName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(message.text)
                    .padding(10)
                    .background(
                        (isMine ? Color.blue.opacity(0.18) : Color.gray.opacity(0.18)),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                Text(TimeFormatting.listPreview(from: message.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if !isMine { Spacer(minLength: 40) }
        }
    }

    // MARK: - Loading

    private func initialLoad() async {
        await refreshMessages()
        if let conversationId {
            await chatViewModel.markRead(conversationId: conversationId)
        }
    }

    private func refreshMessages() async {
        if let conversationId {
            await chatViewModel.loadMessages(conversationId: conversationId)
        } else if let otherUserId {
            await chatViewModel.loadMessages(otherUserId: otherUserId)
        }
    }

    private func scrollToLatest(proxy: ScrollViewProxy, animated: Bool = true) {
        guard let lastId = chatViewModel.messages.last?.id else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(lastId, anchor: .bottom)
        }
    }

    // MARK: - Polling

    private func startPolling() {
        stopPolling()
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: pollInterval)
                if Task.isCancelled { break }
                await refreshMessages()
                // Keep the read cursor moving while the user keeps the thread open.
                if let conversationId {
                    await chatViewModel.markRead(conversationId: conversationId)
                }
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}
