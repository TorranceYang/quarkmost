import Foundation

/// One row in the sidebar, already resolved for display.
public struct SidebarChannel: Hashable, Sendable {
    public let id: String
    public let name: String
    public let type: ChannelType
    public let unread: Bool
    public let mentions: Int
    public let muted: Bool
    public let lastPostAt: Int64
    /// DMs: the other person (or you, for your own DM).
    public let teammateId: String?
    public let teammatePictureUpdate: Int64?
    public let teammateIsBot: Bool
    public let teammateDeleted: Bool
    public let teammateStatus: String?
    /// Group messages: number of other people.
    public let groupSize: Int
}

public struct SidebarSection: Hashable, Sendable {
    public let id: String
    public let title: String
    public let collapsed: Bool
    public let muted: Bool
    public let channels: [SidebarChannel]
}

/// The logged-in state shared by the UI: who you are, which team, and the sidebar.
@MainActor
public final class AppSession {
    public static let shared = AppSession()

    public let client: MattermostClient
    public private(set) var me: User?
    public private(set) var team: Team?
    public private(set) var sidebar: [SidebarSection] = []
    /// Raw JSON of the user's theme preference for the current team, if any.
    public private(set) var themeJSON: String?

    /// Called on the main actor whenever `sidebar` (or the theme) changes.
    public var onSidebarChange: (() -> Void)?

    var usersById: [String: User] = [:]
    var statusByUserId: [String: String] = [:]
    var categories: [SidebarCategory] = []
    var channels: [Channel] = []
    var membersById: [String: ChannelMember] = [:]

    // Drafts (synced with the server), keyed by "channelId/rootId".
    var drafts: [String: String] = [:]
    var draftSaveTasks: [String: Task<Void, Never>] = [:]
    // Followed-thread totals for the Threads row.
    public internal(set) var unreadThreads = 0
    public internal(set) var unreadThreadMentions = 0
    // Who is typing where: "channelId/rootId" → userId → expiry.
    var typing: [String: [String: Date]] = [:]
    public internal(set) var connectionState: WebSocketState = .disconnected
    public internal(set) var config: [String: String] = [:]
    public internal(set) var preferences: [Preference] = []
    var extrasLoaded = false
    var slashCommands: [SlashCommand]?

    public var isLoggedIn: Bool { KeychainStore.loadToken() != nil }

    // Realtime
    var socket: WebSocketClient?
    private var socketTask: Task<Void, Never>?
    private var postObservers: [UUID: (channelId: String, handler: (PostEvent) -> Void)] = [:]
    /// Saved ("flagged") post IDs, from preferences.
    public private(set) var savedPostIds: Set<String> = []
    private var sidebarRefreshTask: Task<Void, Never>?
    /// The channel on screen; new posts there are marked read immediately.
    public var viewingChannelId: String?

    public enum PostEvent: Sendable {
        case posted(Post), edited(Post), deleted(Post)
        case reactionAdded(Reaction), reactionRemoved(Reaction)
        case typing(rootId: String)
        case reconnected
    }

