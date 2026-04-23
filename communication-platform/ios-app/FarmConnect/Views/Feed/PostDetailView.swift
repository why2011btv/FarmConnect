import SwiftUI

struct PostDetailView: View {
    struct FullscreenMediaPayload: Identifiable {
        let id = UUID()
        let mediaURLs: [URL]
        let startIndex: Int
    }

    let post: Post
    @EnvironmentObject private var feedViewModel: FeedViewModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var chatViewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var commentText = ""
    @State private var fullscreenMedia: FullscreenMediaPayload?
    @State private var isDeleteConfirmationPresented = false

    private var currentPost: Post {
        feedViewModel.posts.first(where: { $0.id == post.id }) ?? post
    }

    private var canChatAuthor: Bool {
        currentPost.userId != session.currentUser?.id
    }

    private var isOwner: Bool {
        currentPost.userId == session.currentUser?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if canChatAuthor {
                    NavigationLink {
                        ChatThreadView(conversationId: nil, otherUserId: currentPost.userId, title: currentPost.userName)
                            .environmentObject(chatViewModel)
                    } label: {
                        authorHeader
                    }
                    .buttonStyle(.plain)
                } else {
                    authorHeader
                }

                Text(currentPost.title)
                    .font(.title3.bold())
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                    Text("\(currentPost.city) · \(formattedCoordinate(currentPost.lat)), \(formattedCoordinate(currentPost.lng))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                let mediaUrls = resolvedMediaURLs(for: currentPost)
                if mediaUrls.count == 1, let url = mediaUrls.first {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.gray.opacity(0.2)
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture {
                        openFullscreen(mediaUrls: [url], startIndex: 0)
                    }
                } else if mediaUrls.count > 1 {
                    TabView {
                        ForEach(Array(mediaUrls.enumerated()), id: \.element.absoluteString) { index, url in
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Color.gray.opacity(0.2)
                            }
                            .frame(maxWidth: .infinity, maxHeight: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .onTapGesture {
                                openFullscreen(mediaUrls: mediaUrls, startIndex: index)
                            }
                        }
                    }
                    .frame(height: 320)
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                }
                Text(currentPost.body)
                    .foregroundStyle(.secondary)
                HStack {
                    Label(currentPost.category.rawValue, systemImage: "tag")
                    Spacer()
                    Button {
                        Task {
                            await feedViewModel.upvote(postId: currentPost.id)
                        }
                    } label: {
                        Label("\(currentPost.upvotes)", systemImage: "arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Divider()
                Text("Comments")
                    .font(.headline)

                if currentPost.comments.isEmpty {
                    Text("No comments yet")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                } else {
                    ForEach(currentPost.comments) { comment in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(comment.userName)
                                    .font(.caption.bold())
                                Spacer()
                                Text(TimeFormatting.relative(from: comment.createdAt))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(comment.text)
                                .font(.body)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .id(comment.id)
                    }
                    // Sentinel so we can always scroll to the same anchor below
                    // the newest comment, even if its height changes.
                    Color.clear.frame(height: 1).id(commentsBottomAnchor)
                }
            }
            .padding()
        }
        // When a new comment is added (either by this user or polled later)
        // jump to the bottom so it's visible.
        .onChange(of: currentPost.comments.count) { _, _ in
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(commentsBottomAnchor, anchor: .bottom)
            }
        }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                TextField("Add a comment", text: $commentText)
                    .textFieldStyle(.roundedBorder)
                Button("Send") {
                    let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    Task {
                        await feedViewModel.addComment(postId: currentPost.id, text: text)
                        commentText = ""
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.thinMaterial)
        }
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isOwner {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        isDeleteConfirmationPresented = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Delete post")
                }
            }
        }
        .alert(
            "Delete this post?",
            isPresented: $isDeleteConfirmationPresented
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    let postId = currentPost.id
                    let success = await feedViewModel.deletePost(postId: postId)
                    if success {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("“\(currentPost.title)” will be permanently removed, along with its comments and likes.")
        }
        .fullScreenCover(item: $fullscreenMedia) { payload in
            FullscreenMediaViewer(
                mediaURLs: payload.mediaURLs,
                initialIndex: payload.startIndex
            ) {
                fullscreenMedia = nil
            }
        }
    }

    private var authorHeader: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 36, height: 36)
                .overlay(
                    Text(String(currentPost.userName.prefix(1)).uppercased())
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(currentPost.userName)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Text(TimeFormatting.relative(from: currentPost.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            if canChatAuthor {
                Image(systemName: "message")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var commentsBottomAnchor: String { "comments-bottom" }

    private func formattedCoordinate(_ value: Double) -> String {
        String(format: "%.4f", value)
    }

    private func resolvedMediaURLs(for post: Post) -> [URL] {
        post.imageUrls.compactMap { APIClient.shared.resolveMediaURL(from: $0) }
    }

    private func openFullscreen(mediaUrls: [URL], startIndex: Int) {
        guard !mediaUrls.isEmpty else { return }
        let clampedIndex = min(max(0, startIndex), mediaUrls.count - 1)
        fullscreenMedia = FullscreenMediaPayload(mediaURLs: mediaUrls, startIndex: clampedIndex)
    }
}
