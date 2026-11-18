import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var root: RootSplitViewController?
    private var openObserver: NSObjectProtocol?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        self.window = window
        if AppSession.shared.isLoggedIn { showMain(animated: false) } else { showLogin(animated: false) }
        window.makeKeyAndVisible()

        openObserver = NotificationCenter.default.addObserver(forName: .openConversation, object: nil, queue: .main) {
            [weak self] note in
            guard let channelId = note.userInfo?["channelId"] as? String else { return }
            let rootId = note.userInfo?["rootId"] as? String
            MainActor.assumeIsolated {
                self?.root?.openConversation(channelId: channelId, rootId: rootId, focusComposer: false)
            }
        }
    }

    private func showMain(animated: Bool) {
        let root = RootSplitViewController()
        root.onLogout = { [weak self] in
            Task {
                await AppSession.shared.logout()
                self?.showLogin(animated: true)
            }
        }
        self.root = root
        setRoot(root, animated: animated)
        // Ask for push permission only once there's an account to attach the device to.
        (UIApplication.shared.delegate as? AppDelegate)?.registerForPushNotifications()
        (UIApplication.shared.delegate as? AppDelegate)?.openPendingConversation()
    }

    private func showLogin(animated: Bool) {
        let login = LoginViewController()
        login.onLoggedIn = { [weak self] in self?.showMain(animated: true) }
        root = nil
        setRoot(login, animated: animated)
    }

    private func setRoot(_ viewController: UIViewController, animated: Bool) {
        guard let window else { return }
        window.rootViewController = viewController
        if animated {
            UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve, animations: nil)
        }
    }
}
