import UIKit
@preconcurrency import UserNotifications

@main
final class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    nonisolated static let replyCategory = "CAN_REPLY"     // category the Mattermost server sets on message pushes
    nonisolated static let replyAction = "REPLY_ACTION"

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let reply = UNTextInputNotificationAction(identifier: Self.replyAction, title: "Reply", options: [],
                                                  textInputButtonTitle: "Send", textInputPlaceholder: "Message")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.replyCategory, actions: [reply], intentIdentifiers: [], options: []),
        ])
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default Configuration", sessionRole: session.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    /// A notification tap waiting for the main UI (cold launch, or still on the login screen).
    var pendingOpen: (channelId: String, rootId: String?)?

    func openPendingConversation() {
        guard let pending = pendingOpen, let root = Router.shared.root, AppSession.shared.isLoggedIn else { return }
        pendingOpen = nil
        root.view.window?.endEditing(true)
        if rootIsBusy(root) { root.dismiss(animated: false) }
        root.openConversation(channelId: pending.channelId, rootId: pending.rootId, focusComposer: false)
    }

    private func rootIsBusy(_ root: UIViewController) -> Bool { root.presentedViewController != nil }

    // MARK: Push registration

    /// Called after login (and on every launch while logged in) so the current session gets the device ID.
    func registerForPushNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        let client = AppSession.shared.client
        Task { try? await client.attachDevice(apnsTokenHex: hex) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("APNs registration failed: \(error)")
    }

    /// Silent pushes: the server sends `type: clear` when a channel is read on another device.
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        if (userInfo["type"] as? String) == "clear", let channelId = userInfo["channel_id"] as? String {
            AppSession.shared.clearNotifications(channelId: channelId)
            return .newData
        }
        return .noData
    }

    // MARK: Notification handling

    // These use the completion-handler forms on purpose: UIKit requires the handler to be called on
    // the main thread, and the `async` forms return on a background thread (which crashes on tap).

    /// Foreground: the app shows its own in-app banner for DMs and mentions, so the system one stays quiet.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        nonisolated(unsafe) let done = completionHandler
        DispatchQueue.main.async { done([]) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        nonisolated(unsafe) let done = completionHandler
        let info = response.notification.request.content.userInfo
        let channelId = info["channel_id"] as? String
        let rootId = (info["root_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let postId = info["post_id"] as? String
        let replyText = (response as? UNTextInputNotificationResponse)?.userText
        let isReply = response.actionIdentifier == Self.replyAction

        Task { @MainActor in
            defer { done() }
            guard let channelId else { return }
            if isReply, let text = replyText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Inline reply: send without opening the UI. Replies in a thread go to the thread root.
                let client = AppSession.shared.client
                _ = try? await client.createPost(channelId: channelId, message: text, rootId: rootId ?? postId)
                try? await client.markChannelViewed(channelId: channelId)
                return
            }
            // Plain tap: open the conversation with the keyboard closed. On a cold launch the UI may
            // not exist yet, so the request waits until it does.
            self.pendingOpen = (channelId, rootId)
            self.openPendingConversation()
        }
    }
}

extension Notification.Name {
    static let openConversation = Notification.Name("Quarkmost.openConversation")
}
