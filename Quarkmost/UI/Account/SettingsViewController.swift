import UIKit

/// Settings (`screens/settings`): Notifications, Display, Advanced Settings, About.
final class SettingsViewController: StackScreenViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        let rows: [(String, String, () -> UIViewController)] = [
            ("bell-outline", "Notifications", { NotificationSettingsViewController() }),
            ("layers-outline", "Display", { DisplaySettingsViewController() }),
            ("tune", "Advanced Settings", { AdvancedSettingsViewController() }),
            ("information-outline", "About \(AppInfo.displayName)", { AboutViewController() }),
        ]
        stack.addArrangedSubview(spacer(8))
        for (icon, title, make) in rows {
            let known = CompassGlyphs.codes[icon] != nil ? icon : "settings-outline"
            stack.addArrangedSubview(MenuRow(icon: known, title: title, accessory: .chevron) { [weak self] in
                self?.navigationController?.pushViewController(make(), animated: true)
            })
        }
        addDivider()
        stack.addArrangedSubview(MenuRow(icon: "help-circle-outline".ifKnown("information-outline"), title: "Help") {
            Router.shared.open(url: URL(string: "https://docs.mattermost.com/")!)
        })
    }

    private func spacer(_ h: CGFloat) -> UIView {
        let v = UIView()
        v.heightAnchor.constraint(equalToConstant: h).isActive = true
        return v
    }
}

extension String {
    /// Falls back to another Compass icon name when this one isn't in the bundled font.
    func ifKnown(_ fallback: String) -> String { CompassGlyphs.codes[self] != nil ? self : fallback }
}

/// A screen of mutually exclusive choices, saved as you tap (like the official option lists).
class ChoiceListViewController: StackScreenViewController {
    struct Choice { let value: String; let title: String; var subtitle: String? = nil }
    private let header: String?
    private let footer: String?
    private let choices: [Choice]
    private var selected: String
    private let onSelect: (String) -> Void
    private var rows: [MenuRow] = []

    init(title: String, header: String? = nil, footer: String? = nil, choices: [Choice], selected: String,
         onSelect: @escaping (String) -> Void) {
        self.header = header; self.footer = footer; self.choices = choices; self.selected = selected; self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        if let header { addSectionTitle(header) }
        for choice in choices {
            let row = MenuRow(icon: nil, title: choice.title, subtitle: choice.subtitle,
                              accessory: .check(choice.value == selected)) { [weak self] in self?.pick(choice.value) }
            rows.append(row)
            stack.addArrangedSubview(row)
        }
        if let footer { addText(footer, style: Typography.style(.body, 75), alpha: 0.56) }
    }

    private func pick(_ value: String) {
        selected = value
        for (row, choice) in zip(rows, choices) { row.setAccessory(.check(choice.value == value)) }
        onSelect(value)
    }
}

