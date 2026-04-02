import Foundation

@MainActor
final class FeedViewModel: ObservableObject {
    @Published var posts: [Post] = []
    @Published var query = ""
    @Published var selectedCategory = "all"
    @Published var selectedTimeFilter: TimeFilter = .all
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            posts = try await APIClient.shared.getPosts(
                query: query,
                category: selectedCategory,
                timeFilter: selectedTimeFilter
            )
        } catch {
            errorMessage = "Failed to load posts: \(error.localizedDescription)"
        }
    }

    func upvote(postId: String) async {
        do {
            try await APIClient.shared.upvote(postId: postId)
            await load()
        } catch {
            errorMessage = "Upvote failed: \(error.localizedDescription)"
        }
    }
}
