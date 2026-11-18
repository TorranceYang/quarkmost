import UIKit

/// Threads (`screens/global_threads`): "All Your Threads" / "Unreads", each with the root message,
/// its channel, and reply counts. Unread threads show a dot or a mention badge.
final class ThreadsListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let table = UITableView(frame: .zero, style: .plain)
    private let tabs = FlatTabs(["All Your Threads", "Unreads"])
    private var threads: [UserThread] = []
    private var loading = false
    private var reachedEnd = false
    private var unreadOnly: Bool { tabs.selectedIndex == 1 }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Threads"
        let theme = Theme.current
        view.backgroundColor = theme.centerChannelBg
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: CompassIcon.image("playlist-check".ifKnown("check-all"), size: 24),
            primaryAction: UIAction { [weak self] _ in self?.markAllRead() })
        navigationItem.rightBarButtonItem?.accessibilityLabel = "Mark all as read"
        tabs.onChange = { [weak self] _ in self?.reload() }
        tabs.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = .clear
        table.separatorColor = theme.centerChannelColor.opacity(0.08)
        table.separatorInset = .zero
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 110
        table.dataSource = self
        table.delegate = self
        table.register(ThreadCell.self, forCellReuseIdentifier: "thread")
        table.refreshControl = UIRefreshControl(frame: .zero, primaryAction: UIAction { [weak self] _ in self?.reload() })
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabs)
        view.addSubview(table)
        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            tabs.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            tabs.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            table.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 12),
            table.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        NotificationCenter.default.addObserver(forName: .threadsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload(silent: true) }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        reload(silent: !threads.isEmpty)
    }

    private func reload(silent: Bool = false) {
        guard let me = AppSession.shared.me, let team = AppSession.shared.team else { return }
        if !silent { threads = []; table.reloadData(); table.backgroundView = nil }
        reachedEnd = false
        let unread = unreadOnly
        Task {
            let list = try? await AppSession.shared.client.threads(userId: me.id, teamId: team.id, unreadOnly: unread)
            guard unread == unreadOnly else { return }
            threads = list?.threads ?? []
            reachedEnd = threads.count < 25
            await AppSession.shared.loadUsers(threads.map(\.post.userId))
            table.reloadData()
            table.refreshControl?.endRefreshing()
            showEmptyIfNeeded()
        }
    }

    private func loadMore() {
        guard !loading, !reachedEnd, let last = threads.last, let me = AppSession.shared.me, let team = AppSession.shared.team else { return }
        loading = true
        Task {
            defer { loading = false }
            let more = (try? await AppSession.shared.client.threads(userId: me.id, teamId: team.id, unreadOnly: unreadOnly, before: last.id))?.threads ?? []
            reachedEnd = more.count < 25
            await AppSession.shared.loadUsers(more.map(\.post.userId))
            threads += more
            table.reloadData()
        }
    }

    private func showEmptyIfNeeded() {
        guard threads.isEmpty else { table.backgroundView = nil; return }
        let theme = Theme.current
        var config = UIContentUnavailableConfiguration.empty()
        config.image = CompassIcon.image("message-text-outline", size: 72)
        config.imageProperties.tintColor = theme.buttonBg.opacity(0.48)
        config.text = unreadOnly ? "No unread threads" : "No followed threads yet"
        config.textProperties.font = Typography.style(.heading, 400).font
        config.textProperties.color = theme.centerChannelColor
        config.secondaryText = unreadOnly ? "Looks like you're all caught up."
            : "Any threads you are mentioned in or have participated in will show here along with any threads you have followed."
        config.secondaryTextProperties.font = Typography.style(.body, 200).font
        config.secondaryTextProperties.color = theme.centerChannelColor.opacity(0.72)
        table.backgroundView = UIContentUnavailableView(configuration: config)
    }

    private func markAllRead() {
        confirm(title: "Are you sure you want to mark all threads as read?",
                message: "This will clear any unread status for all of your threads shown here", action: "Mark read", destructive: false) { [weak self] in
            guard let me = AppSession.shared.me, let team = AppSession.shared.team else { return }
            Task {
                try? await AppSession.shared.client.markAllThreadsRead(userId: me.id, teamId: team.id)
                AppSession.shared.refreshThreadTotals()
                self?.reload()
            }
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { threads.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "thread", for: indexPath) as! ThreadCell
        cell.configure(threads[indexPath.row])
        if indexPath.row >= threads.count - 5 { loadMore() }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let thread = threads[indexPath.row]
        threads[indexPath.row].unreadReplies = 0
        threads[indexPath.row].unreadMentions = 0
        tableView.reloadRows(at: [indexPath], with: .none)
        let vc = ConversationViewController(channelId: thread.post.channelId, title: nil, rootId: thread.id)
        navigationController?.pushViewController(vc, animated: true)
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let thread = threads[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            UIMenu(children: [
                UIAction(title: "Open in Channel", image: CompassIcon.image("globe", size: 24)) { _ in
                    Router.shared.openChannel(thread.post.channelId)
                },
                UIAction(title: "Mark as Read", image: CompassIcon.image("mark-as-unread", size: 24)) { [weak self] _ in
                    guard let me = AppSession.shared.me, let team = AppSession.shared.team else { return }
                    Task {
                        try? await AppSession.shared.client.markThreadRead(userId: me.id, teamId: team.id, threadId: thread.id,
                                                                           timestamp: Int64(Date().timeIntervalSince1970 * 1000))
                        AppSession.shared.refreshThreadTotals()
                        self?.reload(silent: true)
                    }
                },
                UIAction(title: "Unfollow Thread", image: CompassIcon.image("message-minus-outline", size: 24)) { [weak self] _ in
                    guard let me = AppSession.shared.me, let team = AppSession.shared.team else { return }
                    Task {
                        try? await AppSession.shared.client.setFollowing(false, userId: me.id, teamId: team.id, threadId: thread.id)
                        self?.reload(silent: true)
                    }
                },
                UIAction(title: "Copy Link", image: CompassIcon.image("link-variant", size: 24)) { _ in
                    UIPasteboard.general.string = PostActions.permalink(thread.post)
                },
            ])
        }
    }
}

