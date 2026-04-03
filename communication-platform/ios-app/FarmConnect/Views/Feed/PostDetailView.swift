import SwiftUI

struct PostDetailView: View {
    let post: Post
    @EnvironmentObject private var feedViewModel: FeedViewModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var chatViewModel: ChatViewModel
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
                Text(currentPost.title)
                    .font(.title3.bold())
                if let imageUrl = currentPost.imageUrl, let url = APIClient.shared.resolveMediaURL(from: imageUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.gray.opacity(0.2)
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Text(currentPost.body)
                    .foregroundStyle(.secondary)
                HStack {
                    Label(currentPost.category.rawValue, systemImage: "tag")
                    Spacer()
                    if canChatAuthor {
                        NavigationLink {
                            ChatThreadView(conversationId: nil, otherUserId: currentPost.userId, title: currentPost.userName)
                                .environmentObject(chatViewModel)
                        } label: {
                            Text("By \(currentPost.userName)")
                        }
                    } else {
                        Text("By \(currentPost.userName)")
                    }
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
}
