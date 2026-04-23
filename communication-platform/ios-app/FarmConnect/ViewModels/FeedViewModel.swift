import Foundation

@MainActor
final class FeedViewModel: ObservableObject {
    @Published var posts: [Post] = []
    @Published var query = ""
    @Published var selectedCategory = "all"
    @Published var selectedTimeFilter: TimeFilter = .all
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    @Published var refreshTrigger = UUID()

    /// Cursor for the next page (unix ms of the last visible post). `nil`
    /// means the currently-loaded set covers everything the server has.
    private(set) var nextCursor: Int64?

    var hasMorePages: Bool { nextCursor != nil }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let page = try await APIClient.shared.getPosts(
                query: query,
                category: selectedCategory,
                timeFilter: selectedTimeFilter
            )
            posts = page.items
            nextCursor = page.nextCursor
        } catch {
            if isCancellationError(error) { return }
            errorMessage = "Failed to load posts: \(error.localizedDescription)"
        }
    }

    /// Fetches the next page using the saved cursor. No-op if we're already
    /// loading or there are no more pages. Safe to call from `.onAppear` of
    /// the last visible cell.
    func loadMoreIfNeeded() async {
        guard let cursor = nextCursor else { return }
        guard !isLoadingMore && !isLoading else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await APIClient.shared.getPosts(
                query: query,
                category: selectedCategory,
                timeFilter: selectedTimeFilter,
                before: cursor
            )
            // Deduplicate in case posts shifted between fetches.
            let existingIds = Set(posts.map(\.id))
            posts.append(contentsOf: page.items.filter { !existingIds.contains($0.id) })
            nextCursor = page.nextCursor
        } catch {
            if isCancellationError(error) { return }
            errorMessage = "Failed to load more posts: \(error.localizedDescription)"
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

    @discardableResult
    func deletePost(postId: String) async -> Bool {
        do {
            try await APIClient.shared.deletePost(postId: postId)
            posts.removeAll { $0.id == postId }
            refreshTrigger = UUID()
            return true
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
            return false
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
        imageUrls: [String]?
    ) async -> Bool {
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
                imageUrls: imageUrls
            )
            refreshTrigger = UUID()
            await load()
            return true
        } catch {
            errorMessage = "Create post failed: \(error.localizedDescription)"
            return false
        }
    }

}
