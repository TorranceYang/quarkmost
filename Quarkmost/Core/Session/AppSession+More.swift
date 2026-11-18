import Foundation
import UIKit
import UserNotifications

public extension Notification.Name {
    static let connectionChanged = Notification.Name("Quarkmost.connectionChanged")
    static let postReceived = Notification.Name("Quarkmost.postReceived")
    static let threadsChanged = Notification.Name("Quarkmost.threadsChanged")
    static let draftsChanged = Notification.Name("Quarkmost.draftsChanged")
    static let preferencesChanged = Notification.Name("Quarkmost.preferencesChanged")
}

/// Drafts, typing, favorites/mute/leave, status, preferences: the state behind the screens ported
/// from the official app's `actions/local` and `actions/remote`.
public extension AppSession {
    // MARK: One-time extras after the sidebar loads

    internal func loadExtras() {
        guard !extrasLoaded, let me, let team else { return }
        extrasLoaded = true
        Task {
            async let draftsReq = try? client.drafts(teamId: team.id)
            async let prefsReq = try? client.allPreferences(userId: me.id)
            async let configReq = try? client.clientConfig()
            if let list = await draftsReq {
                drafts = [:]
                for d in list where (d.deleteAt ?? 0) == 0 && !d.message.isEmpty { drafts["\(d.channelId)/\(d.rootId ?? "")"] = d.message }
                NotificationCenter.default.post(name: .draftsChanged, object: nil)
                rebuildSidebar()
            }
            if let prefs = await prefsReq {
                preferences = prefs
                NotificationCenter.default.post(name: .preferencesChanged, object: nil)
            }
            if let config = await configReq {
                self.config = config
                rebuildSidebar()          // unread counting depends on collapsed threads
                refreshThreadTotals()
            }
            if let fresh = try? await client.me() { setMe(fresh) }
        }
        refreshThreadTotals()
    }

    func setMe(_ user: User) {
        usersById[user.id] = user
        replaceMe(user)
    }

    func refreshThreadTotals() {
        guard let me, let team else { return }
        guard collapsedThreads else {
            unreadThreads = 0; unreadThreadMentions = 0
            onSidebarChange?()
            return
        }
        Task {
            guard let totals = try? await client.threadTotals(userId: me.id, teamId: team.id) else { return }
            unreadThreads = totals.totalUnreadThreads ?? 0
            // The server's mention total can be stale (it can report a mention with no unread thread
            // behind it, which nothing can clear). Like the official app, count from the unread threads.
            var mentions = totals.totalUnreadMentions ?? 0
            if unreadThreads == 0 {
                mentions = 0
            } else if mentions > 0, let unread = try? await client.threads(userId: me.id, teamId: team.id, unreadOnly: true).threads,
                      unread.count < 25 {
                mentions = unread.reduce(0) { $0 + $1.unreadMentions }
            }
            unreadThreadMentions = mentions
            onSidebarChange?()
            NotificationCenter.default.post(name: Notification.Name("Quarkmost.sidebarChanged"), object: nil)
            updateBadge()
        }
    }

    // MARK: Preferences

    func preference(_ category: String, _ name: String) -> String? {
        preferences.first { $0.category == category && $0.name == name }?.value
    }

    func setPreference(_ category: String, _ name: String, _ value: String) {
        guard let me else { return }
        preferences.removeAll { $0.category == category && $0.name == name }
        preferences.append(Preference(userId: me.id, category: category, name: name, value: value))
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
        Task { try? await client.savePreferences(userId: me.id, [(category, name, value)]) }
    }

    /// Applies a theme now and saves it for this team, so desktop and web follow.
    func setTheme(json: String) {
        guard let me, let team else { return }
        replaceTheme(json)
        rebuildSidebar()
        Task { try? await client.saveTheme(userId: me.id, teamId: team.id, json: json) }
    }

