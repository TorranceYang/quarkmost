import UIKit

/// Account tab (`screens/home/account`): your avatar and name on the sidebar color, then a rounded
/// sheet with status, custom status, Your Profile, Settings and Log out.
final class AccountViewController: StackScreenViewController {
    private let session = AppSession.shared
    var onLogout: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.current.sidebarBg
        scrollView.backgroundColor = .clear
        for name in [Notification.Name.sessionSidebarChanged, .preferencesChanged] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.build() }
            }
        }
        build()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        build()
    }

    private func build() {
        guard isViewLoaded else { return }
        clear()
        let theme = Theme.current
        let me = session.me
        let status = me.flatMap { session.status($0.id) } ?? "offline"

        // User info
        let avatar = AvatarView(size: 120)
        avatar.setUser(me?.id, pictureUpdate: me?.lastPictureUpdate)
        avatar.setStatus(status, background: theme.sidebarBg)
        let name = UILabel(me.map { $0.fullName.isEmpty ? $0.username : $0.fullName } ?? "",
                           Typography.style(.heading, 1000), color: theme.sidebarText, lines: 2)
        name.adjustsFontSizeToFitWidth = true
        name.minimumScaleFactor = 0.5
        let username = UILabel("@\(me?.username ?? "")", Typography.style(.body, 200), color: theme.sidebarText.opacity(0.64))
        let info = UIStackView(arrangedSubviews: [avatar, name, username])
        info.axis = .vertical
        info.alignment = .leading
        info.spacing = 8
        info.setCustomSpacing(16, after: avatar)
        addPadded(info, top: 24, bottom: 24)

        // Options sheet
        let sheet = UIStackView()
        sheet.axis = .vertical
        sheet.backgroundColor = theme.centerChannelBg
        sheet.layer.cornerRadius = 12
        sheet.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        sheet.isLayoutMarginsRelativeArrangement = true
        sheet.layoutMargins = UIEdgeInsets(top: 12, left: 0, bottom: 400, right: 0)

        let (statusIcon, statusColor, statusLabel) = Self.statusInfo(status, theme: theme)
        let presence = MenuRow(icon: statusIcon, title: statusLabel) { [weak self] in self?.pickStatus() }
        presence.iconView.tintColor = statusColor
        sheet.addArrangedSubview(presence)

        if let custom = me?.customStatus {
            let row = MenuRow(icon: nil, title: custom.text.isEmpty ? "Custom status" : custom.text) { [weak self] in self?.editCustomStatus() }
            let emoji = UILabel()
            emoji.font = .systemFont(ofSize: 22)
            emoji.text = EmojiStore.shared.unicode(for: custom.emoji) ?? "💬"
            row.iconView.isHidden = false
            row.iconView.image = nil
            row.iconView.addSubview(emoji)
            emoji.frame = CGRect(x: -2, y: -2, width: 28, height: 28)
            sheet.addArrangedSubview(row)
            sheet.addArrangedSubview(MenuRow(icon: "close-circle", title: "Clear status") { [weak self] in
                Task { try? await AppSession.shared.client.clearCustomStatus(); self?.refreshMe() }
            })
        } else {
            sheet.addArrangedSubview(MenuRow(icon: "emoticon-happy-outline", title: "Set a custom status") { [weak self] in
                self?.editCustomStatus()
            })
        }
        sheet.addArrangedSubview(Self.divider())
        sheet.addArrangedSubview(MenuRow(icon: "account-outline", title: "Your Profile") { [weak self] in
            self?.present(EditProfileViewController().wrappedForModal(), animated: true)
        })
        sheet.addArrangedSubview(MenuRow(icon: "settings-outline", title: "Settings") { [weak self] in
            self?.present(SettingsViewController().wrappedForModal(), animated: true)
        })
        sheet.addArrangedSubview(Self.divider())
        let server = session.config["SiteName"].flatMap { $0.isEmpty || $0 == "Mattermost" ? nil : $0 } ?? AppInfo.displayName
        sheet.addArrangedSubview(MenuRow(icon: "exit-to-app", title: "Log out", subtitle: "Log out of \(server)", destructive: true) { [weak self] in
            self?.confirm(title: "Log out", message: "Are you sure you want to log out of \(server)?", action: "Log out") {
                Router.shared.root?.onLogout?()
            }
        })
        stack.addArrangedSubview(sheet)
    }

    static func divider() -> UIView {
        let wrap = UIView()
        let line = UIView()
        line.backgroundColor = Theme.current.centerChannelColor.opacity(0.2)
        line.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(line)
        NSLayoutConstraint.activate([
            line.heightAnchor.constraint(equalToConstant: 1),
            line.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 8),
            line.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -8),
            line.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 20),
            line.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -20),
        ])
        return wrap
    }

    static func statusInfo(_ status: String, theme: Theme) -> (String, UIColor, String) {
        switch status {
        case "online": ("check-circle", theme.onlineIndicator, "Online")
        case "away": ("clock", theme.awayIndicator, "Away")
        case "dnd": ("minus-circle", theme.dndIndicator, "Do Not Disturb")
        default: ("circle-outline", theme.centerChannelColor.opacity(0.48), "Offline")
        }
    }

    private func pickStatus() {
        let options: [PostOptionsViewController.Option] = [
            .init(icon: "check-circle", title: "Online") { [weak self] in self?.setStatus("online") },
            .init(icon: "clock", title: "Away") { [weak self] in self?.setStatus("away") },
            .init(icon: "minus-circle", title: "Do Not Disturb") { [weak self] in self?.pickDndDuration() },
            .init(icon: "circle-outline", title: "Offline") { [weak self] in self?.setStatus("offline") },
        ]
        presentOptions(options, title: "Status")
    }

    private func pickDndDuration() {
        func until(_ seconds: TimeInterval) -> Int64 { Int64(Date().addingTimeInterval(seconds).timeIntervalSince1970) }
        let tomorrow = Calendar.current.startOfDay(for: Date().addingTimeInterval(86400)).addingTimeInterval(9 * 3600)
        let options: [PostOptionsViewController.Option] = [
            .init(icon: "clock-outline", title: "Don't clear") { [weak self] in self?.setStatus("dnd") },
            .init(icon: "clock-outline", title: "30 mins") { [weak self] in self?.setStatus("dnd", until: until(1800)) },
            .init(icon: "clock-outline", title: "1 hour") { [weak self] in self?.setStatus("dnd", until: until(3600)) },
            .init(icon: "clock-outline", title: "2 hours") { [weak self] in self?.setStatus("dnd", until: until(7200)) },
            .init(icon: "clock-outline", title: "Tomorrow") { [weak self] in
                self?.setStatus("dnd", until: Int64(tomorrow.timeIntervalSince1970))
            },
        ]
        presentOptions(options, title: "Disable notifications until")
    }

    private func setStatus(_ status: String, until: Int64? = nil) {
        guard let me = session.me else { return }
        session.setStatusLocally(me.id, status)
        build()
        Task {
            do { try await session.client.setStatus(userId: me.id, status: status, dndEndTime: until) }
            catch { showToast("Failed to update status. Try again") }
        }
    }

    private func editCustomStatus() {
        let vc = CustomStatusViewController()
        vc.onDone = { [weak self] in self?.refreshMe() }
        present(vc.wrappedForModal(), animated: true)
    }

    private func refreshMe() {
        Task {
            if let me = try? await session.client.me() { session.setMe(me) }
            build()
        }
    }
}

