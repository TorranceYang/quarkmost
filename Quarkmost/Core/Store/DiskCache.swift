import Foundation

/// The local cache: the sidebar and the latest page of each conversation, as JSON files in Caches.
/// It only makes launch instant and lets you read offline; the server stays the source of truth, and
/// deleting these files loses nothing.
public enum DiskCache {
    private static let queue = DispatchQueue(label: "quarkmost.cache", qos: .utility)
    private static var directory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("store", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func url(_ key: String) -> URL {
        directory.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_") + ".json")
    }

    public static func save<T: Encodable & Sendable>(_ value: T, key: String) {
        queue.async {
            guard let data = try? JSONEncoder().encode(value) else { return }
            try? data.write(to: url(key), options: .atomic)
        }
    }

    public static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = try? Data(contentsOf: url(key)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    public static func clear() {
        queue.async { try? FileManager.default.removeItem(at: directory) }
    }
}

/// Everything the sidebar needs, saved after each successful refresh.
struct SidebarSnapshot: Codable, Sendable {
    var me: User
    var team: Team
    var channels: [Channel]
    var members: [ChannelMember]
    var categories: [SidebarCategory]
    var users: [User]
    var statuses: [String: String]
    var themeJSON: String?
    var savedPostIds: [String]
}
