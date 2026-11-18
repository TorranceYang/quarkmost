import Foundation

/// The rest of the REST surface the official mobile app uses (`app/client/rest/*`).
public extension MattermostClient {
    private func post<T: Decodable>(_ path: String, _ body: JSONValue, method: String = "POST",
                                    query: [String: String] = [:]) async throws -> T {
        let (data, _) = try await send(path, method: method, body: body, query: query)
        return try decoder.decode(T.self, from: data)
    }

    private func call(_ path: String, _ body: JSONValue? = nil, method: String = "POST") async throws {
        _ = try await send(path, method: method, body: body)
    }

    // MARK: Posts

    func post(id: String) async throws -> Post { try await get("posts/\(id)") }

    func posts(channelId: String, before postId: String, perPage: Int = 30) async throws -> PostList {
        try await get("channels/\(channelId)/posts", query: ["before": postId, "per_page": "\(perPage)"])
    }

    func posts(channelId: String, after postId: String, perPage: Int = 30) async throws -> PostList {
        try await get("channels/\(channelId)/posts", query: ["after": postId, "per_page": "\(perPage)"])
    }

    func createPost(channelId: String, message: String, rootId: String?, fileIds: [String],
                    pendingPostId: String?) async throws -> Post {
        var body: [String: JSONValue] = ["channel_id": .string(channelId), "message": .string(message),
                                         "file_ids": .array(fileIds.map(JSONValue.string))]
        if let rootId { body["root_id"] = .string(rootId) }
        if let pendingPostId { body["pending_post_id"] = .string(pendingPostId) }
        return try await post("posts", .object(body))
    }

    func searchPosts(teamId: String, terms: String, isOrSearch: Bool = false) async throws -> PostList {
        let offset = TimeZone.current.secondsFromGMT()
        return try await post("teams/\(teamId)/posts/search",
                              ["terms": .string(terms), "is_or_search": .bool(isOrSearch),
                               "time_zone_offset": .number(Double(offset)), "page": 0, "per_page": 60])
    }

    func flaggedPosts(userId: String, teamId: String) async throws -> PostList {
        try await get("users/\(userId)/posts/flagged", query: ["team_id": teamId, "per_page": "60"])
    }

    func pinnedPosts(channelId: String) async throws -> PostList { try await get("channels/\(channelId)/pinned") }

    func searchFiles(teamId: String, terms: String) async throws -> FileSearchResults {
        try await post("teams/\(teamId)/files/search", ["terms": .string(terms), "is_or_search": false])
    }

    // MARK: Threads

    func threads(userId: String, teamId: String, unreadOnly: Bool, before: String? = nil) async throws -> ThreadList {
        var q = ["extended": "true", "per_page": "25", "unread": "\(unreadOnly)"]
        if let before { q["before"] = before }
        return try await get("users/\(userId)/teams/\(teamId)/threads", query: q)
    }

    func threadTotals(userId: String, teamId: String) async throws -> ThreadList {
        try await get("users/\(userId)/teams/\(teamId)/threads", query: ["totalsOnly": "true"])
    }

    func markThreadRead(userId: String, teamId: String, threadId: String, timestamp: Int64) async throws {
        try await call("users/\(userId)/teams/\(teamId)/threads/\(threadId)/read/\(timestamp)", method: "PUT")
    }

    func markAllThreadsRead(userId: String, teamId: String) async throws {
        try await call("users/\(userId)/teams/\(teamId)/threads/read", method: "PUT")
    }

    // MARK: Drafts

    func drafts(teamId: String) async throws -> [Draft] { try await get("users/me/teams/\(teamId)/drafts") }

    func saveDraft(channelId: String, rootId: String?, message: String) async throws {
        try await call("drafts", ["channel_id": .string(channelId), "root_id": .string(rootId ?? ""),
                                  "message": .string(message)])
    }

    func deleteDraft(channelId: String, rootId: String?) async throws {
        let suffix = (rootId?.isEmpty ?? true) ? "" : "/\(rootId!)"
        try await call("users/me/channels/\(channelId)/drafts\(suffix)", method: "DELETE")
    }

