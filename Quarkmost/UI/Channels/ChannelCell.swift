import UIKit

/// One sidebar row, matching the official `channel_item`: 24pt icon or avatar, 12pt gap,
/// Open Sans 16 name, white mention pill on the right; 18/20 side padding.
///
/// Built for scrolling speed: frames are set by hand in `layoutSubviews` (no Auto Layout solve
/// per cell), avatars arrive pre-decoded and pre-clipped from `ImageLoader`, and rounded shapes
/// use `layer.backgroundColor` + `cornerRadius` without `masksToBounds`, so nothing renders off-screen.
final class ChannelCell: UICollectionViewCell {
    private let activeBackground = UIView()
    private let activeBorder = UIView()
    private let icon = UIImageView()
    private let avatar = UIImageView()
    private let statusRing = UIView()
    private let statusIcon = UIImageView()
    private let groupLabel = UILabel()
    private let nameLabel = UILabel()
    private let badge = UILabel()

    private var row: SidebarChannel?
    private var active = false
    private var avatarTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(activeBackground)
        contentView.addSubview(activeBorder)
        [icon, avatar, groupLabel, nameLabel, badge].forEach(contentView.addSubview)
        contentView.addSubview(statusRing)
        statusRing.addSubview(statusIcon)
        groupLabel.textAlignment = .center
        groupLabel.layer.cornerRadius = 4
        badge.textAlignment = .center
        badge.layer.borderWidth = 2
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarTask?.cancel()
        avatarTask = nil
    }

    /// Press feedback like React Native's TouchableOpacity (dims to 0.2, fades back).
    override var isHighlighted: Bool {
        didSet {
            guard oldValue != isHighlighted else { return }
            if isHighlighted {
                contentView.alpha = 0.2
            } else {
                UIView.animate(withDuration: 0.15, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                    self.contentView.alpha = 1
                }
            }
        }
    }

    func configure(_ row: SidebarChannel, theme: Theme, active: Bool, iconOverride: String? = nil) {
        self.row = row
        self.active = active
        let bold = row.unread || row.mentions > 0

        // Text: 72% normally, unread text color when bold, full when active, 32% when muted.
        var textColor = theme.sidebarText.opacity(0.72)
        if bold { textColor = theme.sidebarUnreadText }
        if active { textColor = theme.sidebarText }
        if row.muted { textColor = theme.sidebarText.opacity(0.32) }
        let style = Typography.style(.body, 200, bold && !row.muted ? .semibold : .regular)
        nameLabel.attributedText = NSAttributedString(string: row.name, attributes: style.attributes(color: textColor))

        var iconColor = theme.sidebarText.opacity(0.4)
        if bold { iconColor = theme.sidebarUnreadText }
        if active { iconColor = theme.sidebarText }
        if row.muted { iconColor = theme.sidebarText.opacity(0.32 * 0.4) }

        icon.isHidden = true
        avatar.isHidden = true
        statusRing.isHidden = true
        groupLabel.isHidden = true

        if let iconOverride {
            icon.isHidden = false
            icon.image = CompassIcon.image(iconOverride, size: 24)
            icon.tintColor = iconColor
        } else {
        switch row.type {
        case .open, .privateChannel:
            icon.isHidden = false
            icon.image = CompassIcon.image(row.type == .open ? "globe" : "lock-outline", size: 24)
            icon.tintColor = iconColor
        case .group:
            groupLabel.isHidden = false
            groupLabel.text = "\(row.groupSize)"
            groupLabel.font = Typography.style(.body, 75, .semibold, scaled: false).font
            groupLabel.textColor = bold || active ? theme.sidebarUnreadText : theme.sidebarText.opacity(0.4)
            groupLabel.layer.backgroundColor = theme.sidebarText.opacity(bold ? 0.3 : 0.16).cgColor
            groupLabel.alpha = row.muted ? 0.32 : 1
        case .direct:
            if row.teammateDeleted {
                icon.isHidden = false
                icon.image = CompassIcon.image("archive-outline", size: 24)
                icon.tintColor = iconColor
            } else {
                configureAvatar(row, theme: theme)
            }
        }
        }

        if row.mentions > 0 {
            badge.isHidden = false
            badge.text = row.mentions > 99 ? "99+" : "\(row.mentions)"
            badge.font = UIFont(name: "OpenSans-Bold", size: 12)
            badge.textColor = theme.mentionColor
            badge.layer.backgroundColor = theme.mentionBg.cgColor
            badge.layer.borderColor = (active ? activeBackgroundColor(theme) : theme.sidebarBg).cgColor
            badge.alpha = row.muted ? 0.32 : 1
        } else {
            badge.isHidden = true
        }

        activeBackground.isHidden = !active
        activeBorder.isHidden = !active
        activeBackground.backgroundColor = activeBackgroundColor(theme)
        activeBorder.backgroundColor = theme.sidebarTextActiveBorder

        accessibilityLabel = row.name
        accessibilityValue = [row.mentions > 0 ? "\(row.mentions) mentions" : (row.unread ? "unread" : nil),
                              row.muted ? "muted" : nil, row.teammateStatus].compactMap { $0 }.joined(separator: ", ")
        accessibilityTraits = active ? [.button, .selected] : .button
        setNeedsLayout()
    }

    /// 10% active color blended into the sidebar, as a flat color (no alpha blending while scrolling).
    private func activeBackgroundColor(_ theme: Theme) -> UIColor {
        theme.sidebarTextActiveColor.blended(over: theme.sidebarBg, opacity: 0.1)
    }

    private func configureAvatar(_ row: SidebarChannel, theme: Theme) {
        guard let userId = row.teammateId else { return }
        avatar.isHidden = false
        let url = ImageLoader.profileImageURL(userId: userId, lastPictureUpdate: row.teammatePictureUpdate)
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 3
        if let cached = ImageLoader.shared.cached(url, pointSize: 24, scale: scale) {
            avatar.image = cached
            avatar.tintColor = nil
        } else {
            avatar.image = CompassIcon.image("account-outline", size: 24)
            avatar.tintColor = theme.sidebarText.opacity(0.4)
            avatarTask = Task { [weak self] in
                guard let image = await ImageLoader.shared.image(url, pointSize: 24, scale: scale),
                      !Task.isCancelled, let self, self.row?.teammateId == userId else { return }
                UIView.transition(with: self.avatar, duration: 0.15, options: .transitionCrossDissolve) {
                    self.avatar.image = image
                }
            }
        }
        avatar.alpha = row.muted ? 0.32 : 1

        // Status: 12pt icon on a ring of the row's background color, offset 3pt past the corner.
        // Bots have no status.
        guard !row.teammateIsBot, let status = row.teammateStatus else { return }
        let (name, color): (String, UIColor) = switch status {
        case "online": ("check-circle", theme.onlineIndicator)
        case "away": ("clock", theme.awayIndicator)
        case "dnd": ("minus-circle", theme.dndIndicator)
        default: ("circle-outline", theme.sidebarText.opacity(0.32))
        }
        statusRing.isHidden = false
        statusRing.layer.backgroundColor = (active ? activeBackgroundColor(theme) : theme.sidebarBg).cgColor
        statusIcon.image = CompassIcon.image(name, size: 12)
        statusIcon.tintColor = color
        statusRing.alpha = row.muted ? 0.32 : 1
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = contentView.bounds
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        func place(_ frame: CGRect) -> CGRect {
            rtl ? CGRect(x: b.width - frame.maxX, y: frame.minY, width: frame.width, height: frame.height) : frame
        }

        activeBackground.frame = b
        activeBorder.frame = place(CGRect(x: 0, y: 0, width: 5, height: b.height))

        let left: CGFloat = 18, right: CGFloat = 20, iconSize: CGFloat = 24
        let iconFrame = CGRect(x: left, y: ((b.height - iconSize) / 2).rounded(), width: iconSize, height: iconSize)
        icon.frame = place(iconFrame)
        avatar.frame = place(iconFrame)
        groupLabel.frame = place(iconFrame)

        let ringSize: CGFloat = 14
        let ring = CGRect(x: iconFrame.maxX + 3 - ringSize, y: iconFrame.maxY + 3 - ringSize,
                          width: ringSize, height: ringSize)
        statusRing.frame = place(ring)
        statusRing.layer.cornerRadius = ringSize / 2
        statusIcon.frame = CGRect(x: 1, y: 1, width: 12, height: 12)

        var trailing = b.width - right
        if !badge.isHidden {
            let textWidth = badge.intrinsicContentSize.width
            let width = max(26, textWidth + 10 + 4)   // paddingHorizontal 5 + 2pt border each side
            let frame = CGRect(x: trailing - width, y: ((b.height - 22) / 2).rounded(), width: width, height: 22)
            badge.frame = place(frame)
            badge.layer.cornerRadius = 11
            trailing = frame.minX - 4
        }
        let nameX = iconFrame.maxX + 12
        let nameHeight = nameLabel.intrinsicContentSize.height
        nameLabel.frame = place(CGRect(x: nameX, y: ((b.height - nameHeight) / 2).rounded(),
                                       width: max(0, trailing - nameX), height: nameHeight))
    }
}
