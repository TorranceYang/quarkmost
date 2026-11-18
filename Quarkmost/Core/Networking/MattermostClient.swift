import Foundation

public struct APIError: Error, Decodable, Sendable, CustomStringConvertible {
    public let id: String?
    public let message: String
    public let statusCode: Int?

    public var description: String { "\(statusCode ?? 0) \(id ?? ""): \(message)" }
}

public enum ClientError: Error, Sendable {
    case notAuthenticated
    case badResponse
    case missingToken
}

/// Thin async wrapper around Mattermost REST API v4.
public actor MattermostClient {
    let session: URLSession
    let decoder: JSONDecoder
    private let encoder: JSONEncoder
    public private(set) var token: String?

    public init(token: String? = nil, session: URLSession = .shared) {
        self.token = token
        self.session = session
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    public func setToken(_ token: String?) { self.token = token }

    // MARK: Auth

    /// Logs in and returns the user plus the session token (from the `Token` response header).
    public func login(loginId: String, password: String, mfaCode: String? = nil) async throws -> (User, String) {
        let body = LoginRequest(loginId: loginId, password: password, token: mfaCode, deviceId: nil)
        let (data, response) = try await send("users/login", method: "POST", body: body, authenticated: false)
        guard let token = response.value(forHTTPHeaderField: "Token") else { throw ClientError.missingToken }
        self.token = token
        return (try decoder.decode(User.self, from: data), token)
    }

    public func logout() async throws {
        _ = try await send("users/logout", method: "POST", body: Optional<String>.none)
        token = nil
    }

    // MARK: Reads

    public func me() async throws -> User { try await get("users/me") }

    public func myTeams() async throws -> [Team] { try await get("users/me/teams") }

    public func myChannels(teamId: String) async throws -> [Channel] {
        try await get("users/me/teams/\(teamId)/channels")
    }

    public func myChannelMembers(teamId: String) async throws -> [ChannelMember] {
        try await get("users/me/teams/\(teamId)/channels/members")
    }

    public func sidebarCategories(userId: String, teamId: String) async throws -> SidebarCategoryList {
        try await get("users/\(userId)/teams/\(teamId)/channels/categories")
    }

    public func users(ids: [String]) async throws -> [User] {
        guard !ids.isEmpty else { return [] }
        let (data, _) = try await send("users/ids", method: "POST", body: ids)
        return try decoder.decode([User].self, from: data)
    }

    public func updateCategory(_ category: SidebarCategory) async throws {
        _ = try await send("users/\(category.userId)/teams/\(category.teamId)/channels/categories/\(category.id)",
                           method: "PUT", body: category)
    }

    public func customEmoji(page: Int) async throws -> [CustomEmoji] {
        try await get("emoji", query: ["page": "\(page)", "per_page": "200", "sort": "name"])
    }

    public func statuses(userIds: [String]) async throws -> [UserStatus] {
        guard !userIds.isEmpty else { return [] }
        let (data, _) = try await send("users/status/ids", method: "POST", body: userIds)
        return try decoder.decode([UserStatus].self, from: data)
    }

    public func preferences(userId: String, category: String) async throws -> [Preference] {
        try await get("users/\(userId)/preferences/\(category)")
    }

    /// Channel posts, newest first. With collapsed reply threads, replies stay in their thread.
    public func posts(channelId: String, page: Int = 0, perPage: Int = 60, collapsedThreads: Bool = true) async throws -> PostList {
        try await get("channels/\(channelId)/posts", query: ["page": "\(page)", "per_page": "\(perPage)",
                                                            "collapsedThreads": "\(collapsedThreads)",
                                                            "collapsedThreadsExtended": "false"])
    }

    /// Posts changed since a timestamp (ms) — used to catch up after a WebSocket reconnect.
    public func posts(channelId: String, since: Int64) async throws -> PostList {
        try await get("channels/\(channelId)/posts", query: ["since": "\(since)"])
    }

    public func thread(postId: String) async throws -> PostList { try await get("posts/\(postId)/thread") }

    // MARK: Writes

    public func createPost(channelId: String, message: String, rootId: String? = nil,
                           pendingPostId: String? = nil) async throws -> Post {
        struct Body: Encodable { let channelId: String; let message: String; let rootId: String?; let pendingPostId: String? }
        let (data, _) = try await send("posts", method: "POST",
                                       body: Body(channelId: channelId, message: message, rootId: rootId,
                                                  pendingPostId: pendingPostId))
        return try decoder.decode(Post.self, from: data)
    }

    // MARK: Post actions

    public func addReaction(userId: String, postId: String, emojiName: String) async throws {
        struct Body: Encodable { let userId: String; let postId: String; let emojiName: String }
        _ = try await send("reactions", method: "POST", body: Body(userId: userId, postId: postId, emojiName: emojiName))
    }

    public func removeReaction(userId: String, postId: String, emojiName: String) async throws {
        _ = try await send("users/\(userId)/posts/\(postId)/reactions/\(emojiName)", method: "DELETE", body: Optional<String>.none)
    }

    public func editPost(id: String, message: String) async throws -> Post {
        struct Body: Encodable { let message: String }
        let (data, _) = try await send("posts/\(id)/patch", method: "PUT", body: Body(message: message))
        return try decoder.decode(Post.self, from: data)
    }

    public func deletePost(id: String) async throws {
        _ = try await send("posts/\(id)", method: "DELETE", body: Optional<String>.none)
    }

    public func setPinned(_ pinned: Bool, postId: String) async throws {
        _ = try await send("posts/\(postId)/\(pinned ? "pin" : "unpin")", method: "POST", body: Optional<String>.none)
    }

    public func markUnread(userId: String, postId: String) async throws {
        _ = try await send("users/\(userId)/posts/\(postId)/set_unread", method: "POST", body: Optional<String>.none)
    }

    /// Saved ("flagged") posts are preferences in category `flagged_post`, one per post.
    public func setSaved(_ saved: Bool, userId: String, postId: String) async throws {
        struct Pref: Encodable { let userId: String; let category: String; let name: String; let value: String }
        let pref = Pref(userId: userId, category: "flagged_post", name: postId, value: "true")
        _ = try await send("users/\(userId)/preferences\(saved ? "" : "/delete")", method: saved ? "PUT" : "POST", body: [pref])
    }

    public func setFollowing(_ following: Bool, userId: String, teamId: String, threadId: String) async throws {
        _ = try await send("users/\(userId)/teams/\(teamId)/threads/\(threadId)/following",
                           method: following ? "PUT" : "DELETE", body: Optional<String>.none)
    }

    public func markChannelViewed(channelId: String) async throws {
        struct Body: Encodable { let channelId: String }
        _ = try await send("channels/members/me/view", method: "POST", body: Body(channelId: channelId))
    }

    /// Registers this device's APNs token with the current session so the server sends it pushes.
    public func attachDevice(apnsTokenHex: String) async throws {
        struct Body: Encodable { let deviceId: String }
        _ = try await send("users/sessions/device", method: "PUT",
                           body: Body(deviceId: "\(ServerConfig.pushDevicePrefix):\(apnsTokenHex)"))
    }

    // MARK: Plumbing

    func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let (data, _) = try await send(path, method: "GET", body: Optional<String>.none, query: query)
        return try decoder.decode(T.self, from: data)
    }

    func send<B: Encodable>(_ path: String, method: String, body: B?, query: [String: String] = [:],
                                    authenticated: Bool = true) async throws -> (Data, HTTPURLResponse) {
        var components = URLComponents(url: ServerConfig.apiURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue(ServerConfig.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        if authenticated {
            guard let token else { throw ClientError.notAuthenticated }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            if let apiError = try? decoder.decode(APIError.self, from: data) { throw apiError }
            throw APIError(id: nil, message: HTTPURLResponse.localizedString(forStatusCode: http.statusCode),
                           statusCode: http.statusCode)
        }
        return (data, http)
    }
}