    // MARK: Channels

    func channel(id: String) async throws -> Channel { try await get("channels/\(id)") }
    func channelStats(id: String) async throws -> ChannelStats { try await get("channels/\(id)/stats") }

    func channelMember(channelId: String, userId: String) async throws -> FullChannelMember {
        try await get("channels/\(channelId)/members/\(userId)")
    }

    func users(inChannel channelId: String, page: Int = 0) async throws -> [User] {
        try await get("users", query: ["in_channel": channelId, "page": "\(page)", "per_page": "100", "sort": "status"])
    }

    func users(inTeam teamId: String, page: Int = 0) async throws -> [User] {
        try await get("users", query: ["in_team": teamId, "page": "\(page)", "per_page": "100", "sort": "username"])
    }

    func searchUsers(term: String, teamId: String?, notInChannel: String? = nil) async throws -> [User] {
        var body: [String: JSONValue] = ["term": .string(term)]
        if let teamId { body["team_id"] = .string(teamId) }
        if let notInChannel { body["not_in_channel_id"] = .string(notInChannel) }
        return try await post("users/search", .object(body))
    }

    func user(id: String) async throws -> User { try await get("users/\(id)") }
    func user(username: String) async throws -> User { try await get("users/username/\(username)") }

    func autocompleteUsers(term: String, teamId: String, channelId: String) async throws -> UserAutocomplete {
        try await get("users/autocomplete", query: ["in_team": teamId, "in_channel": channelId, "name": term, "limit": "25"])
    }

    func autocompleteChannels(term: String, teamId: String) async throws -> [Channel] {
        try await get("teams/\(teamId)/channels/autocomplete", query: ["name": term])
    }

    func publicChannels(teamId: String, page: Int = 0) async throws -> [Channel] {
        try await get("teams/\(teamId)/channels", query: ["page": "\(page)", "per_page": "100"])
    }

    func searchChannels(teamId: String, term: String) async throws -> [Channel] {
        try await post("teams/\(teamId)/channels/search", ["term": .string(term)])
    }

    func addMember(channelId: String, userId: String) async throws {
        try await call("channels/\(channelId)/members", ["user_id": .string(userId)])
    }

    func removeMember(channelId: String, userId: String) async throws {
        try await call("channels/\(channelId)/members/\(userId)", method: "DELETE")
    }

    func createChannel(teamId: String, displayName: String, isPrivate: Bool, purpose: String, header: String) async throws -> Channel {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        var name = String(displayName.lowercased().replacingOccurrences(of: " ", with: "-").filter { allowed.contains($0) })
        if name.count < 2 { name = "channel-" + String(UUID().uuidString.lowercased().prefix(8)) }
        return try await post("channels", ["team_id": .string(teamId), "name": .string(name),
                                           "display_name": .string(displayName), "type": .string(isPrivate ? "P" : "O"),
                                           "purpose": .string(purpose), "header": .string(header)])
    }

    func patchChannel(id: String, header: String? = nil, purpose: String? = nil, displayName: String? = nil) async throws -> Channel {
        var body: [String: JSONValue] = [:]
        if let header { body["header"] = .string(header) }
        if let purpose { body["purpose"] = .string(purpose) }
        if let displayName { body["display_name"] = .string(displayName) }
        return try await post("channels/\(id)/patch", .object(body), method: "PUT")
    }

    func archiveChannel(id: String) async throws { try await call("channels/\(id)", method: "DELETE") }

    func createDirect(userIds: [String]) async throws -> Channel {
        try await post(userIds.count == 2 ? "channels/direct" : "channels/group", .array(userIds.map(JSONValue.string)))
    }

    func updateNotifyProps(channelId: String, userId: String, props: [String: String]) async throws {
        var body: [String: JSONValue] = ["channel_id": .string(channelId), "user_id": .string(userId)]
        for (k, v) in props { body[k] = .string(v) }
        try await call("channels/\(channelId)/members/\(userId)/notify_props", .object(body), method: "PUT")
    }

