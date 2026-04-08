import Foundation

@MainActor
final class FeedViewModel: ObservableObject {
    @Published var posts: [Post] = []
    @Published var query = ""
    @Published var selectedCategory = "all"
    @Published var selectedTimeFilter: TimeFilter = .all
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var refreshTrigger = UUID()

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
            if isCancellation(error) {
                return
            }
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

    func addComment(postId: String, text: String) async {
        do {
            try await APIClient.shared.addComment(postId: postId, text: text)
            await load()
        } catch {
            errorMessage = "Comment failed: \(error.localizedDescription)"
        }
    }

    func createPost(
        title: String,
        body: String,
        crop: String,
        category: Category,
        severity: Int,
        visibility: String,
        lat: Double,
        lng: Double,
        city: String,
        imageUrl: String?
    ) async {
        do {
            try await APIClient.shared.createPost(
                title: title,
                body: body,
                crop: crop,
                category: category,
                severity: severity,
                visibility: visibility,
                lat: lat,
                lng: lng,
                city: city,
                imageUrl: imageUrl
            )
            query = ""
            selectedCategory = "all"
            selectedTimeFilter = .all
            refreshTrigger = UUID()
            await load()
        } catch {
            errorMessage = "Create post failed: \(error.localizedDescription)"
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }

        return false
    }
}
