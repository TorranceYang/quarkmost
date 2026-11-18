import Intents
import UIKit
import UserNotifications

/// Formats Mattermost pushes before they're shown, to match the official app: the sender's avatar
/// (a "communication notification", like Messages), the name once, then the message.
///
/// Relevant payload keys: `channel_id`, `post_id`, `root_id`, `sender_id`, `sender_name`,
/// `channel_name`, `override_username`, `override_icon_url`, `type` ("message" | "clear" | …).
final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?
    private var delivered = false

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        bestAttempt = content
        let info = content.userInfo
        let channelId = info["channel_id"] as? String
        if let channelId { content.threadIdentifier = channelId }   // group per channel

        func clean(_ s: String?) -> String? { s.flatMap { $0.isEmpty ? nil : $0 } }
        let sender = clean(info["override_username"] as? String).map { "@\($0)" } ?? clean(info["sender_name"] as? String)
        let channelName = clean(info["channel_name"] as? String)
        // As in the official extension: the title is the channel name (for a DM the server sends the
        // sender's name there), and the sender goes in the message text for channels.
        let isChannel = channelName != nil && channelName != sender
        let title = channelName ?? sender
        if let sender {
            let prefix = "\(sender): "
            if isChannel, !content.body.hasPrefix(prefix) { content.body = prefix + content.body }
            if !isChannel, content.body.hasPrefix(prefix) { content.body = String(content.body.dropFirst(prefix.count)) }
        }
        // Plain fallback (used as-is if the avatar step fails).
        content.title = title ?? content.title
        content.subtitle = ""
        if content.categoryIdentifier.isEmpty, info["post_id"] != nil { content.categoryIdentifier = "CAN_REPLY" }

        guard let sender, let channelId else { deliver(content); return }
        let senderId = clean(info["sender_id"] as? String)
        let iconOverride = clean(info["override_icon_url"] as? String)
        nonisolated(unsafe) let plain = content
        Task { [weak self] in
            // If the picture can't be fetched, draw initials so it's never just the app icon.
            let avatar = await Self.avatar(senderId: senderId, override: iconOverride) ?? Self.monogram(for: sender)
            let handle = INPersonHandle(value: senderId ?? sender, type: .unknown)
            let person = INPerson(personHandle: handle, nameComponents: nil, displayName: title ?? sender,
                                  image: avatar.map { INImage(imageData: $0) }, contactIdentifier: nil,
                                  customIdentifier: senderId ?? sender)
            let intent = INSendMessageIntent(
                recipients: nil, outgoingMessageType: .outgoingMessageText, content: plain.body,
                speakableGroupName: nil,
                conversationIdentifier: channelId, serviceName: nil, sender: person, attachments: nil)
            let interaction = INInteraction(intent: intent, response: nil)
            interaction.direction = .incoming
            try? await interaction.donate()
            if let updated = try? plain.updating(from: intent) { self?.deliver(updated) } else { self?.deliver(plain) }
        }
    }

    private func deliver(_ content: UNNotificationContent) {
        guard !delivered else { return }
        delivered = true
        contentHandler?(content)
    }

    override func serviceExtensionTimeWillExpire() {
        if let bestAttempt { deliver(bestAttempt) }
    }

    // MARK: Avatar

    /// Build settings baked into Info.plist (see Config/Base.xcconfig).
    private static func info(_ key: String) -> String? {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The server the app logged in to (saved in the shared Keychain group), else the build default.
    private static var server: URL? {
        (keychainValue(service: "server") ?? info("QMDefaultServerURL")).flatMap { URL(string: $0) }
    }

    /// The sender's profile picture (or a webhook's custom icon), fetched with the app's session.
    private static func avatar(senderId: String?, override: String?) async -> Data? {
        var url: URL?
        guard let server else { return nil }
        if let override { url = URL(string: override, relativeTo: server)?.absoluteURL }
        else if let senderId { url = server.appendingPathComponent("api/v4/users/\(senderId)/image") }
        guard let url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Quarkmost-NotificationService/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        if url.host == server.host, let token = keychainValue(service: "session") {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return nil }
        return data
    }

    /// A round initials badge in the app's blue, used when the real picture isn't available.
    private static func monogram(for name: String) -> Data? {
        let letters = name.trimmingCharacters(in: CharacterSet(charactersIn: "@ ")).prefix(1).uppercased()
        let size = CGSize(width: 120, height: 120)
        return UIGraphicsImageRenderer(size: size).pngData { _ in
            UIColor(red: 0.11, green: 0.35, blue: 0.85, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 56, weight: .semibold),
                                                        .foregroundColor: UIColor.white]
            let text = letters as NSString
            let t = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: (size.width - t.width) / 2, y: (size.height - t.height) / 2), withAttributes: attrs)
        }
    }

    /// Reads what the app saved in the shared Keychain group ("session" token or "server" URL).
    private static func keychainValue(service: String) -> String? {
        guard let bundleID = info("QMBundleID") else { return nil }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(bundleID).\(service)",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let group = info("QMKeychainGroup") { query[kSecAttrAccessGroup as String] = group }
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
