import UIKit

extension PostInput {
    /// Gathers what a post needs for layout from the session (names, avatar, time format, saved state).
    @MainActor
    static func make(_ post: Post, consecutive: Bool, highlighted: Bool = false, failed: Bool = false) -> PostInput {
        let session = AppSession.shared
        let user = session.user(post.userId)
        var name = post.overrideUsername ?? session.displayName(user)
        var avatar: URL? = ImageLoader.profileImageURL(userId: post.userId, lastPictureUpdate: user?.lastPictureUpdate)
        if let icon = post.overrideIconURL {
            avatar = URL(string: icon, relativeTo: ServerConfig.baseURL)?.absoluteURL ?? avatar
        }
        if post.isSystemMessage { name = "System"; avatar = nil }
        let date = Date(timeIntervalSince1970: TimeInterval(post.createAt) / 1000)
        var input = PostInput(post: post, consecutive: consecutive, displayName: name,
                              isBot: (user?.isBot ?? false) || post.fromWebhook || post.fromBot,
                              avatarURL: avatar, time: Formatters.time(date), myUserId: session.me?.id ?? "")
        input.isSaved = session.savedPostIds.contains(post.id)
        input.highlighted = highlighted
        input.failed = failed
        input.following = post.isFollowing ?? false
        input.useImageProxy = session.config["HasImageProxy"] == "true"
        return input
    }
}

@MainActor
enum Formatters {
    private static let twelve: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h:mm a"; return f }()
    private static let twentyFour: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()

    static func time(_ date: Date) -> String {
        (AppSession.shared.uses24HourClock ? twentyFour : twelve).string(from: date)
    }

    static func day(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate(cal.isDate(date, equalTo: Date(), toGranularity: .year) ? "MMM d" : "MMM d, yyyy")
        return f.string(from: date)
    }

    /// "5m", "3h", "Yesterday", "Nov 3": the compact form used in the threads list.
    static func relative(_ date: Date) -> String {
        let s = Date().timeIntervalSince(date)
        if s < 60 { return "Now" }
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86400 { return "\(Int(s / 3600))h" }
        return day(date)
    }
}

/// A plain (non-inverted) list of posts with their channel names: Recent Mentions, Saved Messages,
/// Pinned Messages and search results (`components/post_with_channel_info`).
class PostResultsViewController: UIViewController, UICollectionViewDelegate {
    struct EmptyState { let icon: String; let title: String; let text: String }

    private enum Item: Hashable { case channel(String), date(String), post(String) }

    var loader: () async throws -> [Post]
    var emptyState: EmptyState
    var showsChannel = true
    var highlightedPostId: String?
    var headerTitle: String?
    var onLoaded: (([Post]) -> Void)?

    private let session = AppSession.shared
    private(set) var collectionView: UICollectionView!
    private let listLayout = MessageListLayout()
    private var dataSource: UICollectionViewDiffableDataSource<Int, Item>!
    private var posts: [Post] = []
    private var layouts: [String: PostLayout] = [:]
    private var labels: [String: String] = [:]
    private var layoutWidth: CGFloat = 0
    private var generation = 0
    private var header: TabHeaderView?
    private var loadTask: Task<Void, Never>?

