import UIKit

/// Navigation controller for the app's solid-color header. iOS 26+ wraps bar buttons in Liquid Glass
/// bubbles, which are designed for translucent bars and look like grey blobs on ours; the official
/// app uses flat icons. This strips the glass from every bar button and supplies a flat back chevron,
/// keeping the swipe-back gesture.
final class ThemedNavigationController: UINavigationController, UINavigationControllerDelegate, UIGestureRecognizerDelegate {
    private static let backTag = 0xBAC

    /// On the iPhone Duo the status bar is a column at the side. The header stops where that column
    /// begins: this covers the bar's background there with the chat color, under the bar's buttons.
    private let columnCover = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        applyThemedBar()
        interactivePopGestureRecognizer?.delegate = self
        columnCover.isUserInteractionEnabled = false
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The Duo reports its status column as a side safe-area inset (~84pt; a landscape notch is ≤62).
        let insets = view.safeAreaInsets
        let bar = navigationBar
        var cover = CGRect.zero
        if insets.right >= 70 {
            cover = CGRect(x: bar.bounds.width - insets.right, y: -bar.frame.minY, width: insets.right, height: bar.frame.maxY)
        } else if insets.left >= 70 {
            cover = CGRect(x: 0, y: -bar.frame.minY, width: insets.left, height: bar.frame.maxY)
        }
        if cover.isEmpty || isNavigationBarHidden {
            columnCover.removeFromSuperview()
        } else {
            // Index 1: above the bar's background view, below its title and buttons.
            if columnCover.superview !== bar || bar.subviews.firstIndex(of: columnCover) != 1 {
                bar.insertSubview(columnCover, at: min(1, bar.subviews.count))
            }
            columnCover.frame = cover
            columnCover.backgroundColor = Theme.current.centerChannelBg
        }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        view.setNeedsLayout()
    }

    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        view.setNeedsLayout()
    }

    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        flatten(viewController)
    }

    /// Call again after a screen replaces its bar buttons.
    func flatten(_ vc: UIViewController) {
        let item = vc.navigationItem
        let isRoot = viewControllers.first === vc
        // Collapsed split view: the detail stack's first screen still needs a way back to the list.
        let collapsedDetail = isRoot && splitViewController?.isCollapsed == true
            && splitViewController?.viewController(for: .secondary) === self
        if item.leftBarButtonItem == nil || item.leftBarButtonItem?.tag == Self.backTag {
            if (!isRoot || collapsedDetail) && !item.hidesBackButton {
                let back = UIBarButtonItem(image: CompassIcon.image("arrow-back-ios", size: 24), primaryAction: UIAction { [weak self] _ in
                    guard let self else { return }
                    if viewControllers.count > 1 { popViewController(animated: true) }
                    else { splitViewController?.show(.primary) }
                })
                back.tag = Self.backTag
                back.accessibilityLabel = "Back"
                item.leftBarButtonItem = back
            } else if item.leftBarButtonItem?.tag == Self.backTag {
                item.leftBarButtonItem = nil
            }
        }
        let tint = Theme.current.sidebarHeaderTextColor
        for button in (item.leftBarButtonItems ?? []) + (item.rightBarButtonItems ?? []) {
            // Without the glass, items no longer pick up the bar's tint; set it on each one.
            button.tintColor = tint
            if #available(iOS 26.0, *) { button.hidesSharedBackground = true }
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}

extension UIViewController {
    /// Re-applies the flat button style after changing `navigationItem` buttons on a visible screen.
    func refreshBarButtons() {
        (navigationController as? ThemedNavigationController)?.flatten(self)
    }
}