final class NotificationSettingsViewController: StackScreenViewController {
    private var props: [String: JSONValue] { AppSession.shared.me?.notifyProps?.objectValue ?? [:] }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        build()
    }

    private func save(_ changes: [String: String]) {
        var all = props
        for (k, v) in changes { all[k] = .string(v) }
        Task {
            do { AppSession.shared.setMe(try await AppSession.shared.client.patchMyNotifyProps(all)); build() }
            catch { showError(error) }
        }
    }

    private func build() {
        clear()
        title = "Notifications"
        let p = props
        func s(_ k: String, _ d: String) -> String { p[k]?.stringValue ?? d }
        let push = s("push", "mention"), pushStatus = s("push_status", "online")
        let pushLabel = ["all": "All new messages", "mention": "Mentions", "none": "Off"][push] ?? push
        let keys = s("mention_keys", "")

        stack.addArrangedSubview(MenuRow(icon: "at", title: "Mentions",
                                         subtitle: keys.isEmpty ? "Keywords that trigger mentions" : keys, accessory: .chevron) { [weak self] in
            self?.editMentions()
        })
        stack.addArrangedSubview(MenuRow(icon: "cellphone", title: "Push Notifications", detail: pushLabel, accessory: .chevron) { [weak self] in
            self?.navigationController?.pushViewController(ChoiceListViewController(
                title: "Push Notifications", header: "Notify me about...",
                choices: [.init(value: "all", title: "All new messages"),
                          .init(value: "mention", title: "Mentions, direct messages and group messages (default)"),
                          .init(value: "none", title: "Nothing", subtitle: "You will still see mention badges within the app, but you will not receive push notifications on your device.")],
                selected: push) { self?.save(["push": $0]) }, animated: true)
        })
        stack.addArrangedSubview(MenuRow(icon: "bell-ring-outline", title: "Trigger push notifications when...",
                                         detail: ["online": "Online, away or offline", "away": "Away or offline", "offline": "Offline"][pushStatus],
                                         accessory: .chevron) { [weak self] in
            self?.navigationController?.pushViewController(ChoiceListViewController(
                title: "Push Notifications", header: "Trigger push notifications when...",
                choices: [.init(value: "online", title: "Online, away or offline"),
                          .init(value: "away", title: "Away or offline"), .init(value: "offline", title: "Offline")],
                selected: pushStatus) { self?.save(["push_status": $0]) }, animated: true)
        })
        let threads = MenuRow(icon: "reply-outline", title: "Thread replies",
                              subtitle: "Notify me about replies to threads I'm following", accessory: .toggle(s("push_threads", "all") == "all"))
        threads.onToggle = { [weak self] on in self?.save(["push_threads": on ? "all" : "mention"]) }
        stack.addArrangedSubview(threads)
        let email = MenuRow(icon: "email-outline", title: "Email", subtitle: "Send email notifications for mentions and direct messages when you're offline or away",
                            accessory: .toggle(s("email", "true") == "true"))
        email.onToggle = { [weak self] on in self?.save(["email": on ? "true" : "false"]) }
        stack.addArrangedSubview(email)
        let auto = MenuRow(icon: "reply-outline", title: "Automatic replies",
                           subtitle: s("auto_responder_message", "Hello, I am out of office and unable to respond to messages."),
                           accessory: .toggle(s("auto_responder_active", "false") == "true"))
        auto.onToggle = { [weak self] on in
            self?.save(["auto_responder_active": on ? "true" : "false",
                        "auto_responder_message": s("auto_responder_message", "Hello, I am out of office and unable to respond to messages.")])
        }
        stack.addArrangedSubview(auto)
    }

    private func editMentions() {
        let p = props
        let alert = UIAlertController(title: "Keywords that trigger mentions",
                                      message: "Separate keywords with commas. They aren't case sensitive.", preferredStyle: .alert)
        alert.addTextField { $0.text = p["mention_keys"]?.stringValue; $0.placeholder = "Enter other keywords" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            let text = (alert.textFields?.first?.text ?? "").replacingOccurrences(of: " ", with: "")
            self?.save(["mention_keys": text])
        })
        present(alert, animated: true)
    }
}

final class DisplaySettingsViewController: StackScreenViewController {
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        build()
    }

    private func build() {
        clear()
        title = "Display"
        let session = AppSession.shared
        let themeName = Self.themes.first { Self.matches($0, session.themeJSON) }?["type"] ?? "Custom"
        stack.addArrangedSubview(MenuRow(icon: "palette-outline", title: "Theme", detail: themeName, accessory: .chevron) { [weak self] in
            self?.navigationController?.pushViewController(ChoiceListViewController(
                title: "Theme", choices: Self.themes.map { .init(value: $0["type"] ?? "", title: $0["type"] ?? "") },
                selected: themeName) { name in
                    guard let theme = Self.themes.first(where: { $0["type"] == name }),
                          let data = try? JSONSerialization.data(withJSONObject: theme),
                          let json = String(data: data, encoding: .utf8) else { return }
                    session.setTheme(json: json)
                    self?.showToast("Theme changed. Reopen screens to see it everywhere.")
                }, animated: true)
        })
        stack.addArrangedSubview(MenuRow(icon: "clock-outline", title: "Clock Display",
                                         detail: session.uses24HourClock ? "24-hour" : "12-hour", accessory: .chevron) { [weak self] in
            self?.navigationController?.pushViewController(ChoiceListViewController(
                title: "Clock Display",
                choices: [.init(value: "false", title: "12-hour clock", subtitle: "Example: 4:00 PM"),
                          .init(value: "true", title: "24-hour clock", subtitle: "Example: 16:00")],
                selected: session.uses24HourClock ? "true" : "false") {
                    session.setPreference("display_settings", "use_military_time", $0)
                }, animated: true)
        })
        let tz = session.me?.timezone
        let auto = tz?["useAutomaticTimezone"]?.stringValue != "false"
        let zone = auto ? "Auto" : (tz?["manualTimezone"]?.stringValue ?? "Manual")
        stack.addArrangedSubview(MenuRow(icon: "globe", title: "Timezone", detail: zone))
        let crt = session.preference("display_settings", "collapsed_reply_threads") ?? "on"
        // Hidden when the server turns collapsed threads off for everyone, as in the official app.
        if !["disabled", "always_on", ""].contains(session.config["CollapsedThreads"] ?? "") {
        stack.addArrangedSubview(MenuRow(icon: "message-text-outline", title: "Collapsed Reply Threads",
                                         detail: crt == "off" ? "Off" : "On", accessory: .chevron) { [weak self] in
            self?.navigationController?.pushViewController(ChoiceListViewController(
                title: "Collapsed Reply Threads",
                footer: "When enabled, reply messages are not shown in the channel and you'll be notified about threads you're following in the \"Threads\" view.",
                choices: [.init(value: "on", title: "On"), .init(value: "off", title: "Off")], selected: crt == "off" ? "off" : "on") {
                    session.setPreference("display_settings", "collapsed_reply_threads", $0)
                }, animated: true)
        })
        }
        stack.addArrangedSubview(MenuRow(icon: "account-outline", title: "Teammate Name Display",
                                         detail: ["username": "Username", "nickname_full_name": "Nickname", "full_name": "Full name"][session.teammateNameDisplay],
                                         accessory: .chevron) { [weak self] in
            self?.navigationController?.pushViewController(ChoiceListViewController(
                title: "Teammate Name Display",
                choices: [.init(value: "username", title: "Show username"),
                          .init(value: "nickname_full_name", title: "Show nickname if one exists, otherwise first and last name"),
                          .init(value: "full_name", title: "Show first and last name")],
                selected: session.teammateNameDisplay) { session.setPreference("display_settings", "name_format", $0) }, animated: true)
        })
    }

    static let themes: [[String: String]] = {
        guard let url = Bundle.main.url(forResource: "themes", withExtension: "json"), let data = try? Data(contentsOf: url),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else { return [] }
        return list
    }()

    static func matches(_ theme: [String: String], _ json: String?) -> Bool {
        guard let json, let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return theme["type"] == "Denim" }
        if let type = obj["type"] as? String, type != "custom" { return type.lowercased() == theme["type"]?.lowercased() }
        return (obj["sidebarBg"] as? String)?.lowercased() == theme["sidebarBg"]?.lowercased()
            && (obj["centerChannelBg"] as? String)?.lowercased() == theme["centerChannelBg"]?.lowercased()
    }
}

