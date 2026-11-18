import Foundation

/// The server this app talks to. Chosen on the login screen and remembered (in the Keychain group
/// shared with the notification extension); `QM_DEFAULT_SERVER_URL` in Config/Local.xcconfig can
/// pre-fill it.
public enum ServerConfig {
    /// Values baked into Info.plist from the xcconfig files.
    static func info(_ key: String) -> String? {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The build's default server (may be nil: then the user types one in).
    public static var defaultServerURL: URL? { info("QMDefaultServerURL").flatMap(normalize) }

    nonisolated(unsafe) private static var cached: URL?

    /// The server in use. Before login this is the default (or a placeholder that's never contacted).
    public static var baseURL: URL {
        if let cached { return cached }
        let url = KeychainStore.loadServerURL().flatMap(normalize) ?? defaultServerURL ?? URL(string: "https://invalid.example")!
        cached = url
        return url
    }

    public static var hasServer: Bool { KeychainStore.loadServerURL() != nil || defaultServerURL != nil }

    public static func setServer(_ url: URL) throws {
        try KeychainStore.saveServerURL(url.absoluteString)
        cached = url
    }

    /// "chat.example.com", "chat.example.com/", "https://chat.example.com/sub" → https URL, no trailing slash.
    public static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "https://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host?.isEmpty == false else { return nil }
        return url
    }

    public static var apiURL: URL { baseURL.appendingPathComponent("api/v4") }

    public static var webSocketURL: URL {
        var components = URLComponents(url: apiURL.appendingPathComponent("websocket"), resolvingAgainstBaseURL: false)!
        components.scheme = baseURL.scheme == "http" ? "ws" : "wss"
        return components.url!
    }

    /// Some proxies (e.g. Cloudflare) reject default user-agents, so every request identifies itself.
    public static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
        return "Quarkmost/\(version) (iOS)"
    }

    /// Device-ID prefix registered with the server. Must match the push proxy's `Type`.
    public static let pushDevicePrefix = "apple"
}

/// The app's name as shown under its icon (`QM_DISPLAY_NAME`).
public enum AppInfo {
    public static var displayName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? "Quarkmost"
    }
}