    init(title: String?, emptyState: EmptyState, loader: @escaping () async throws -> [Post]) {
        self.loader = loader
        self.emptyState = emptyState
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    static func mentions() -> PostResultsViewController {
        let vc = PostResultsViewController(
            title: "Recent Mentions",
            emptyState: .init(icon: "at", title: "No Mentions yet",
                              text: "You'll see messages here when someone mentions you or uses terms you're monitoring.")) {
            let s = AppSession.shared
            guard let team = s.team else { return [] }
            let terms = s.mentionKeys.joined(separator: " ")
            return try await s.client.searchPosts(teamId: team.id, terms: terms, isOrSearch: true).orderedPosts
        }
        vc.headerTitle = "Recent Mentions"
        return vc
    }

    static func saved() -> PostResultsViewController {
        let vc = PostResultsViewController(
            title: "Saved Messages",
            emptyState: .init(icon: "bookmark-outline", title: "No saved messages yet",
                              text: "To save something for later, long-press on a message and choose Save from the menu. Saved messages are only visible to you.")) {
            let s = AppSession.shared
            guard let me = s.me, let team = s.team else { return [] }
            return try await s.client.flaggedPosts(userId: me.id, teamId: team.id).orderedPosts
        }
        vc.headerTitle = "Saved Messages"
        return vc
    }

    static func pinned(channelId: String) -> PostResultsViewController {
        let vc = PostResultsViewController(
            title: "Pinned Messages",
            emptyState: .init(icon: "pin-outline", title: "No pinned messages yet",
                              text: "To pin important messages, long-press on a message and choose Pin To Channel. Pinned messages will be visible to everyone in this channel.")) {
            try await AppSession.shared.client.pinnedPosts(channelId: channelId).orderedPosts
        }
        vc.showsChannel = false
        return vc
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let theme = Theme.current
        view.backgroundColor = theme.centerChannelBg
        listLayout.heightForItem = { [weak self] indexPath in self?.height(at: indexPath) ?? 0 }
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: listLayout)
        collectionView.backgroundColor = theme.centerChannelBg
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .onDrag
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.refreshControl = UIRefreshControl(frame: .zero, primaryAction: UIAction { [weak self] _ in self?.reload() })
        collectionView.refreshControl?.tintColor = theme.centerChannelColor.opacity(0.48)
        view.addSubview(collectionView)

        var top = view.safeAreaLayoutGuide.topAnchor
        if let headerTitle {
            let header = TabHeaderView(title: headerTitle)
            header.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(header)
            NSLayoutConstraint.activate([
                header.topAnchor.constraint(equalTo: view.topAnchor),
                header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
            top = header.bottomAnchor
            self.header = header
        }
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: top),
            collectionView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let postCell = UICollectionView.CellRegistration<PostCell, String> { [weak self] cell, _, id in
            guard let self, let layout = layouts[id] else { return }
            cell.flipped = false
            cell.configure(layout, theme: Theme.current)
            cell.onTap = { [weak self] post in self?.open(post) }
            cell.onOpenThread = { post in Router.shared.openThread(channelId: post.channelId, rootId: post.id) }
            cell.onTapTarget = { key, value in PostActions.openTarget(key, value, channelId: layout.post.channelId) }
            cell.onTapAvatar = { post in Router.shared.showProfile(userId: post.userId, channelId: post.channelId) }
            cell.onTapFile = { [weak self] _, file in if let self { FilePreviewer.open(file, from: self) } }
            cell.onOpenImage = { [weak self] post, index in
                if let self { PostActions.openMedia(layout, index: index, from: self) }
            }
            cell.onLongPress = { [weak self] post in self?.showOptions(post) }
            cell.onToggleReaction = { _, _ in }
            cell.onAddReaction = { _ in }
        }
        let dateCell = UICollectionView.CellRegistration<DateSeparatorCell, String> { [weak self] cell, _, key in
            cell.flipped = false
            cell.configure(self?.labels[key] ?? "", theme: Theme.current)
        }
        let channelCell = UICollectionView.CellRegistration<ChannelInfoCell, String> { [weak self] cell, _, key in
            cell.configure(self?.labels[key] ?? "")
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, indexPath, item in
            switch item {
            case .post(let id): cv.dequeueConfiguredReusableCell(using: postCell, for: indexPath, item: id)
            case .date(let key): cv.dequeueConfiguredReusableCell(using: dateCell, for: indexPath, item: key)
            case .channel(let key): cv.dequeueConfiguredReusableCell(using: channelCell, for: indexPath, item: key)
            }
        }
        NotificationCenter.default.addObserver(forName: CustomEmojiStore.didLoad, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layouts = [:]; self?.rebuild() }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if collectionView.bounds.width > 0, collectionView.bounds.width != layoutWidth, !posts.isEmpty { rebuild() }
    }

    func reload() {
        loadTask?.cancel()
        if posts.isEmpty { contentUnavailableConfiguration = UIContentUnavailableConfiguration.loading() }
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await loader()
                guard !Task.isCancelled else { return }
                await session.loadUsers(result.map(\.userId))
                posts = result.filter { $0.deleteAt == 0 }
                onLoaded?(posts)
                layouts = [:]
                rebuild()
            } catch is CancellationError {
            } catch {
                showEmpty(title: "Something went wrong", text: (error as? APIError)?.message ?? error.localizedDescription,
                          icon: "alert-circle-outline")
            }
            collectionView.refreshControl?.endRefreshing()
        }
    }

    func setPosts(_ new: [Post]) {
        posts = new
        layouts = [:]
        rebuild()
    }

    private func rebuild() {
        let width = collectionView.bounds.width
        guard width > 0 else { return }
        generation += 1
        let gen = generation
        var items: [Item] = []
        var inputs: [PostInput] = []
        var lastDay: String?
        let keyFormatter = DateFormatter()
        keyFormatter.dateFormat = "yyyy-MM-dd"
        for post in posts {
            let date = Date(timeIntervalSince1970: TimeInterval(post.createAt) / 1000)
            if showsChannel {
                let key = "c-\(post.id)"
                let name = session.channel(post.channelId).map(session.title(for:)) ?? "Channel"
                labels[key] = post.isReply ? "\(name)  ·  Thread" : name
                let dayKey = "d-" + keyFormatter.string(from: date)
                if dayKey != lastDay {
                    labels[dayKey] = Formatters.day(date)
                    items.append(.date(dayKey))
                    lastDay = dayKey
                }
                items.append(.channel(key))
            }
            items.append(.post(post.id))
            if layouts[post.id] == nil || width != layoutWidth {
                var input = PostInput.make(post, consecutive: false, highlighted: post.id == highlightedPostId)
                input.expanded = true
                inputs.append(input)
            }
        }
        let style = RenderStyle.current(myUsername: session.me?.username ?? "")
        Task.detached(priority: .userInitiated) { [inputs] in
            let built = inputs.map { PostLayoutBuilder.layout($0, width: width, style: style) }
            await MainActor.run { [weak self] in
                guard let self, gen == self.generation else { return }
                for l in built { self.layouts[l.id] = l }
                let widthChanged = self.layoutWidth != width
                self.layoutWidth = width
                var snapshot = NSDiffableDataSourceSnapshot<Int, Item>()
                snapshot.appendSections([0])
                snapshot.appendItems(items)
                snapshot.reconfigureItems(items)
                if widthChanged { self.listLayout.invalidateLayout() }
                self.dataSource.apply(snapshot, animatingDifferences: false)
                if self.posts.isEmpty {
                    self.showEmpty(title: self.emptyState.title, text: self.emptyState.text, icon: self.emptyState.icon)
                } else {
                    self.contentUnavailableConfiguration = nil
                    if let id = self.highlightedPostId, let ip = self.dataSource.indexPath(for: .post(id)) {
                        self.collectionView.scrollToItem(at: ip, at: .centeredVertically, animated: false)
                    }
                }
            }
        }
    }

    private func showEmpty(title: String, text: String, icon: String) {
        let theme = Theme.current
        var config = UIContentUnavailableConfiguration.empty()
        config.image = CompassIcon.image(icon, size: 72)
        config.imageProperties.tintColor = theme.buttonBg.opacity(0.48)
        config.text = title
        config.textProperties.font = Typography.style(.heading, 400).font
        config.textProperties.color = theme.centerChannelColor
        config.secondaryText = text
        config.secondaryTextProperties.font = Typography.style(.body, 200).font
        config.secondaryTextProperties.color = theme.centerChannelColor.opacity(0.72)
        contentUnavailableConfiguration = config
    }

    private func height(at indexPath: IndexPath) -> CGFloat {
        guard let item = dataSource?.itemIdentifier(for: indexPath) else { return 0 }
        switch item {
        case .post(let id): return layouts[id]?.height ?? 44
        case .date: return DateSeparatorCell.height
        case .channel: return 28
        }
    }

    func open(_ post: Post) { Router.shared.openPost(post) }

    private func showOptions(_ post: Post) {
        let saved = session.savedPostIds.contains(post.id)
        var options: [PostOptionsViewController.Option] = [
            .init(icon: "reply-outline", title: "Reply") {
                Router.shared.openThread(channelId: post.channelId, rootId: post.rootId.isEmpty ? post.id : post.rootId)
            },
            .init(icon: "link-variant", title: "Copy Link") { [weak self] in
                UIPasteboard.general.string = PostActions.permalink(post)
                self?.showToast("Link copied")
            },
        ]
        if !post.message.isEmpty {
            options.append(.init(icon: "content-copy", title: "Copy Text") { [weak self] in
                UIPasteboard.general.string = post.message
                self?.showToast("Copied to clipboard")
            })
        }
        options.append(.init(icon: saved ? "bookmark" : "bookmark-outline", title: saved ? "Unsave" : "Save") { [weak self] in
            AppSession.shared.setSaved(!saved, postId: post.id)
            self?.showToast(saved ? "Removed from saved messages" : "Message saved")
            self?.layouts[post.id] = nil
            self?.rebuild()
        })
        presentOptions(options)
    }

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool { false }
}