final class AdvancedSettingsViewController: StackScreenViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Advanced Settings"
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("files")
        let size = (FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey])?.allObjects as? [URL] ?? [])
            .reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
            + Int64(URLCache.shared.currentDiskUsage)
        let row = MenuRow(icon: "trash-can-outline", title: "Delete local files", detail: formatFileSize(size), destructive: true) { [weak self] in
            self?.confirm(title: "Delete local files",
                          message: "This will delete all files downloaded through the app for this server. Please confirm to proceed.",
                          action: "Delete") {
                try? FileManager.default.removeItem(at: dir)
                URLCache.shared.removeAllCachedResponses()
                self?.showToast("Local files deleted")
            }
        }
        stack.addArrangedSubview(row)
    }
}

final class AboutViewController: StackScreenViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "About"
        let theme = Theme.current
        let config = AppSession.shared.config
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        let logo = UIImageView(image: CompassIcon.image("message-text-outline", size: 72))
        logo.tintColor = theme.centerChannelColor
        logo.contentMode = .center
        logo.heightAnchor.constraint(equalToConstant: 120).isActive = true
        stack.addArrangedSubview(logo)
        let title = UILabel(AppInfo.displayName, Typography.style(.heading, 800), color: theme.centerChannelColor, alignment: .center)
        stack.addArrangedSubview(title)
        let sub = UILabel("Connected to \(ServerConfig.baseURL.host() ?? "")", Typography.style(.body, 200),
                          color: theme.centerChannelColor.opacity(0.72), alignment: .center)
        stack.addArrangedSubview(sub)
        addDivider()
        stack.addArrangedSubview(MenuRow(icon: nil, title: "App Version:", detail: "\(version) (Build \(build))"))
        stack.addArrangedSubview(MenuRow(icon: nil, title: "Server Version:",
                                         detail: "\(config["Version"] ?? "?") (Build \(config["BuildNumber"] ?? "?"))"))
        stack.addArrangedSubview(MenuRow(icon: nil, title: "Database:", detail: config["SQLDriverName"] ?? "—"))
        addDivider()
        addText("\(AppInfo.displayName) is an unofficial, independent client. It is a Swift port of the open-source Mattermost Mobile app (Apache License 2.0) and is not affiliated with or endorsed by Mattermost, Inc. Icons: Mattermost Compass Icons (Apache License 2.0).",
                style: Typography.style(.body, 75), alpha: 0.64)
        addText("Original app designs and assets copyright 2015-present Mattermost, Inc. Mattermost is a trademark of Mattermost, Inc.",
                style: Typography.style(.body, 75), alpha: 0.48)
    }
}
