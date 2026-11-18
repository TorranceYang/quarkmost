import UIKit

/// Home screen sidebar, matching the official app's `categories_list`:
/// team header, unread filter + "Find channels..." field, then collapsible categories.
final class ChannelListViewController: UIViewController {
    var onSelectChannel: ((SidebarChannel) -> Void)?
    var onThemeChange: (() -> Void)?

    /// Highlighted with the active style when shown side by side (Duo inner screen).
    var activeChannelId: String? { didSet { reconfigureVisible() } }

    private let session = AppSession.shared
    private let header = ChannelListHeaderView()
    private let subheader = ChannelListSubheaderView()
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<String, String>!
    private var rowsById: [String: SidebarChannel] = [:]
    private var sectionsById: [String: SidebarSection] = [:]
    private var onlyUnreads = false
    private var loadTask: Task<Void, Never>?
    private var appliedThemeJSON: String??

    private static let unreadsSection = "__unreads"

    private var theme: Theme { Theme.current }
    private var showsActive: Bool { splitViewController?.isCollapsed == false }

    override func viewDidLoad() {
        super.viewDidLoad()

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.contentInset.bottom = 16
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.refreshControl = UIRefreshControl(frame: .zero, primaryAction: UIAction { [weak self] _ in
            self?.reload()
        })

        header.translatesAutoresizingMaskIntoConstraints = false
        subheader.translatesAutoresizingMaskIntoConstraints = false
        header.onPlus = { [weak self] in self?.showPlusMenu() }
        subheader.onSearch = { [weak self] in
            self?.present(FindChannelsViewController().wrappedForModal(), animated: true)
        }
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(rowLongPressed(_:)))
        collectionView.addGestureRecognizer(longPress)
        subheader.onToggleUnreads = { [weak self] in self?.toggleUnreads() }
        view.addSubview(collectionView)
        view.addSubview(header)
        view.addSubview(subheader)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            header.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            subheader.topAnchor.constraint(equalTo: header.bottomAnchor),
            subheader.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            subheader.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: subheader.bottomAnchor),
            // Rows lay out by hand with fixed padding, so keep the list itself out of a vertical bar.
            collectionView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let channelCell = UICollectionView.CellRegistration<ChannelCell, String> { [weak self] cell, _, id in
            guard let self, let row = rowsById[id] else { return }
            let active = showsActive && row.id == activeChannelId
            var icon: String?
            if id == Self.threadsRow { icon = "message-text-outline" }
            else if id == Self.draftsRow { icon = "send-outline".ifKnown("pencil-outline") }
            else if !active, session.hasDraft(channelId: id) { icon = "pencil-outline" }
            cell.configure(row, theme: theme, active: active, iconOverride: icon)
        }
        let headerCell = UICollectionView.SupplementaryRegistration<CategoryHeaderView>(
            elementKind: UICollectionView.elementKindSectionHeader) { [weak self] view, _, indexPath in
            guard let self, let id = dataSource.sectionIdentifier(for: indexPath.section),
                  let section = sectionsById[id] else { return }
            view.configure(section, theme: theme)
            view.onTap = { [weak self] in self?.session.toggleCollapsed(categoryId: id) }
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, indexPath, id in
            cv.dequeueConfiguredReusableCell(using: channelCell, for: indexPath, item: id)
        }
        dataSource.supplementaryViewProvider = { cv, _, indexPath in
            cv.dequeueConfiguredReusableSupplementary(using: headerCell, for: indexPath)
        }

        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in
            self.collectionView.setCollectionViewLayout(self.makeLayout(), animated: false)
        }
        session.onSidebarChange = { [weak self] in self?.applySidebar() }
        applyTheme()
        applySidebar()
        reload()
    }

    static let threadsRow = "__threads"
    static let draftsRow = "__drafts"
    private static let topSection = "__top"

    private func pseudoRow(_ id: String, _ name: String, unread: Bool, mentions: Int) -> SidebarChannel {
        SidebarChannel(id: id, name: name, type: .open, unread: unread, mentions: mentions, muted: false, lastPostAt: 0,
                       teammateId: nil, teammatePictureUpdate: nil, teammateIsBot: false, teammateDeleted: false,
                       teammateStatus: nil, groupSize: 0)
    }

    /// The official "+" menu (`header/plus_menu`).
    private func showPlusMenu() {
        presentOptions([
            .init(icon: "globe", title: "Browse Channels") { [weak self] in
                self?.present(BrowseChannelsViewController().wrappedForModal(), animated: true)
            },
            .init(icon: "plus", title: "Create New Channel") { [weak self] in
                self?.present(CreateChannelViewController().wrappedForModal(), animated: true)
            },
            .init(icon: "account-outline", title: "Open a Direct Message") { [weak self] in
                self?.present(CreateDirectMessageViewController().wrappedForModal(), animated: true)
            },
        ])
    }

    /// Long-press a channel for its quick actions (`components/channel_actions`).
    @objc private func rowLongPressed(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, let indexPath = collectionView.indexPathForItem(at: g.location(in: collectionView)),
              let id = dataSource.itemIdentifier(for: indexPath), let channel = session.channel(id) else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        presentOptions(ChannelActions.options(for: channel, from: self), title: session.title(for: channel))
    }


    /// Folding/unfolding changes whether the active row is highlighted.
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.reconfigureVisible() }
    }

    func reload() {
        loadTask?.cancel()
        if session.sidebar.isEmpty { showLoading() }
        loadTask = Task { [weak self] in
            do {
                try await AppSession.shared.refreshSidebar()
                self?.contentUnavailableConfiguration = nil
            } catch is CancellationError {
            } catch {
                self?.showLoadError(error)
            }
            self?.collectionView.refreshControl?.endRefreshing()
        }
    }

    // MARK: Data

    private func applySidebar() {
        if appliedThemeJSON != .some(session.themeJSON) { applyTheme() }
        header.configure(team: session.team?.displayName ?? "", server: session.config["SiteName"].flatMap { $0.isEmpty || $0 == "Mattermost" ? nil : $0 } ?? AppInfo.displayName, theme: theme)

        let previous = rowsById
        rowsById = [:]
        sectionsById = [:]
        var snapshot = NSDiffableDataSourceSnapshot<String, String>()

        if onlyUnreads {
            let unread = session.sidebar.flatMap(\.channels).filter { $0.unread || $0.mentions > 0 }
                .sorted { $0.lastPostAt > $1.lastPostAt }
            snapshot.appendSections([Self.unreadsSection])
            snapshot.appendItems(unread.map(\.id))
            unread.forEach { rowsById[$0.id] = $0 }
        } else {
            // Threads and Drafts rows sit above the categories.
            // The Threads row only exists with collapsed reply threads, as in the official app.
            var top: [SidebarChannel] = session.collapsedThreads
                ? [pseudoRow(Self.threadsRow, "Threads", unread: session.unreadThreads > 0, mentions: session.unreadThreadMentions)] : []
            let draftCount = session.allDrafts.count
            if draftCount > 0 { top.append(pseudoRow(Self.draftsRow, "Drafts", unread: false, mentions: 0)) }
            if !top.isEmpty {
                snapshot.appendSections([Self.topSection])
                snapshot.appendItems(top.map(\.id), toSection: Self.topSection)
            }
            top.forEach { rowsById[$0.id] = $0 }

            // "Unreads" category on top when the sidebar preference asks for it.
            var hoisted = Set<String>()
            if session.preference("sidebar_settings", "show_unread_section") == "true" {
                let unread = session.sidebar.flatMap(\.channels).filter { $0.unread || $0.mentions > 0 }
                    .sorted { $0.lastPostAt > $1.lastPostAt }
                if !unread.isEmpty {
                    let s = SidebarSection(id: Self.unreadsSection, title: "Unreads", collapsed: false, muted: false, channels: unread)
                    sectionsById[s.id] = s
                    snapshot.appendSections([s.id])
                    snapshot.appendItems(unread.map(\.id), toSection: s.id)
                    unread.forEach { rowsById[$0.id] = $0 }
                    hoisted = Set(unread.map(\.id))
                }
            }
            for var section in session.sidebar {
                if !hoisted.isEmpty {
                    section = SidebarSection(id: section.id, title: section.title, collapsed: section.collapsed, muted: section.muted,
                                             channels: section.channels.filter { !hoisted.contains($0.id) })
                }
                sectionsById[section.id] = section
                snapshot.appendSections([section.id])
                // A collapsed category still shows its unread channels and the open one, like the official app.
                let visible = section.collapsed
                    ? section.channels.filter { $0.unread || $0.mentions > 0 || $0.id == activeChannelId }
                    : section.channels
                snapshot.appendItems(visible.map(\.id), toSection: section.id)
                visible.forEach { rowsById[$0.id] = $0 }
            }
        }
        // Rows whose content changed are reconfigured in place (no cell swap, no flicker).
        let changed = rowsById.filter { id, row in previous[id].map { $0 != row } ?? false }.map(\.key)
        let current = dataSource.snapshot()
        let unchanged = changed.isEmpty && current.sectionIdentifiers == snapshot.sectionIdentifiers
            && current.itemIdentifiers == snapshot.itemIdentifiers
        // Skipping no-op applies matters: an apply in the middle of a tap cancels the tap.
        if !unchanged {
            snapshot.reconfigureItems(changed.filter { snapshot.indexOfItem($0) != nil })
            dataSource.apply(snapshot, animatingDifferences: view.window != nil && !previous.isEmpty)
        }
        // Headers are updated in place so the chevron can animate.
        for indexPath in collectionView.indexPathsForVisibleSupplementaryElements(
            ofKind: UICollectionView.elementKindSectionHeader) {
            guard let id = dataSource.sectionIdentifier(for: indexPath.section), let section = sectionsById[id],
                  let view = collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionHeader,
                                                              at: indexPath) as? CategoryHeaderView else { continue }
            view.configure(section, theme: theme)
        }

        if snapshot.numberOfItems == 0 && onlyUnreads {
            var config = UIContentUnavailableConfiguration.empty()
            config.text = "No unreads"
            config.textProperties.color = theme.sidebarText.opacity(0.72)
            config.textProperties.font = Typography.style(.body, 200).font
            contentUnavailableConfiguration = config
        } else if !session.sidebar.isEmpty {
            contentUnavailableConfiguration = nil
        }
    }

    private func toggleUnreads() {
        onlyUnreads.toggle()
        subheader.setUnreadsOn(onlyUnreads, theme: theme)
        applySidebar()
    }

    private func reconfigureVisible() {
        guard let dataSource else { return }
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func applyTheme() {
        appliedThemeJSON = .some(session.themeJSON)
        Theme.current = session.themeJSON.flatMap(Theme.init(preferenceJSON:)) ?? .denim
        view.backgroundColor = theme.sidebarBg
        collectionView.refreshControl?.tintColor = theme.sidebarText.opacity(0.72)
        header.configure(team: session.team?.displayName ?? "", server: session.config["SiteName"].flatMap { $0.isEmpty || $0 == "Mattermost" ? nil : $0 } ?? AppInfo.displayName, theme: theme)
        subheader.setUnreadsOn(onlyUnreads, theme: theme)
        if dataSource != nil { reconfigureVisible() }
        onThemeChange?()
    }

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] index, environment in
            let sectionId = self?.dataSource?.sectionIdentifier(for: index)
            let scale = UIFontMetrics(forTextStyle: .body).scaledValue(for: 1, compatibleWith: environment.traitCollection)
            let rowHeight = max(40, (40 * scale).rounded())   // ROW_HEIGHT, grown for larger text sizes
            let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1),
                                                                heightDimension: .absolute(rowHeight)))
            let group = NSCollectionLayoutGroup.vertical(layoutSize: item.layoutSize, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: .init(widthDimension: .fractionalWidth(1),
                                  heightDimension: .absolute(CategoryHeaderView.height(scale: scale))),
                elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)
            if sectionId != Self.topSection && sectionId != Self.unreadsSection || (sectionId == Self.unreadsSection && self?.onlyUnreads == false) {
                section.boundarySupplementaryItems = [header]
            }
            return section
        }
    }

    // MARK: States

    private func showLoading() {
        var config = UIContentUnavailableConfiguration.loading()
        config.text = nil
        contentUnavailableConfiguration = config
    }

    private func showLoadError(_ error: Error) {
        guard session.sidebar.isEmpty else { return }   // keep showing stale data rather than an error
        var config = UIContentUnavailableConfiguration.empty()
        config.image = CompassIcon.image("alert-outline", size: 32)
        config.imageProperties.tintColor = theme.sidebarText.opacity(0.48)
        config.text = "Couldn't load channels"
        config.textProperties.color = theme.sidebarText
        config.textProperties.font = Typography.style(.heading, 300).font
        config.secondaryText = (error as? APIError)?.message ?? error.localizedDescription
        config.secondaryTextProperties.color = theme.sidebarText.opacity(0.64)
        config.secondaryTextProperties.font = Typography.style(.body, 100).font
        var retry = UIButton.Configuration.filled()
        retry.title = "Retry"
        retry.baseBackgroundColor = theme.buttonBg
        retry.baseForegroundColor = theme.buttonColor
        config.button = retry
        config.buttonProperties.primaryAction = UIAction { [weak self] _ in self?.reload() }
        contentUnavailableConfiguration = config
    }
}

