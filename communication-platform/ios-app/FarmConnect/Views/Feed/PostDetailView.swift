import SwiftUI

struct PostDetailView: View {
    let post: Post
    @EnvironmentObject private var feedViewModel: FeedViewModel
    @State private var commentText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(post.title)
                    .font(.title3.bold())
                Text(post.body)
                    .foregroundStyle(.secondary)
                HStack {
                    Label(post.category.rawValue, systemImage: "tag")
                    Spacer()
                    Text("By \(post.userName)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Divider()
                Text("Comments")
                    .font(.headline)

                if post.comments.isEmpty {
                    Text("No comments yet")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                } else {
                    ForEach(post.comments) { comment in
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
                        await feedViewModel.addComment(postId: post.id, text: text)
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
