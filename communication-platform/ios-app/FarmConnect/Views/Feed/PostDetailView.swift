import SwiftUI

struct PostDetailView: View {
    let post: Post
    @EnvironmentObject private var feedViewModel: FeedViewModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var chatViewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var commentText = ""

    private var currentPost: Post {
        feedViewModel.posts.first(where: { $0.id == post.id }) ?? post
    }

    private var canChatAuthor: Bool {
        currentPost.userId != session.currentUser?.id
    }

    var body: some View {
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
                } else if mediaUrls.count > 1 {
                    TabView {
                        ForEach(mediaUrls, id: \.absoluteString) { url in
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Color.gray.opacity(0.2)
                            }
                            .frame(maxWidth: .infinity, maxHeight: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .frame(height: 320)
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                }
                Text(currentPost.body)
                    .foregroundStyle(.secondary)
                HStack {
                    Button {
                        Task {
                            feedViewModel.selectedCategory = currentPost.category.rawValue
                            feedViewModel.selectedTimeFilter = .all
                            await feedViewModel.load()
                            feedViewModel.refreshTrigger = UUID()
                            dismiss()
                        }
                    } label: {
                        Label(currentPost.category.rawValue, systemImage: "tag")
                    }
                    .buttonStyle(.plain)
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
                            Text(comment.userName)
                                .font(.caption.bold())
                            Text(comment.text)
                                .font(.body)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding()
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
                Text(relativeTime(currentPost.createdAt))
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

    private func relativeTime(_ timestampMs: Int64) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let date = Date(timeIntervalSince1970: Double(timestampMs) / 1000)
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func formattedCoordinate(_ value: Double) -> String {
        String(format: "%.4f", value)
    }

    private func resolvedMediaURLs(for post: Post) -> [URL] {
        post.imageUrls.compactMap { APIClient.shared.resolveMediaURL(from: $0) }
    }
}