    /// Collapsed reply threads, decided like the official app (`utils/thread.ts`): off when the server
    /// disables it; otherwise the user's display preference, falling back to the server default.
    /// Off means replies are shown inline in the channel and there is no Threads view.
    var collapsedThreads: Bool {
        let server = config["CollapsedThreads"] ?? "disabled"
        switch server {
        case "disabled", "": return false
        case "always_on": return true
        default:
            let pref = preference("display_settings", "collapsed_reply_threads")
            return pref.map { $0 == "on" } ?? (server == "default_on")
        }
    }

    /// 24-hour clock preference (Display → Clock Display).
    var uses24HourClock: Bool { preference("display_settings", "use_military_time") == "true" }

    /// How names are shown: "username" (default), "nickname_full_name", or "full_name".
    var teammateNameDisplay: String {
        preference("display_settings", "name_format") ?? config["TeammateNameDisplay"] ?? "username"
    }

    func displayName(_ user: User?) -> String {
        guard let user else { return "Someone" }
        switch teammateNameDisplay {
        case "nickname_full_name": return user.displayName
        case "full_name": return user.fullName.isEmpty ? user.username : user.fullName
        default: return user.username
        }
    }

    // MARK: Drafts

    func draft(channelId: String, rootId: String?) -> String { drafts["\(channelId)/\(rootId ?? "")"] ?? "" }

    var allDrafts: [(channelId: String, rootId: String, message: String)] {
        drafts.map { key, value in
            let parts = key.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            return (String(parts[0]), parts.count > 1 ? String(parts[1]) : "", value)
        }.sorted { $0.channelId < $1.channelId }
    }

    func hasDraft(channelId: String) -> Bool { !(drafts["\(channelId)/"] ?? "").isEmpty }

    /// Stores the draft now and syncs it to the server after a pause in typing.
    func setDraft(_ text: String, channelId: String, rootId: String?) {
        let key = "\(channelId)/\(rootId ?? "")"
        let had = !(drafts[key] ?? "").isEmpty
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        drafts[key] = trimmed.isEmpty ? nil : text
        if had != !trimmed.isEmpty {
            NotificationCenter.default.post(name: .draftsChanged, object: nil)
            rebuildSidebar()
        }
        draftSaveTasks[key]?.cancel()
        draftSaveTasks[key] = Task { [client] in
            try? await Task.sleep(for: .milliseconds(trimmed.isEmpty ? 0 : 1500))
            guard !Task.isCancelled else { return }
            if trimmed.isEmpty { try? await client.deleteDraft(channelId: channelId, rootId: rootId) }
            else { try? await client.saveDraft(channelId: channelId, rootId: rootId, message: text) }
        }
    }

    internal func handleDraftEvent(_ event: WebSocketEvent) {
        guard let json = event.data?["draft"]?.stringValue, let data = json.data(using: .utf8) else { return }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let draft = try? decoder.decode(Draft.self, from: data) else { return }
        let key = "\(draft.channelId)/\(draft.rootId ?? "")"
        drafts[key] = (event.event == "draft_deleted" || draft.message.isEmpty) ? nil : draft.message
        NotificationCenter.default.post(name: .draftsChanged, object: nil, userInfo: ["key": key])
        rebuildSidebar()
    }

    // MARK: Typing

    func sendTyping(channelId: String, rootId: String?) {
        guard let socket else { return }
        Task { await socket.sendAction("user_typing", data: ["channel_id": channelId, "parent_id": rootId ?? ""]) }
    }

    /// Usernames currently typing in a channel or thread.
    func typingNames(channelId: String, rootId: String?) -> [String] {
        let now = Date()
        return (typing["\(channelId)/\(rootId ?? "")"] ?? [:]).filter { $0.value > now && $0.key != me?.id }
            .keys.compactMap { usersById[$0].map(displayName) }.sorted()
    }