    private init() {
        KeychainStore.migrateToSharedGroup()   // so the notification extension can read it
        client = MattermostClient(token: KeychainStore.loadToken())
        // Show the last known sidebar immediately; the network refresh replaces it.
        if KeychainStore.loadToken() != nil, let snap = DiskCache.load(SidebarSnapshot.self, key: "sidebar") {
            me = snap.me
            team = snap.team
            channels = snap.channels
            membersById = Dictionary(snap.members.map { ($0.channelId, $0) }, uniquingKeysWith: { a, _ in a })
            categories = snap.categories
            usersById = Dictionary(snap.users.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            statusByUserId = snap.statuses
            themeJSON = snap.themeJSON
            savedPostIds = Set(snap.savedPostIds)
            rebuildSidebar()
        }
    }

    // MARK: Auth

    public func login(loginId: String, password: String, mfaCode: String?) async throws {
        let (user, token) = try await client.login(loginId: loginId, password: password, mfaCode: mfaCode)
        try KeychainStore.saveToken(token)
        me = user
    }

    public func logout() async {
        stopRealtime()
        try? await client.logout()
        KeychainStore.deleteToken()
        DiskCache.clear()
        await client.setToken(nil)
        me = nil
        team = nil
        sidebar = []
        categories = []
        channels = []
        usersById = [:]
        statusByUserId = [:]
        savedPostIds = []
        drafts = [:]; typing = [:]; preferences = []; extrasLoaded = false; slashCommands = nil
        unreadThreads = 0; unreadThreadMentions = 0
        themeJSON = nil
        customEmojiLoaded = false
        CustomEmojiStore.shared.reset()
    }

    // MARK: Sidebar

    /// Loads (or reloads) the user, team, channels, unread state and sidebar categories.
    public func refreshSidebar() async throws {
        let me: User
        if let current = self.me { me = current } else { me = try await client.me(); self.me = me }
        usersById[me.id] = me
        let team: Team
        if let current = self.team {
            team = current
        } else {
            guard let first = try await client.myTeams().sorted(by: { $0.displayName < $1.displayName }).first else {
                sidebar = []; onSidebarChange?(); return
            }
            team = first
            self.team = first
        }

        async let channelsReq = client.myChannels(teamId: team.id)
        async let membersReq = client.myChannelMembers(teamId: team.id)
        async let categoriesReq = client.sidebarCategories(userId: me.id, teamId: team.id)
        async let themeReq = try? client.preferences(userId: me.id, category: "theme")
        async let savedReq = try? client.preferences(userId: me.id, category: "flagged_post")
        let (channels, members, categoryList, themePrefs) = try await (channelsReq, membersReq, categoriesReq, themeReq)
        if let saved = await savedReq { savedPostIds = Set(saved.filter { $0.value == "true" }.map(\.name)) }

        // A team-specific theme wins over the account-wide one, as on desktop.
        let prefs = themePrefs ?? []
        themeJSON = (prefs.first { $0.name == team.id } ?? prefs.first { $0.name.isEmpty })?.value

        // Resolve the other person in each DM, then everyone's status.
        let dmUserIds = Set(channels.filter { $0.type == .direct }.flatMap { $0.name.components(separatedBy: "__") })
        let unknown = dmUserIds.subtracting(usersById.keys)
        if !unknown.isEmpty {
            for user in try await client.users(ids: Array(unknown)) { usersById[user.id] = user }
        }
        if let statuses = try? await client.statuses(userIds: Array(dmUserIds)) {
            for s in statuses { statusByUserId[s.userId] = s.status }
        }

        self.channels = channels.filter { $0.deleteAt == 0 }
        self.membersById = Dictionary(uniqueKeysWithValues: members.map { ($0.channelId, $0) })
        self.categories = categoryList.ordered
        rebuildSidebar()
        DiskCache.save(SidebarSnapshot(me: me, team: team, channels: self.channels, members: members,
                                       categories: self.categories, users: Array(usersById.values),
                                       statuses: statusByUserId, themeJSON: themeJSON, savedPostIds: Array(savedPostIds)),
                       key: "sidebar")
        startRealtime()
        loadExtras()
        if !customEmojiLoaded {
            customEmojiLoaded = true
            Task { await CustomEmojiStore.shared.load(client: client) }
        }
    }
    private var customEmojiLoaded = false

    /// Collapses or expands a category locally right away, then saves it to the server
    /// so desktop and web stay in sync.
    public func toggleCollapsed(categoryId: String) {
        guard let index = categories.firstIndex(where: { $0.id == categoryId }) else { return }
        categories[index].collapsed = !(categories[index].collapsed ?? false)
        rebuildSidebar()
        let updated = categories[index]
        Task { try? await client.updateCategory(updated) }
    }

    func replaceMe(_ user: User) { me = user }
    func replaceTheme(_ json: String) { themeJSON = json }

    public func channelName(_ id: String) -> String? {
        for section in sidebar { if let row = section.channels.first(where: { $0.id == id }) { return row.name } }
        return nil
    }

    // MARK: Users and read state

    public func user(_ id: String) -> User? { usersById[id] }
    public func status(_ userId: String) -> String? { statusByUserId[userId] }
    public func member(_ channelId: String) -> ChannelMember? { membersById[channelId] }
    public func channel(_ id: String) -> Channel? { channels.first { $0.id == id } }

    /// Fetches any authors not seen yet, in one request.
    public func loadUsers(_ ids: some Sequence<String>) async {
        let missing = Set(ids).subtracting(usersById.keys)
        guard !missing.isEmpty, let users = try? await client.users(ids: Array(missing)) else { return }
        for user in users { usersById[user.id] = user }
    }

    /// Marks a channel read on the server and clears its unread state locally right away.
    public func markRead(channelId: String) {
        if let member = membersById[channelId], let channel = channels.first(where: { $0.id == channelId }) {
            membersById[channelId] = ChannelMember(
                channelId: member.channelId, userId: member.userId,
                msgCount: channel.totalMsgCount ?? member.msgCount,
                msgCountRoot: channel.totalMsgCountRoot ?? member.msgCountRoot,
                mentionCount: 0, mentionCountRoot: 0,
                lastViewedAt: Int64(Date().timeIntervalSince1970 * 1000), notifyProps: member.notifyProps)
            rebuildSidebar()
        }
        Task { try? await client.markChannelViewed(channelId: channelId) }
        clearNotifications(channelId: channelId)
    }

    // MARK: Realtime

    /// Any number of screens can watch one channel (the channel and an open thread).
    @discardableResult
    public func observePosts(channelId: String, _ handler: @escaping (PostEvent) -> Void) -> UUID {
        let token = UUID()
        postObservers[token] = (channelId, handler)
        return token
    }

    public func stopObservingPosts(_ token: UUID) { postObservers[token] = nil }

    func notify(_ channelId: String, _ event: PostEvent) {
        for observer in postObservers.values where observer.channelId == channelId || observer.channelId == "*" { observer.handler(event) }
    }

    public func setSaved(_ saved: Bool, postId: String) {
        if saved { savedPostIds.insert(postId) } else { savedPostIds.remove(postId) }
        guard let me else { return }
        Task { try? await client.setSaved(saved, userId: me.id, postId: postId) }
    }

    private func startRealtime() {
        guard socket == nil, let token = KeychainStore.loadToken() else { return }
        let socket = WebSocketClient(token: token)
        self.socket = socket
        socketTask = Task { [weak self] in
            await socket.connect()
            await withTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor [weak self] in
                    for await event in socket.events { self?.handle(event) }
                }
                group.addTask { @MainActor [weak self] in
                    var wasConnected = false
                    for await state in socket.states {
                        self?.connectionState = state
                        NotificationCenter.default.post(name: .connectionChanged, object: nil)
                        if state == .connected {
                            // Events aren't replayed after a drop, so catch up.
                            if wasConnected { self?.didReconnect() }
                            wasConnected = true
                        }
                    }
                }
            }
        }
    }

    private func stopRealtime() {
        socketTask?.cancel()
        socketTask = nil
        if let socket { Task { await socket.disconnect() } }
        socket = nil
    }

    private func didReconnect() {
        for observer in postObservers.values { observer.handler(.reconnected) }
        extrasLoaded = false
        scheduleSidebarRefresh()
    }

    private func handle(_ event: WebSocketEvent) {
        func post() -> Post? {
            guard let json = event.data?["post"]?.stringValue, let data = json.data(using: .utf8) else { return nil }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try? decoder.decode(Post.self, from: data)
        }
        switch event.event {
        case "posted":
            guard let post = post() else { return }
            notify(post.channelId, .posted(post))
            typing["\(post.channelId)/\(post.rootId)"]?[post.userId] = nil
            NotificationCenter.default.post(name: .postReceived, object: nil, userInfo: ["post": post, "event": event])
            if post.channelId == viewingChannelId { markRead(channelId: post.channelId) }
            scheduleSidebarRefresh()
        case "post_edited":
            if let post = post() { notify(post.channelId, .edited(post)) }
        case "post_deleted":
            if let post = post() { notify(post.channelId, .deleted(post)) }
        case "reaction_added", "reaction_removed":
            guard let json = event.data?["reaction"]?.stringValue, let data = json.data(using: .utf8),
                  let channelId = event.broadcast?["channel_id"]?.stringValue else { return }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            guard let reaction = try? decoder.decode(Reaction.self, from: data) else { return }
            notify(channelId, event.event == "reaction_added" ? .reactionAdded(reaction) : .reactionRemoved(reaction))
        case "typing":
            handleTyping(event)
        case "thread_updated", "thread_read_changed", "thread_follow_changed":
            refreshThreadTotals()
            NotificationCenter.default.post(name: .threadsChanged, object: nil)
        case "draft_created", "draft_updated", "draft_deleted":
            handleDraftEvent(event)
        case "user_updated":
            handleUserUpdated(event)
        case "emoji_added":
            Task { await CustomEmojiStore.shared.load(client: client) }
        case "status_change":
            if let userId = event.data?["user_id"]?.stringValue, let status = event.data?["status"]?.stringValue {
                statusByUserId[userId] = status
                rebuildSidebar()
            }
        case "channel_viewed":
            if let id = event.data?["channel_id"]?.stringValue { clearNotifications(channelId: id) }
            scheduleSidebarRefresh()
        case "multiple_channels_viewed", "channel_created", "channel_updated",
             "channel_deleted", "user_added", "user_removed", "sidebar_category_updated",
             "sidebar_category_order_updated", "sidebar_category_created", "sidebar_category_deleted",
             "direct_added", "group_added", "preferences_changed":
            scheduleSidebarRefresh()
        default:
            break
        }
    }

    /// Bursts of events (a busy channel, a reconnect) collapse into one refresh.
    func scheduleSidebarRefresh() {
        sidebarRefreshTask?.cancel()
        sidebarRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            try? await self?.refreshSidebar()
        }
    }

    func rebuildSidebar() {
        guard let me else { return }
        let channelsById = Dictionary(uniqueKeysWithValues: channels.map { ($0.id, $0) })
        sidebar = categories.compactMap { category in
            var rows = category.channelIds.compactMap { id -> SidebarChannel? in
                guard let channel = channelsById[id] else { return nil }
                return makeRow(channel, member: membersById[id], me: me)
            }
            // Favorites is hidden when empty; other categories still show their header.
            if rows.isEmpty && category.type == .favorites { return nil }
            switch category.sorting ?? .none {
            case .alpha: rows.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            case .recent: rows.sort { $0.lastPostAt > $1.lastPostAt }
            case .manual, .none: break
            }
            let title: String = switch category.type {
            case .favorites: "Favorites"
            case .channels: "Channels"
            case .directMessages: "Direct messages"
            case .custom: category.displayName
            }
            return SidebarSection(id: category.id, title: title, collapsed: category.collapsed ?? false,
                                  muted: category.muted ?? false, channels: rows)
        }
        onSidebarChange?()
        NotificationCenter.default.post(name: Notification.Name("Quarkmost.sidebarChanged"), object: nil)
        updateBadge()
    }

    private func makeRow(_ channel: Channel, member: ChannelMember?, me: User) -> SidebarChannel {
        var name = channel.displayName
        var teammate: User?
        var groupSize = 0
        switch channel.type {
        case .direct:
            let ids = channel.name.components(separatedBy: "__")
            let otherId = ids.first { $0 != me.id } ?? me.id
            teammate = usersById[otherId]
            name = teammate?.username ?? channel.displayName
            if otherId == me.id { name = "\(me.username) (you)" }
        case .group:
            groupSize = channel.displayName.components(separatedBy: ",").count
        default:
            break
        }
        // With collapsed threads only root posts count toward channel unread; without them, replies
        // are channel messages like any other.
        let crt = collapsedThreads
        let total = (crt ? channel.totalMsgCountRoot : nil) ?? channel.totalMsgCount ?? 0
        let seen = (crt ? member?.msgCountRoot : nil) ?? member?.msgCount ?? total
        let mentions = Int((crt ? member?.mentionCountRoot : nil) ?? member?.mentionCount ?? 0)
        return SidebarChannel(
            id: channel.id, name: name, type: channel.type, unread: total > seen, mentions: mentions,
            muted: member?.isMuted ?? false, lastPostAt: channel.lastPostAt,
            teammateId: teammate?.id, teammatePictureUpdate: teammate?.lastPictureUpdate,
            teammateIsBot: teammate?.isBot ?? false, teammateDeleted: (teammate?.deleteAt ?? 0) > 0,
            teammateStatus: teammate.flatMap { statusByUserId[$0.id] }, groupSize: groupSize)
    }
}