/// Set a custom status (`screens/custom_status`): emoji + text, suggestions, and "Clear After".
final class CustomStatusViewController: StackScreenViewController, UITextFieldDelegate {
    var onDone: (() -> Void)?
    private var emoji = "speech_balloon"
    private let emojiButton = UIButton(type: .custom)
    private let field = ThemedTextField(placeholder: "Set a custom status")
    private var duration = "today"
    private var clearRow: MenuRow!

    private static let suggestions: [(String, String, String)] = [
        ("calendar", "In a meeting", "one_hour"), ("hamburger", "Out for lunch", "thirty_minutes"),
        ("sneezing_face", "Out sick", "today"), ("house", "Working from home", "today"),
        ("palm_tree", "On a vacation", "this_week"),
    ]
    private static let durations: [(String, String)] = [
        ("", "Don't clear"), ("thirty_minutes", "30 minutes"), ("one_hour", "1 hour"),
        ("four_hours", "4 hours"), ("today", "Today"), ("this_week", "This week"),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Set a custom status"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Done", primaryAction: UIAction { [weak self] _ in self?.save() })
        if let current = AppSession.shared.me?.customStatus {
            emoji = current.emoji.isEmpty ? emoji : current.emoji
            field.text = current.text
        }
        emojiButton.titleLabel?.font = .systemFont(ofSize: 24)
        emojiButton.addAction(UIAction { [weak self] _ in
            let picker = EmojiPickerViewController()
            picker.onPick = { name in self?.emoji = name; self?.refreshEmoji() }
            self?.present(picker, animated: true)
        }, for: .primaryActionTriggered)
        emojiButton.widthAnchor.constraint(equalToConstant: 48).isActive = true
        emojiButton.accessibilityLabel = "Choose emoji"
        field.delegate = self
        field.returnKeyType = .done
        field.clearButtonMode = .whileEditing
        let row = UIStackView(arrangedSubviews: [emojiButton, field])
        row.spacing = 8
        let wrap = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 20),
            row.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -8),
            row.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -20),
        ])
        stack.addArrangedSubview(wrap)
        clearRow = MenuRow(icon: "clock-outline", title: "Clear After", detail: "Today", accessory: .chevron) { [weak self] in
            self?.pickDuration()
        }
        stack.addArrangedSubview(clearRow)
        addSectionTitle("Suggestions")
        for (e, text, d) in Self.suggestions {
            let r = MenuRow(icon: nil, title: "\(EmojiStore.shared.unicode(for: e) ?? "")  \(text)",
                            detail: Self.durations.first { $0.0 == d }?.1) { [weak self] in
                self?.emoji = e
                self?.field.text = text
                self?.duration = d
                self?.refreshEmoji()
            }
            stack.addArrangedSubview(r)
        }
        refreshEmoji()
    }

    private func refreshEmoji() {
        emojiButton.setTitle(EmojiStore.shared.unicode(for: emoji) ?? "💬", for: .normal)
        clearRow.setDetail(Self.durations.first { $0.0 == duration }?.1 ?? "")
    }

    private func pickDuration() {
        presentOptions(Self.durations.map { key, label in
            .init(icon: "clock-outline", title: label) { [weak self] in self?.duration = key; self?.refreshEmoji() }
        }, title: "Clear After")
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool { save(); return true }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        ((textField.text ?? "") as NSString).replacingCharacters(in: range, with: string).count <= 100
    }

    private func expiry() -> Date? {
        let cal = Calendar.current
        switch duration {
        case "thirty_minutes": return Date().addingTimeInterval(1800)
        case "one_hour": return Date().addingTimeInterval(3600)
        case "four_hours": return Date().addingTimeInterval(4 * 3600)
        case "today": return cal.date(bySettingHour: 23, minute: 59, second: 59, of: Date())
        case "this_week":
            let weekday = cal.component(.weekday, from: Date())
            let end = cal.date(byAdding: .day, value: 7 - weekday, to: Date()) ?? Date()
            return cal.date(bySettingHour: 23, minute: 59, second: 59, of: end)
        default: return nil
        }
    }

    private func save() {
        let text = (field.text ?? "").trimmingCharacters(in: .whitespaces)
        Task {
            do {
                if text.isEmpty && emoji == "speech_balloon" { try await AppSession.shared.client.clearCustomStatus() }
                else { try await AppSession.shared.client.setCustomStatus(emoji: emoji, text: text, duration: duration, expiresAt: expiry()) }
                onDone?()
                dismiss(animated: true)
            } catch { showError(error) }
        }
    }
}

