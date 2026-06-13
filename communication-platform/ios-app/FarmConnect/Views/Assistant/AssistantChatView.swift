import PhotosUI
import SwiftUI
import UIKit

struct AssistantChatView: View {
    @EnvironmentObject private var viewModel: AssistantChatViewModel
    @State private var draft = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var pendingImageData: Data?
    @State private var isSessionListPresented = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let session = viewModel.selectedSession, !session.messages.isEmpty {
                    messagesList(session: session)
                } else {
                    emptyState
                }

                if let pendingImageData {
                    pendingImagePreview(pendingImageData)
                }

                inputBar
            }
            .navigationTitle(viewModel.selectedSession?.title ?? "Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isSessionListPresented = true
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    AccountMenuButton()
                }
            }
            .sheet(isPresented: $isSessionListPresented) {
                sessionListSheet
            }
            .onChange(of: selectedPhoto) { _, item in
                Task { await loadSelectedPhoto(item) }
            }
            .task {
                await viewModel.loadSessions()
            }
            .overlay {
                if viewModel.isLoading && viewModel.sessions.isEmpty {
                    ProgressView("Loading chats…")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "leaf.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green.opacity(0.7))
            Text("The answer is in the basket!")
                .font(.title2.bold())
            Text("Ask about crops, pests, diseases, or upload a photo for help.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func messagesList(session: AssistantChatSession) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(session.messages) { message in
                        messageRow(message)
                            .id(message.id)
                    }
                    if viewModel.isSending {
                        typingIndicator
                            .id("typing")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .onChange(of: session.messages.count) { _, _ in
                scrollToBottom(proxy: proxy, session: session)
            }
            .onChange(of: viewModel.isSending) { _, loading in
                if loading {
                    withAnimation {
                        proxy.scrollTo("typing", anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ message: AssistantChatMessage) -> some View {
        let isUser = message.role == .user
        HStack(alignment: .top, spacing: 10) {
            if isUser { Spacer(minLength: 48) }

            if !isUser {
                Image(systemName: "leaf.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                    .frame(width: 28, height: 28)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                if !message.imageUrls.isEmpty {
                    ForEach(Array(message.imageUrls.enumerated()), id: \.offset) { _, imageUrl in
                        if let url = URL(string: imageUrl) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                case .failure:
                                    Image(systemName: "photo")
                                        .foregroundStyle(.secondary)
                                default:
                                    ProgressView()
                                }
                            }
                            .frame(maxWidth: 220, maxHeight: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.body)
                        .foregroundStyle(isUser ? .white : .primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            isUser ? Color.accentColor : Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 18)
                        )
                }
            }

            if !isUser { Spacer(minLength: 48) }
        }
    }

    private var typingIndicator: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "leaf.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Color.secondary.opacity(0.5))
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
            Spacer()
        }
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider()
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            HStack(alignment: .bottom, spacing: 10) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }
                .disabled(viewModel.isSending)

                TextField("Message", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, canSend ? Color.accentColor : Color.gray.opacity(0.4))
                }
                .disabled(!canSend || viewModel.isSending)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
        }
    }

    @ViewBuilder
    private func pendingImagePreview(_ data: Data) -> some View {
        HStack {
            if let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Text("Image attached")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Remove") {
                pendingImageData = nil
                selectedPhoto = nil
            }
            .font(.caption)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    private var sessionListSheet: some View {
        NavigationStack {
            List {
                ForEach(viewModel.sessions) { session in
                    Button {
                        viewModel.selectSession(session.id)
                        isSessionListPresented = false
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(session.displayPreview)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(TimeFormatting.listPreview(from: session.updatedAt))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let id = viewModel.sessions[index].id
                        Task { await viewModel.deleteSession(id) }
                    }
                }
            }
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { isSessionListPresented = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New chat") {
                        Task {
                            try? await viewModel.createNewSession()
                            isSessionListPresented = false
                        }
                    }
                }
            }
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pendingImageData != nil
    }

    private func sendMessage() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageData = pendingImageData
        guard !text.isEmpty || imageData != nil else { return }

        draft = ""
        pendingImageData = nil
        selectedPhoto = nil

        Task {
            await viewModel.sendMessage(text: text, imageData: imageData)
        }
    }

    private func loadSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        pendingImageData = compressImageData(data) ?? data
    }

    private func compressImageData(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxDimension: CGFloat = 1024
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }

    private func scrollToBottom(proxy: ScrollViewProxy, session: AssistantChatSession) {
        guard let lastId = session.messages.last?.id else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(lastId, anchor: .bottom)
        }
    }
}
