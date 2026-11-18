import UIKit

/// Mattermost theme colors, same keys as the official apps (`app/constants/preferences.ts`).
/// Defaults to Denim; replaced by the user's own theme preference from the server when loaded,
/// so the app matches whatever theme they picked on desktop.
struct Theme: Equatable {
    var sidebarBg: UIColor
    var sidebarText: UIColor
    var sidebarUnreadText: UIColor
    var sidebarTextHoverBg: UIColor
    var sidebarTextActiveBorder: UIColor
    var sidebarTextActiveColor: UIColor
    var sidebarHeaderBg: UIColor
    var sidebarHeaderTextColor: UIColor
    var sidebarTeamBarBg: UIColor
    var onlineIndicator: UIColor
    var awayIndicator: UIColor
    var dndIndicator: UIColor
    var mentionBg: UIColor
    var mentionColor: UIColor
    var centerChannelBg: UIColor
    var centerChannelColor: UIColor
    var newMessageSeparator: UIColor
    var linkColor: UIColor
    var buttonBg: UIColor
    var buttonColor: UIColor
    var errorTextColor: UIColor
    var mentionHighlightBg: UIColor
    var mentionHighlightLink: UIColor

    static let denim = Theme(
        sidebarBg: .hex(0x1E325C), sidebarText: .hex(0xFFFFFF), sidebarUnreadText: .hex(0xFFFFFF),
        sidebarTextHoverBg: .hex(0x28427B), sidebarTextActiveBorder: .hex(0x5D89EA),
        sidebarTextActiveColor: .hex(0xFFFFFF), sidebarHeaderBg: .hex(0x192A4D),
        sidebarHeaderTextColor: .hex(0xFFFFFF), sidebarTeamBarBg: .hex(0x162545),
        onlineIndicator: .hex(0x3DB887), awayIndicator: .hex(0xFFBC1F), dndIndicator: .hex(0xD24B4E),
        mentionBg: .hex(0xFFFFFF), mentionColor: .hex(0x1E325C), centerChannelBg: .hex(0xFFFFFF),
        centerChannelColor: .hex(0x3F4350), newMessageSeparator: .hex(0xCC8F00), linkColor: .hex(0x386FE5),
        buttonBg: .hex(0x1C58D9), buttonColor: .hex(0xFFFFFF), errorTextColor: .hex(0xD24B4E),
        mentionHighlightBg: .hex(0xFFD470), mentionHighlightLink: .hex(0x1B1D22))

    @MainActor static var current = Theme.denim

    /// Builds a theme from the JSON string stored in the user's `theme` preference.
    /// Missing or malformed keys keep the Denim value.
    init?(preferenceJSON: String) {
        guard let data = preferenceJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var theme = Theme.denim
        func set(_ key: String, _ path: WritableKeyPath<Theme, UIColor>) {
            if let hex = dict[key] as? String, let color = UIColor(hexString: hex) { theme[keyPath: path] = color }
        }
        set("sidebarBg", \.sidebarBg); set("sidebarText", \.sidebarText)
        set("sidebarUnreadText", \.sidebarUnreadText); set("sidebarTextHoverBg", \.sidebarTextHoverBg)
        set("sidebarTextActiveBorder", \.sidebarTextActiveBorder); set("sidebarTextActiveColor", \.sidebarTextActiveColor)
        set("sidebarHeaderBg", \.sidebarHeaderBg); set("sidebarHeaderTextColor", \.sidebarHeaderTextColor)
        set("sidebarTeamBarBg", \.sidebarTeamBarBg); set("onlineIndicator", \.onlineIndicator)
        set("awayIndicator", \.awayIndicator); set("dndIndicator", \.dndIndicator)
        set("mentionBg", \.mentionBg); set("mentionBj", \.mentionBg)   // legacy misspelling still in old prefs
        set("mentionColor", \.mentionColor); set("centerChannelBg", \.centerChannelBg)
        set("centerChannelColor", \.centerChannelColor); set("newMessageSeparator", \.newMessageSeparator)
        set("linkColor", \.linkColor); set("buttonBg", \.buttonBg); set("buttonColor", \.buttonColor)
        set("errorTextColor", \.errorTextColor); set("mentionHighlightBg", \.mentionHighlightBg)
        set("mentionHighlightLink", \.mentionHighlightLink)
        self = theme
    }

    private init(sidebarBg: UIColor, sidebarText: UIColor, sidebarUnreadText: UIColor, sidebarTextHoverBg: UIColor,
                 sidebarTextActiveBorder: UIColor, sidebarTextActiveColor: UIColor, sidebarHeaderBg: UIColor,
                 sidebarHeaderTextColor: UIColor, sidebarTeamBarBg: UIColor, onlineIndicator: UIColor,
                 awayIndicator: UIColor, dndIndicator: UIColor, mentionBg: UIColor, mentionColor: UIColor,
                 centerChannelBg: UIColor, centerChannelColor: UIColor, newMessageSeparator: UIColor,
                 linkColor: UIColor, buttonBg: UIColor, buttonColor: UIColor, errorTextColor: UIColor,
                 mentionHighlightBg: UIColor, mentionHighlightLink: UIColor) {
        self.sidebarBg = sidebarBg; self.sidebarText = sidebarText; self.sidebarUnreadText = sidebarUnreadText
        self.sidebarTextHoverBg = sidebarTextHoverBg; self.sidebarTextActiveBorder = sidebarTextActiveBorder
        self.sidebarTextActiveColor = sidebarTextActiveColor; self.sidebarHeaderBg = sidebarHeaderBg
        self.sidebarHeaderTextColor = sidebarHeaderTextColor; self.sidebarTeamBarBg = sidebarTeamBarBg
        self.onlineIndicator = onlineIndicator; self.awayIndicator = awayIndicator; self.dndIndicator = dndIndicator
        self.mentionBg = mentionBg; self.mentionColor = mentionColor; self.centerChannelBg = centerChannelBg
        self.centerChannelColor = centerChannelColor; self.newMessageSeparator = newMessageSeparator
        self.linkColor = linkColor; self.buttonBg = buttonBg; self.buttonColor = buttonColor
        self.errorTextColor = errorTextColor; self.mentionHighlightBg = mentionHighlightBg
        self.mentionHighlightLink = mentionHighlightLink
    }

    /// Whether status-bar content over the sidebar color should be light.
    var sidebarIsDark: Bool { sidebarBg.luminance < 0.5 }
}

extension UIColor {
    static func hex(_ value: UInt32) -> UIColor {
        UIColor(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    convenience init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    /// Same as the official app's `changeOpacity(color, opacity)`.
    func opacity(_ alpha: CGFloat) -> UIColor { withAlphaComponent(alpha) }

    /// The official app blends some colors over a background instead of using alpha
    /// (`blendColors`); flat colors also avoid off-screen blending while scrolling.
    func blended(over background: UIColor, opacity: CGFloat) -> UIColor {
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        background.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r2 + (r1 - r2) * opacity, green: g2 + (g1 - g2) * opacity,
                       blue: b2 + (b1 - b2) * opacity, alpha: 1)
    }

    var luminance: CGFloat {
        var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }
}