/// Channel name above a result: 12pt SemiBold at 64%.
final class ChannelInfoCell: UICollectionViewCell {
    private let label = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(label)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
    func configure(_ text: String) {
        label.attributedText = NSAttributedString(string: text, attributes:
            Typography.style(.body, 75, .semibold).attributes(color: Theme.current.centerChannelColor.opacity(0.64)))
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = CGRect(x: PostLayout.side, y: 10, width: bounds.width - 32, height: 16)
    }
}

/// The official permalink modal: the post with a few messages around it, and "Jump to recent messages".
final class PermalinkViewController: PostResultsViewController {
    private let postId: String
    private var channelId: String?

    init(postId: String) {
        self.postId = postId
        super.init(title: "Message",
                   emptyState: .init(icon: "message-text-outline", title: "Message Not Found",
                                     text: "Permalink belongs to a deleted message or to a channel to which you do not have access.")) { [] }
        showsChannel = false
        highlightedPostId = postId
        loader = { [weak self] in
            let client = AppSession.shared.client
            let post = try await client.post(id: postId)
            async let before = try? client.posts(channelId: post.channelId, before: postId, perPage: 5)
            async let after = try? client.posts(channelId: post.channelId, after: postId, perPage: 5)
            var all = [post] + ((await before)?.orderedPosts ?? []) + ((await after)?.orderedPosts ?? [])
            all = all.filter { !$0.isReply || $0.id == postId }
            await MainActor.run { self?.setChannel(post.channelId) }
            return all.sorted { $0.createAt < $1.createAt }
        }
    }

