import UIKit
import SafariServices

/// One place every screen uses to navigate: open a channel, a thread, a permalink, a profile.
@MainActor
final class Router {
    static let shared = Router()
    weak var root: RootSplitViewController?

    func openChannel(_ channelId: String, focusComposer: Bool = false) {
        dismissModals { self.root?.openConversation(channelId: channelId, rootId: nil, focusComposer: focusComposer) }
    }

    func openThread(channelId: String, rootId: String) {
        dismissModals { self.root?.openConversation(channelId: channelId, rootId: rootId, focusComposer: false) }
    }

    /// A post from search, mentions, saved or a permalink: replies open their thread; channel posts
    /// open the permalink view with "Jump to recent messages", like the official app.
    func openPost(_ post: Post) {
        if post.isReply { openThread(channelId: post.channelId, rootId: post.rootId); return }
        openPermalink(postId: post.id)
    }

    func openPermalink(postId: String) {
        let vc = PermalinkViewController(postId: postId)
        top?.present(vc.wrappedForModal(), animated: true)
    }

    func showDetail(_ vc: UIViewController) {
        dismissModals { self.root?.showDetail(vc) }
    }

    func showProfile(userId: String, channelId: String? = nil) {
        let vc = UserProfileViewController(userId: userId, channelId: channelId)
        top?.present(vc, animated: true)
    }

    func showProfile(username: String, channelId: String? = nil) {
        if let user = AppSession.shared.user(username: username) { showProfile(userId: user.id, channelId: channelId); return }
        Task {
            guard let user = try? await AppSession.shared.client.user(username: username) else { return }
            AppSession.shared.cache([user])
            showProfile(userId: user.id, channelId: channelId)
        }
    }

    /// Opens a DM with someone, creating it if needed.
    func openDirect(userId: String) {
        Task {
            do { openChannel(try await AppSession.shared.openDirect(with: [userId]).id) }
            catch { top?.showError(error) }
        }
    }

    func openChannel(named name: String) {
        if let channel = AppSession.shared.channel(named: name) { openChannel(channel.id); return }
        top?.showToast("You're not a member of ~\(name)")
    }

    /// Links: permalinks and channel links on our own server stay in the app; the rest open in Safari.
    func open(url: URL) {
        if url.host == ServerConfig.baseURL.host {
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.count >= 3, parts[1] == "pl" { openPermalink(postId: parts[2]); return }
            if parts.count >= 3, parts[1] == "channels" { openChannel(named: parts[2]); return }
            if parts.count >= 3, parts[1] == "messages", parts[2].hasPrefix("@") {
                showProfile(username: String(parts[2].dropFirst())); return
            }
        }
        if url.scheme?.hasPrefix("http") == true {
            let safari = SFSafariViewController(url: url)
            safari.preferredControlTintColor = Theme.current.linkColor
            top?.present(safari, animated: true)
        } else {
            UIApplication.shared.open(url)
        }
    }

    func search(_ terms: String) {
        dismissModals { self.root?.homeTabs.showSearch(terms: terms) }
    }

    var top: UIViewController? {
        var vc: UIViewController? = root
        while let presented = vc?.presentedViewController, !presented.isBeingDismissed { vc = presented }
        return vc
    }

    private func dismissModals(then run: @escaping () -> Void) {
        if let root, root.presentedViewController != nil { root.dismiss(animated: true, completion: run) } else { run() }
    }
}
