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
    private var authToken: String?

    func setAuthToken(_ token: String?) {
        authToken = token
    }

    private func authorizedRequest(path: String, method: String = "GET") throws -> URLRequest {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    func login(name: String) async throws -> AuthResponse {
        var req = try authorizedRequest(path: "/v1/auth/login", method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["name": name])

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.badStatus(-1) }
        guard 200..<300 ~= http.statusCode else { throw APIError.badStatus(http.statusCode) }
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }

    func me() async throws -> UserProfile {
        let req = try authorizedRequest(path: "/v1/auth/me")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.badStatus(-1) }
        guard 200..<300 ~= http.statusCode else { throw APIError.badStatus(http.statusCode) }
        return try JSONDecoder().decode(AuthMeResponse.self, from: data).user
    }

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
        let req = try authorizedRequest(path: "/v1/posts/\(postId)/upvote", method: "POST")

        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.badStatus(-1) }
        guard 200..<300 ~= http.statusCode else { throw APIError.badStatus(http.statusCode) }
    }

    func getConversations() async throws -> [Conversation] {
        let req = try authorizedRequest(path: "/v1/conversations")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.badStatus(-1) }
        guard 200..<300 ~= http.statusCode else { throw APIError.badStatus(http.statusCode) }

        return try JSONDecoder().decode(ConversationListResponse.self, from: data).items
    }

    func getMessages(otherUserId: String) async throws -> [Message] {
        var components = URLComponents(url: baseURL.appendingPathComponent("/v1/messages"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "otherUserId", value: otherUserId)]
        guard let url = components?.url else { throw APIError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if let token = authToken {
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.badStatus(-1) }
        guard 200..<300 ~= http.statusCode else { throw APIError.badStatus(http.statusCode) }
        return try JSONDecoder().decode(MessageListResponse.self, from: data).items
    }

    func sendMessage(toUserId: String, text: String) async throws {
        var req = try authorizedRequest(path: "/v1/messages", method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "toUserId": toUserId,
            "text": text
        ])
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.badStatus(-1) }
        guard 200..<300 ~= http.statusCode else { throw APIError.badStatus(http.statusCode) }
    }

    func addComment(postId: String, text: String) async throws {
        var req = try authorizedRequest(path: "/v1/posts/\(postId)/comments", method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["text": text])

        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.badStatus(-1) }
        guard 200..<300 ~= http.statusCode else { throw APIError.badStatus(http.statusCode) }
    }

    func createUploadUrl(fileName: String, mimeType: String) async throws -> (uploadUrl: String, publicUrl: String) {
        var req = try authorizedRequest(path: "/v1/uploads/create", method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "fileName": fileName,
            "mimeType": mimeType
        ])
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.badStatus(-1) }
        guard 200..<300 ~= http.statusCode else { throw APIError.badStatus(http.statusCode) }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let uploadUrl = json["uploadUrl"] as? String,
            let publicUrl = json["publicUrl"] as? String
        else {
            throw APIError.badStatus(-2)
        }
        return (uploadUrl, publicUrl)
    }

    func uploadImage(data: Data, fileName: String, mimeType: String) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = try authorizedRequest(path: "/v1/uploads/image", method: "POST")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (responseData, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.badStatus(-1) }
        guard 200..<300 ~= http.statusCode else { throw APIError.badStatus(http.statusCode) }

        guard
            let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
            let publicUrl = json["publicUrl"] as? String
        else {
            throw APIError.badStatus(-2)
        }
        if publicUrl.hasPrefix("http://") || publicUrl.hasPrefix("https://") {
            return publicUrl
        }
        return baseURL.appendingPathComponent(publicUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).absoluteString
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
    ) async throws {
        var req = try authorizedRequest(path: "/v1/posts", method: "POST")
        var payload: [String: Any] = [
            "title": title,
            "body": body,
            "crop": crop,
            "category": category.rawValue,
            "severity": severity,
            "visibility": visibility,
            "lat": lat,
            "lng": lng,
            "city": city
        ]
        if let imageUrl {
            payload["imageUrl"] = imageUrl
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.badStatus(-1) }
        guard 200..<300 ~= http.statusCode else { throw APIError.badStatus(http.statusCode) }
    }

    func registerDeviceToken(_ token: String) async throws {
        var req = try authorizedRequest(path: "/v1/notifications/register-device", method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["deviceToken": token])
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.badStatus(-1) }
        guard 200..<300 ~= http.statusCode else { throw APIError.badStatus(http.statusCode) }
    }
}
