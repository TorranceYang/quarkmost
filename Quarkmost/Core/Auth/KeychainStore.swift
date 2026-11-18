import Foundation
import Security

/// Stores the session token and server address in the Keychain, in a group shared with the
/// notification extension (which needs both to fetch the sender's avatar).
public enum KeychainStore {
    private static var bundleID: String { ServerConfig.info("QMBundleID") ?? Bundle.main.bundleIdentifier ?? "quarkmost" }
    private static var tokenService: String { "\(bundleID).session" }
    private static var serverService: String { "\(bundleID).server" }
    /// Team ID prefix + "<bundle id>.shared", as in both targets' entitlements.
    static var sharedGroup: String? { ServerConfig.info("QMKeychainGroup") }

    private static func base(_ service: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
    }

    private static func save(_ value: String, service: String) throws {
        SecItemDelete(base(service) as CFDictionary)     // no group: removes it from every group we can see
        var add = base(service)
        add[kSecAttrAccount as String] = "default"
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        var status = errSecMissingEntitlement
        if let sharedGroup {
            var shared = add
            shared[kSecAttrAccessGroup as String] = sharedGroup
            status = SecItemAdd(shared as CFDictionary, nil)
        }
        // Builds without the shared-group entitlement (some simulator setups) fall back to the default group.
        if status != errSecSuccess { status = SecItemAdd(add as CFDictionary, nil) }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    private static func load(service: String) -> String? {
        var query = base(service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func saveToken(_ token: String) throws { try save(token, service: tokenService) }
    public static func loadToken() -> String? { load(service: tokenService) }
    public static func deleteToken() { SecItemDelete(base(tokenService) as CFDictionary) }

    public static func saveServerURL(_ url: String) throws { try save(url, service: serverService) }
    public static func loadServerURL() -> String? { load(service: serverService) }

    /// Moves a token saved by an older build into the shared group. Safe to call on every launch.
    public static func migrateToSharedGroup() {
        guard let sharedGroup else { return }
        var query = base(tokenService)
        query[kSecAttrAccessGroup as String] = sharedGroup
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess { return }
        if let token = loadToken() { try? saveToken(token) }
    }
}