    internal func handleTyping(_ event: WebSocketEvent) {
        guard let userId = event.data?["user_id"]?.stringValue,
              let channelId = event.broadcast?["channel_id"]?.stringValue else { return }
        let rootId = event.data?["parent_id"]?.stringValue ?? ""
        let key = "\(channelId)/\(rootId)"
        typing[key, default: [:]][userId] = Date().addingTimeInterval(5)
        Task {
            await loadUsers([userId])
            notify(channelId, .typing(rootId: rootId))
            try? await Task.sleep(for: .seconds(5.1))
            notify(channelId, .typing(rootId: rootId))
        }
    }

    internal func handleUserUpdated(_ event: WebSocketEvent) {
        guard let json = event.data?["user"], let data = try? JSONEncoder().encode(json) else { return }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let user = try? decoder.decode(User.self, from: data) else { return }
        usersById[user.id] = user
        if user.id == me?.id { replaceMe(user) }
        rebuildSidebar()
    }

    // MARK: Channels

    var allChannels: [Channel] { channels }

    func channel(named name: String) -> Channel? { channels.first { $0.name == name } }

    func user(username: String) -> User? { usersById.values.first { $0.username == username } }

    func cache(_ users: [User]) { for u in users { usersById[u.id] = u } }

    func setStatusLocally(_ userId: String, _ status: String) { statusByUserId[userId] = status; rebuildSidebar() }

    /// The other person in a DM channel.
    func teammateId(of channel: Channel) -> String? {
        guard channel.type == .direct, let me else { return nil }
        let ids = channel.name.components(separatedBy: "__")
        return ids.first { $0 != me.id } ?? me.id
    }

    func title(for channel: Channel) -> String {
        channelName(channel.id) ?? (channel.type == .direct
            ? teammateId(of: channel).flatMap { usersById[$0] }.map(displayName) ?? channel.displayName
            : channel.displayName)
    }

    func isFavorite(_ channelId: String) -> Bool {
        categories.first { $0.type == .favorites }?.channelIds.contains(channelId) ?? false
    }

    func isMuted(_ channelId: String) -> Bool { membersById[channelId]?.isMuted ?? false }

    func setFavorite(_ favorite: Bool, channelId: String) {
        guard let me, let team, let channel = channel(channelId) else { return }
        var changed: [SidebarCategory] = []
        for i in categories.indices {
            let c = categories[i]
            let home: Bool = favorite ? c.type == .favorites
                : (channel.type == .direct || channel.type == .group ? c.type == .directMessages : c.type == .channels)
            var ids = c.channelIds.filter { $0 != channelId }
            if home { ids.insert(channelId, at: 0) }
            if ids != c.channelIds {
                categories[i] = SidebarCategory(id: c.id, userId: c.userId, teamId: c.teamId, displayName: c.displayName,
                                                type: c.type, sorting: c.sorting, channelIds: ids,
                                                collapsed: c.collapsed, muted: c.muted)
                changed.append(categories[i])
            }
        }
        rebuildSidebar()
        Task { try? await client.updateCategories(userId: me.id, teamId: team.id, categories: changed) }
    }

    func setMuted(_ muted: Bool, channelId: String) {
        guard let me, let m = membersById[channelId] else { return }
        var props = m.notifyProps?.objectValue ?? [:]
        props["mark_unread"] = .string(muted ? "mention" : "all")
        membersById[channelId] = ChannelMember(channelId: m.channelId, userId: m.userId, msgCount: m.msgCount,
                                               msgCountRoot: m.msgCountRoot, mentionCount: m.mentionCount,
                                               mentionCountRoot: m.mentionCountRoot, lastViewedAt: m.lastViewedAt,
                                               notifyProps: .object(props))
        rebuildSidebar()
        Task { try? await client.updateNotifyProps(channelId: channelId, userId: me.id, props: ["mark_unread": muted ? "mention" : "all"]) }
    }

