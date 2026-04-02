import Foundation

enum APIError: Error {
    case badURL
    case badStatus(Int)
}

final class APIClient {
    static let shared = APIClient()
    private init() {}

    // Replace this with your cloud API endpoint.
    private let baseURL = URL(string: "http://localhost:4000")!

    func getPosts(
        query: String,
        category: String,
        timeFilter: TimeFilter
    ) async throws -> [Post] {
        var components = URLComponents(url: baseURL.appendingPathComponent("/v1/posts"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "category", value: category),
            URLQueryItem(name: "timeFilter", value: timeFilter.rawValue),
            URLQueryItem(name: "visibility", value: "Public")
        ]
        guard let url = components?.url else { throw APIError.badURL }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw APIError.badStatus(-1) }
        guard 200..<300 ~= http.statusCode else { throw APIError.badStatus(http.statusCode) }

        return try JSONDecoder().decode(PostListResponse.self, from: data).items
    }

    func upvote(postId: String) async throws {
        let url = baseURL.appendingPathComponent("/v1/posts/\(postId)/upvote")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.badStatus(-1) }
        guard 200..<300 ~= http.statusCode else { throw APIError.badStatus(http.statusCode) }
    }

    func getConversations(userId: String) async throws -> [Conversation] {
        var components = URLComponents(url: baseURL.appendingPathComponent("/v1/conversations"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "userId", value: userId)]
        guard let url = components?.url else { throw APIError.badURL }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw APIError.badStatus(-1) }
        guard 200..<300 ~= http.statusCode else { throw APIError.badStatus(http.statusCode) }

        return try JSONDecoder().decode(ConversationListResponse.self, from: data).items
    }
}