extension ChannelListViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        guard let id = dataSource.itemIdentifier(for: indexPath), let row = rowsById[id] else { return }
        if id == Self.threadsRow {
            activeChannelId = id
            Router.shared.showDetail(ThreadsListViewController())
            return
        }
        if id == Self.draftsRow {
            activeChannelId = id
            Router.shared.showDetail(DraftsViewController())
            return
        }
        activeChannelId = id
        onSelectChannel?(row)
    }
}

// MARK: - Header

/// Team name (Metropolis 28) with the server name under it, and the round "+" button.
final class ChannelListHeaderView: UIView {
    var onPlus: (() -> Void)?

    private let teamLabel = UILabel()
    private let serverLabel = UILabel()
    private let plusButton = UIButton(type: .custom)
    /// Quiet "connecting" indicator beside the team name (instead of a floating banner).
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var spinnerTask: Task<Void, Never>?
    private var connectionObserver: NSObjectProtocol?

    override init(frame: CGRect) {
        super.init(frame: frame)
        [teamLabel, serverLabel, plusButton, spinner].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        teamLabel.adjustsFontForContentSizeCategory = true
        teamLabel.accessibilityTraits = .header
        plusButton.layer.cornerRadius = 14
        plusButton.accessibilityLabel = "Browse, create or message"
        plusButton.addAction(UIAction { [weak self] _ in self?.onPlus?() }, for: .primaryActionTriggered)
        NSLayoutConstraint.activate([
            teamLabel.topAnchor.constraint(equalTo: topAnchor),
            teamLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            teamLabel.trailingAnchor.constraint(lessThanOrEqualTo: plusButton.leadingAnchor, constant: -8),
            serverLabel.topAnchor.constraint(equalTo: teamLabel.bottomAnchor),
            serverLabel.leadingAnchor.constraint(equalTo: teamLabel.leadingAnchor),
            serverLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -60),
            serverLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
            plusButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            plusButton.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            plusButton.widthAnchor.constraint(equalToConstant: 28),
            plusButton.heightAnchor.constraint(equalToConstant: 28),
            spinner.centerYAnchor.constraint(equalTo: plusButton.centerYAnchor),
            spinner.trailingAnchor.constraint(equalTo: plusButton.leadingAnchor, constant: -12),
        ])
        spinner.hidesWhenStopped = true
        spinner.accessibilityLabel = "Connecting"
        connectionObserver = NotificationCenter.default.addObserver(forName: .connectionChanged, object: nil, queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { self?.connectionChanged() }
        }
    }

    deinit { connectionObserver.map(NotificationCenter.default.removeObserver) }

    private func connectionChanged() {
        spinnerTask?.cancel()
        if AppSession.shared.connectionState == .connected { spinner.stopAnimating(); return }
        // Brief blips (app resume, network switch) reconnect on their own; only show if it lasts.
        spinnerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, AppSession.shared.connectionState != .connected else { return }
            self?.spinner.startAnimating()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(team: String, server: String, theme: Theme) {
        let heading = Typography.style(.heading, 700)
        teamLabel.attributedText = NSAttributedString(string: team, attributes: heading.attributes(color: theme.sidebarText))
        let sub = Typography.style(.heading, 50)
        serverLabel.attributedText = NSAttributedString(
            string: server, attributes: sub.attributes(color: theme.sidebarText.opacity(0.64)))
        plusButton.layer.backgroundColor = theme.sidebarText.opacity(0.08).cgColor
        plusButton.setImage(CompassIcon.image("plus", size: 18), for: .normal)
        plusButton.tintColor = theme.sidebarText.opacity(0.8)
        spinner.color = theme.sidebarText.opacity(0.64)
    }
}