    func setChannelNotifyProp(_ key: String, _ value: String, channelId: String) {
        guard let me, let m = membersById[channelId] else { return }
        var props = m.notifyProps?.objectValue ?? [:]
        props[key] = .string(value)
        membersById[channelId] = ChannelMember(channelId: m.channelId, userId: m.userId, msgCount: m.msgCount,
                                               msgCountRoot: m.msgCountRoot, mentionCount: m.mentionCount,
                                               mentionCountRoot: m.mentionCountRoot, lastViewedAt: m.lastViewedAt,
                                               notifyProps: .object(props))
        Task { try? await client.updateNotifyProps(channelId: channelId, userId: me.id, props: [key: value]) }
    }

    /// Leaves a channel, or hides a DM/GM from the sidebar (they can always be reopened).
    func leaveOrClose(_ channel: Channel) async {
        guard let me else { return }
        switch channel.type {
        case .direct:
            if let other = teammateId(of: channel) {
                try? await client.savePreferences(userId: me.id, [("direct_channel_show", other, "false")])
            }
        case .group:
            try? await client.savePreferences(userId: me.id, [("group_channel_show", channel.id, "false")])
        default:
            try? await client.removeMember(channelId: channel.id, userId: me.id)
        }
        channels.removeAll { $0.id == channel.id }
        rebuildSidebar()
        try? await refreshSidebar()
    }

    /// Opens (creating if needed) a DM or group message and returns its channel.
    func openDirect(with userIds: [String]) async throws -> Channel {
        guard let me else { throw ClientError.notAuthenticated }
        let ids = Array(Set(userIds + [me.id]))
        let channel = try await client.createDirect(userIds: ids.count == 1 ? [me.id, me.id] : ids)
        if channel.type == .direct, let other = userIds.first {
            try? await client.savePreferences(userId: me.id, [("direct_channel_show", other, "true")])
        } else {
            try? await client.savePreferences(userId: me.id, [("group_channel_show", channel.id, "true")])
        }
        await loadUsers(userIds)
        try? await refreshSidebar()
        if !channels.contains(where: { $0.id == channel.id }) { channels.append(channel) }
        return channel
    }

    func join(_ channel: Channel) async throws {
        guard let me else { return }
        try await client.addMember(channelId: channel.id, userId: me.id)
        try await refreshSidebar()
        if !channels.contains(where: { $0.id == channel.id }) { channels.append(channel) }
    }

    func commands() async -> [SlashCommand] {
        if let slashCommands { return slashCommands }
        guard let team, let list = try? await client.commands(teamId: team.id) else { return [] }
        slashCommands = list
        return list
    }

    // MARK: Totals and badge

    var totalMentions: Int {
        sidebar.flatMap(\.channels).filter { !$0.muted }.reduce(0) { $0 + $1.mentions } + unreadThreadMentions
    }

    var hasUnreads: Bool { sidebar.flatMap(\.channels).contains { $0.unread && !$0.muted } || unreadThreads > 0 }

    internal func updateBadge() {
        UNUserNotificationCenter.current().setBadgeCount(totalMentions)
    }

    /// Removes delivered notifications for a channel once it's been read (here or on another device).
    nonisolated func clearNotifications(channelId: String) {
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { delivered in
            let ids = delivered.filter { ($0.request.content.userInfo["channel_id"] as? String) == channelId }
                .map(\.request.identifier)
            if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
        }
    }

    /// Words that count as a mention of you (for Recent Mentions and highlights).
    var mentionKeys: [String] {
        guard let me else { return [] }
        var keys = ["@\(me.username)"]
        if let custom = me.notifyProps?["mention_keys"]?.stringValue {
            keys += custom.split(separator: ",").map(String.init).filter { !$0.isEmpty }
        }
        if me.notifyProps?["first_name"]?.stringValue == "true", let first = me.firstName, !first.isEmpty { keys.append(first) }
        return Array(Set(keys))
    }
}