    func updateCategories(userId: String, teamId: String, categories: [SidebarCategory]) async throws {
        _ = try await send("users/\(userId)/teams/\(teamId)/channels/categories", method: "PUT", body: categories)
    }

    // MARK: Preferences, status, profile

    func savePreferences(userId: String, _ prefs: [(category: String, name: String, value: String)]) async throws {
        let body = JSONValue.array(prefs.map { ["user_id": .string(userId), "category": .string($0.category),
                                                "name": .string($0.name), "value": .string($0.value)] })
        try await call("users/\(userId)/preferences", body, method: "PUT")
    }

    func allPreferences(userId: String) async throws -> [Preference] { try await get("users/\(userId)/preferences") }

    func setStatus(userId: String, status: String, dndEndTime: Int64? = nil) async throws {
        var body: [String: JSONValue] = ["user_id": .string(userId), "status": .string(status)]
        if let dndEndTime { body["dnd_end_time"] = .number(Double(dndEndTime)) }
        try await call("users/\(userId)/status", .object(body), method: "PUT")
    }

    func setCustomStatus(emoji: String, text: String, duration: String, expiresAt: Date?) async throws {
        var body: [String: JSONValue] = ["emoji": .string(emoji), "text": .string(text)]
        if let expiresAt {
            body["duration"] = .string(duration)
            body["expires_at"] = .string(ISO8601DateFormatter.flexible.string(from: expiresAt))
        }
        try await call("users/me/status/custom", .object(body), method: "PUT")
    }

    func clearCustomStatus() async throws { try await call("users/me/status/custom", method: "DELETE") }

    func patchMe(_ fields: [String: String]) async throws -> User {
        try await post("users/me/patch", .object(fields.mapValues(JSONValue.string)), method: "PUT")
    }

    func patchMyNotifyProps(_ props: [String: JSONValue]) async throws -> User {
        try await post("users/me/patch", ["notify_props": .object(props)], method: "PUT")
    }

    func saveTheme(userId: String, teamId: String, json: String) async throws {
        try await savePreferences(userId: userId, [("theme", teamId, json)])
    }

    func clientConfig() async throws -> [String: String] { try await get("config/client", query: ["format": "old"]) }

    // MARK: Commands

    func commands(teamId: String) async throws -> [SlashCommand] {
        try await get("teams/\(teamId)/commands/autocomplete")
    }

    func executeCommand(_ command: String, channelId: String, teamId: String, rootId: String?) async throws -> CommandResponse {
        var body: [String: JSONValue] = ["command": .string(command), "channel_id": .string(channelId), "team_id": .string(teamId)]
        if let rootId { body["root_id"] = .string(rootId) }
        return try await post("commands/execute", .object(body))
    }

    // MARK: Files

    /// Simple (non-multipart) upload: raw bytes with the channel and filename in the query.
    func uploadFile(data: Data, filename: String, channelId: String,
                    progress: (@Sendable (Double) -> Void)? = nil) async throws -> FileInfo {
        var c = URLComponents(url: ServerConfig.apiURL.appendingPathComponent("files"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "channel_id", value: channelId), URLQueryItem(name: "filename", value: filename)]
        var request = URLRequest(url: c.url!)
        request.httpMethod = "POST"
        request.setValue(ServerConfig.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        guard let token else { throw ClientError.notAuthenticated }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let delegate = UploadProgressDelegate(progress)
        let (body, response) = try await session.upload(for: request, from: data, delegate: delegate)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            if let e = try? decoder.decode(APIError.self, from: body) { throw e }
            throw ClientError.badResponse
        }
        guard let info = try decoder.decode(FileUploadResponse.self, from: body).fileInfos.first else { throw ClientError.badResponse }
        return info
    }
}

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    let progress: (@Sendable (Double) -> Void)?
    init(_ progress: (@Sendable (Double) -> Void)?) { self.progress = progress }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        progress?(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}