/// Unread filter button and the "Find channels..." field.
final class ChannelListSubheaderView: UIView {
    var onToggleUnreads: (() -> Void)?
    var onSearch: (() -> Void)?

    private let filterButton = UIButton(type: .custom)
    private let searchField = UIControl()
    private let searchIcon = UIImageView()
    private let searchLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        [filterButton, searchField].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.layer.cornerRadius = 8
            addSubview($0)
        }
        [searchIcon, searchLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.isUserInteractionEnabled = false
            searchField.addSubview($0)
        }
        searchLabel.adjustsFontForContentSizeCategory = true
        searchField.addAction(UIAction { [weak self] _ in self?.onSearch?() }, for: .touchUpInside)
        searchField.accessibilityLabel = "Find channels"
        searchField.accessibilityTraits = .button
        searchField.isAccessibilityElement = true
        filterButton.accessibilityLabel = "Show unreads only"
        filterButton.addAction(UIAction { [weak self] _ in self?.onToggleUnreads?() }, for: .primaryActionTriggered)

        NSLayoutConstraint.activate([
            filterButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            filterButton.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            filterButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            filterButton.widthAnchor.constraint(equalToConstant: 40),
            filterButton.heightAnchor.constraint(equalToConstant: 40),
            searchField.leadingAnchor.constraint(equalTo: filterButton.trailingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            searchField.topAnchor.constraint(equalTo: filterButton.topAnchor),
            searchField.heightAnchor.constraint(equalToConstant: 40),
            searchIcon.leadingAnchor.constraint(equalTo: searchField.leadingAnchor, constant: 8),
            searchIcon.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 24),
            searchIcon.heightAnchor.constraint(equalToConstant: 24),
            searchLabel.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 5),
            searchLabel.trailingAnchor.constraint(lessThanOrEqualTo: searchField.trailingAnchor, constant: -8),
            searchLabel.centerYAnchor.constraint(equalTo: searchField.centerYAnchor, constant: 1),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setUnreadsOn(_ on: Bool, theme: Theme) {
        UIView.animate(withDuration: 0.15) {
            self.filterButton.layer.backgroundColor = (on ? theme.sidebarText : theme.sidebarText.opacity(0.12)).cgColor
        }
        filterButton.setImage(CompassIcon.image("filter-variant", size: 24), for: .normal)
        filterButton.tintColor = (on ? theme.sidebarBg : theme.sidebarText).opacity(0.56)
        filterButton.accessibilityValue = on ? "On" : "Off"
        searchField.layer.backgroundColor = theme.sidebarText.opacity(0.12).cgColor
        searchIcon.image = CompassIcon.image("magnify", size: 24)
        searchIcon.tintColor = theme.sidebarText.opacity(0.72)
        searchLabel.attributedText = NSAttributedString(
            string: "Find channels...",
            attributes: Typography.style(.body, 200).attributes(color: theme.sidebarText.opacity(0.72)))
    }
}