    private func setChannel(_ id: String) {
        channelId = id
        if let channel = AppSession.shared.channel(id) { title = AppSession.shared.title(for: channel) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let theme = Theme.current
        var config = UIButton.Configuration.filled()
        config.title = "Jump to recent messages"
        config.baseBackgroundColor = theme.buttonBg
        config.baseForegroundColor = theme.buttonColor
        config.cornerStyle = .fixed
        config.background.cornerRadius = 4
        config.contentInsets = .init(top: 12, leading: 20, bottom: 12, trailing: 20)
        let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            guard let id = self?.channelId else { return }
            Router.shared.openChannel(id)
        })
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            button.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            button.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
        collectionView.contentInset.bottom = 72
    }

    override func open(_ post: Post) {
        if let id = channelId { Router.shared.openChannel(id) }
    }
}

/// Post-related actions shared by the conversation and the result lists.
@MainActor
enum PostActions {
    static func permalink(_ post: Post) -> String {
        let team = AppSession.shared.team?.name ?? ""
        return ServerConfig.baseURL.appendingPathComponent("\(team)/pl/\(post.id)").absoluteString
    }

    static func openTarget(_ key: NSAttributedString.Key, _ value: Any, channelId: String?) {
        switch key {
        case .link: if let url = value as? URL { Router.shared.open(url: url) }
        case .mentionUser:
            guard let name = value as? String, !["here", "channel", "all"].contains(name) else { return }
            Router.shared.showProfile(username: name, channelId: channelId)
        case .channelMention: if let name = value as? String { Router.shared.openChannel(named: name) }
        case .hashtag: if let tag = value as? String { Router.shared.search(tag) }
        default: break
        }
    }

    /// Images open the gallery; videos play in the system player (with the session token).
    static func openMedia(_ layout: PostLayout, index: Int, from presenter: UIViewController) {
        guard index < layout.images.count else { return }
        let item = layout.images[index]
        if item.isVideo {
            VideoPlayer.play(item.fullURL, from: presenter)
            return
        }
        let stills = layout.images.filter { !$0.isVideo }
        let start = stills.firstIndex { $0.fullURL == item.fullURL } ?? 0
        let session = AppSession.shared
        let name = layout.post.overrideUsername ?? session.displayName(session.user(layout.post.userId))
        presenter.present(GalleryViewController(urls: stills.map(\.fullURL), startIndex: start, author: name), animated: true)
    }
}

import AVKit

@MainActor
enum VideoPlayer {
    static func play(_ url: URL, from presenter: UIViewController) {
        Task {
            var headers = ["User-Agent": ServerConfig.userAgent]
            if let token = await AppSession.shared.client.token { headers["Authorization"] = "Bearer \(token)" }
            let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
            let controller = AVPlayerViewController()
            controller.player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            presenter.present(controller, animated: true) { controller.player?.play() }
        }
    }
}