final class ThreadCell: UITableViewCell {
    private let dot = UIView()
    private let badge = UILabel()
    private let avatar = AvatarView(size: 24)
    private let name = UILabel()
    private let channelTag = PaddedTag("")
    private let time = UILabel()
    private let message = UILabel()
    private let footer = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        let bg = UIView()
        bg.backgroundColor = Theme.current.centerChannelColor.opacity(0.08)
        selectedBackgroundView = bg
        message.numberOfLines = 2
        dot.layer.cornerRadius = 4
        badge.textAlignment = .center
        badge.layer.cornerRadius = 9
        badge.layer.masksToBounds = true
        let headerRow = UIStackView(arrangedSubviews: [avatar, name, channelTag, UIView(), time])
        headerRow.spacing = 8
        headerRow.alignment = .center
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        time.setContentCompressionResistancePriority(.required, for: .horizontal)
        let column = UIStackView(arrangedSubviews: [headerRow, message, footer])
        column.axis = .vertical
        column.spacing = 6
        column.translatesAutoresizingMaskIntoConstraints = false
        [dot, badge].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview($0) }
        contentView.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            column.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            column.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 36),
            column.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            dot.centerXAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            dot.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            dot.widthAnchor.constraint(equalToConstant: 8), dot.heightAnchor.constraint(equalToConstant: 8),
            badge.centerXAnchor.constraint(equalTo: dot.centerXAnchor), badge.centerYAnchor.constraint(equalTo: dot.centerYAnchor),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 18), badge.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ thread: UserThread) {
        let theme = Theme.current
        let session = AppSession.shared
        let post = thread.post
        let user = session.user(post.userId)
        avatar.setUser(post.userId, pictureUpdate: user?.lastPictureUpdate,
                       overrideURL: post.overrideIconURL.flatMap { URL(string: $0, relativeTo: ServerConfig.baseURL)?.absoluteURL })
        name.attributedText = NSAttributedString(string: post.overrideUsername ?? session.displayName(user),
                                                 attributes: Typography.style(.body, 200, .semibold).attributes(color: theme.centerChannelColor))
        channelTag.text = session.channel(post.channelId).map(session.title(for:))?.uppercased() ?? ""
        channelTag.isHidden = (channelTag.text ?? "").isEmpty
        channelTag.invalidateIntrinsicContentSize()
        let last = Date(timeIntervalSince1970: TimeInterval(max(thread.lastReplyAt, post.createAt)) / 1000)
        time.attributedText = NSAttributedString(string: Formatters.relative(last),
                                                 attributes: Typography.style(.body, 75).attributes(color: theme.centerChannelColor.opacity(0.64)))
        let plain = post.message.isEmpty ? (post.attachments.first?.title ?? post.attachments.first?.text ?? "Attachment") : post.message
        var attrs = Typography.style(.body, 200).attributes(color: theme.centerChannelColor)
        if let p = (attrs[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle {
            p.lineBreakMode = .byTruncatingTail
            attrs[.paragraphStyle] = p
        }
        message.attributedText = NSAttributedString(string: plain.replacingOccurrences(of: "\n", with: " "), attributes: attrs)
        let unread = thread.unreadReplies > 0
        let text = unread ? "\(thread.unreadReplies) new \(thread.unreadReplies == 1 ? "reply" : "replies")"
            : "\(thread.replyCount) \(thread.replyCount == 1 ? "reply" : "replies")"
        footer.attributedText = NSAttributedString(string: text, attributes: Typography.style(.body, 75, .semibold)
            .attributes(color: unread ? theme.buttonBg : theme.centerChannelColor.opacity(0.64)))
        dot.isHidden = !(unread && thread.unreadMentions == 0)
        dot.backgroundColor = theme.sidebarTextActiveBorder
        badge.isHidden = thread.unreadMentions == 0
        badge.text = " \(thread.unreadMentions) "
        badge.font = UIFont(name: "OpenSans-Bold", size: 11)
        badge.backgroundColor = theme.buttonBg
        badge.textColor = theme.buttonColor
        accessibilityLabel = "\(name.text ?? ""), \(plain), \(text)"
    }
}

/// Drafts (`screens/global_drafts`): every unsent draft; tap to open where it belongs.
final class DraftsViewController: StackScreenViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Drafts"
        NotificationCenter.default.addObserver(forName: .draftsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.build() }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        build()
    }

    private func build() {
        clear()
        let session = AppSession.shared
        let drafts = session.allDrafts
        if drafts.isEmpty {
            addPadded(UILabel("No drafts at the moment", Typography.style(.heading, 400), color: Theme.current.centerChannelColor), top: 48, bottom: 8)
            addText("Any message you have started will show here.", style: Typography.style(.body, 200))
            return
        }
        for d in drafts {
            let name = session.channel(d.channelId).map(session.title(for:)) ?? "Channel"
            let row = MenuRow(icon: "pencil-outline", title: d.message, subtitle: d.rootId.isEmpty ? "In: \(name)" : "Thread in: \(name)",
                              accessory: .chevron) {
                if d.rootId.isEmpty { Router.shared.openChannel(d.channelId, focusComposer: true) }
                else { Router.shared.openThread(channelId: d.channelId, rootId: d.rootId) }
            }
            row.titleLabel.numberOfLines = 3
            let delete = UIContextMenuInteraction(delegate: DraftMenu.shared)
            row.addInteraction(delete)
            row.accessibilityIdentifier = "\(d.channelId)/\(d.rootId)"
            stack.addArrangedSubview(row)
        }
        addText("Long-press on an item to see draft actions", style: Typography.style(.body, 75), alpha: 0.48)
    }
}

@MainActor
final class DraftMenu: NSObject, UIContextMenuInteractionDelegate {
    static let shared = DraftMenu()
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let key = interaction.view?.accessibilityIdentifier else { return nil }
        let parts = key.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            UIMenu(children: [UIAction(title: "Delete draft", image: CompassIcon.image("trash-can-outline", size: 24), attributes: .destructive) { _ in
                AppSession.shared.setDraft("", channelId: parts[0], rootId: parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil)
            }])
        }
    }
}