/// Your Profile (`screens/edit_profile`): first name, last name, username, nickname, position.
final class EditProfileViewController: StackScreenViewController {
    private var fields: [(key: String, field: ThemedTextField)] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Edit Profile"
        guard let me = AppSession.shared.me else { return }
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", primaryAction: UIAction { [weak self] _ in self?.save() })
        let avatar = AvatarView(size: 120)
        avatar.setUser(me.id, pictureUpdate: me.lastPictureUpdate)
        let wrap = UIView()
        wrap.addSubview(avatar)
        NSLayoutConstraint.activate([
            avatar.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 24),
            avatar.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -16),
            avatar.centerXAnchor.constraint(equalTo: wrap.centerXAnchor),
        ])
        stack.addArrangedSubview(wrap)
        func add(_ key: String, _ label: String, _ value: String?, enabled: Bool = true) {
            let caption = UILabel(label, Typography.style(.body, 75), color: Theme.current.centerChannelColor.opacity(0.64))
            addPadded(caption, top: 12, bottom: 4)
            let field = ThemedTextField(placeholder: label)
            field.text = value
            field.autocapitalizationType = key == "username" ? .none : .words
            field.autocorrectionType = .no
            field.isEnabled = enabled
            field.alpha = enabled ? 1 : 0.5
            let w = UIView()
            field.translatesAutoresizingMaskIntoConstraints = false
            w.addSubview(field)
            NSLayoutConstraint.activate([
                field.topAnchor.constraint(equalTo: w.topAnchor), field.bottomAnchor.constraint(equalTo: w.bottomAnchor),
                field.leadingAnchor.constraint(equalTo: w.leadingAnchor, constant: 20),
                field.trailingAnchor.constraint(equalTo: w.trailingAnchor, constant: -20),
            ])
            stack.addArrangedSubview(w)
            if enabled { fields.append((key, field)) }
        }
        add("first_name", "First Name", me.firstName)
        add("last_name", "Last Name", me.lastName)
        add("username", "Username", me.username)
        add("email", "Email", me.email, enabled: false)
        addText("Email must be updated using a web client or desktop application.", style: Typography.style(.body, 75), alpha: 0.56)
        add("nickname", "Nickname (optional)", me.nickname)
        add("position", "Position (optional)", me.position)
    }

    private func save() {
        var patch: [String: String] = [:]
        for (key, field) in fields { patch[key] = (field.text ?? "").trimmingCharacters(in: .whitespaces) }
        Task {
            do {
                let me = try await AppSession.shared.client.patchMe(patch)
                AppSession.shared.setMe(me)
                dismiss(animated: true)
            } catch { showError(error) }
        }
    }
}