// MARK: - Category header

/// Uppercase category name with a chevron that rotates when collapsed. Tapping toggles.
final class CategoryHeaderView: UICollectionReusableView {
    var onTap: (() -> Void)?

    private let chevron = UIImageView()
    private let label = UILabel()
    private var collapsed = false

    /// marginTop 12 + paddingVertical 8 + line height 16 + 8.
    static func height(scale: CGFloat) -> CGFloat { 12 + 8 + (16 * scale).rounded() + 8 }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(chevron)
        addSubview(label)
        label.adjustsFontForContentSizeCategory = true
        isAccessibilityElement = true
        accessibilityTraits = [.header, .button]
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ section: SidebarSection, theme: Theme) {
        let color = theme.sidebarText.opacity(0.64)
        label.attributedText = NSAttributedString(string: section.title.uppercased(),
                                                  attributes: Typography.style(.heading, 75).attributes(color: color))
        chevron.image = CompassIcon.image("chevron-down", size: 20)
        chevron.tintColor = color
        alpha = section.muted ? 0.32 : 1
        accessibilityLabel = section.title
        accessibilityValue = section.collapsed ? "Collapsed" : "Expanded"
        if collapsed != section.collapsed, window != nil {
            // Same 100ms linear rotation as the official app.
            UIView.animate(withDuration: 0.1, delay: 0, options: .curveLinear) {
                self.chevron.transform = section.collapsed ? CGAffineTransform(rotationAngle: -.pi / 2) : .identity
            }
        } else {
            chevron.transform = section.collapsed ? CGAffineTransform(rotationAngle: -.pi / 2) : .identity
        }
        collapsed = section.collapsed
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let top: CGFloat = 12 + 8
        chevron.bounds = CGRect(x: 0, y: 0, width: 20, height: 20)
        chevron.center = CGPoint(x: 16 + 2 + 10, y: top - 2 + 10)
        let x = 16 + 2 + 20 + 2
        let size = label.sizeThatFits(CGSize(width: bounds.width - CGFloat(x) - 20, height: .greatestFiniteMagnitude))
        label.frame = CGRect(x: CGFloat(x), y: top, width: min(size.width, bounds.width - CGFloat(x) - 20),
                             height: size.height)
    }

    @objc private func tapped() {
        let base = alpha
        UIView.animate(withDuration: 0.1) { self.alpha = base * 0.6 } completion: { _ in
            UIView.animate(withDuration: 0.15) { self.alpha = base }
        }
        onTap?()
    }
}
