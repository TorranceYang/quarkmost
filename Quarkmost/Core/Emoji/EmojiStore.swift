import Foundation

/// The official app's emoji set (3,300 emoji, same short names and categories), bundled as JSON.
/// Loaded once, lazily and thread-safely; lookups are dictionary reads that are safe from any thread.
public final class EmojiStore: Sendable {
    public struct Emoji: Sendable, Hashable {
        public let names: [String]
        public let unicode: String
        public let category: Int
        public var name: String { names[0] }
        /// Variants with a Fitzpatrick modifier (🏻–🏿); the grid shows only the default yellow.
        public var hasSkinTone: Bool { unicode.unicodeScalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) } }
    }

    public static let shared = EmojiStore()

    public let emoji: [Emoji]
    public let categories: [String]
    private let byName: [String: Emoji]

    private init() {
        struct File: Decodable {
            struct E: Decodable { let n: [String]; let u: String; let c: Int }
            let categories: [String]
            let emoji: [E]
        }
        guard let url = Bundle.main.url(forResource: "emoji", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else {
            emoji = []; categories = []; byName = [:]
            return
        }
        emoji = file.emoji.map { Emoji(names: $0.n, unicode: $0.u, category: $0.c) }
        categories = file.categories
        var map: [String: Emoji] = [:]
        for e in emoji { for n in e.names where map[n] == nil { map[n] = e } }
        byName = map
    }

    public func unicode(for name: String) -> String? { byName[name]?.unicode }

    /// A standard or custom emoji the app can draw.
    public func exists(_ name: String) -> Bool { byName[name] != nil || CustomEmojiStore.shared.isCustom(name) }

    /// Exact name first, then prefix matches, then substring matches. Skin-tone variants are left out.
    public func search(_ query: String, limit: Int = 200) -> [Emoji] {
        let q = query.lowercased()
        let pool = emoji.filter { !$0.hasSkinTone }
        guard !q.isEmpty else { return Array(pool.prefix(limit)) }
        func rank(_ e: Emoji) -> Int? {
            if e.names.contains(q) { return 0 }
            if e.names.contains(where: { $0.hasPrefix(q) }) { return 1 }
            if e.names.contains(where: { $0.contains("_" + q) }) { return 2 }
            if e.names.contains(where: { $0.contains(q) }) { return 3 }
            return nil
        }
        let ranked = pool.compactMap { e in rank(e).map { (e, $0) } }
        return Array(ranked.enumerated().sorted { ($0.element.1, $0.offset) < ($1.element.1, $1.offset) }
            .map(\.element.0).prefix(limit))
    }

    // MARK: Recent emoji (per device, like the official app)

    private static let recentKey = "recentEmoji"
    private static let defaults = ["+1", "smile", "white_check_mark", "heart", "joy", "eyes"]

    public var recent: [String] {
        (UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []) + Self.defaults
            .filter { !(UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []).contains($0) }
    }

    public func noteUsed(_ name: String) {
        var list = UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []
        list.removeAll { $0 == name }
        list.insert(name, at: 0)
        UserDefaults.standard.set(Array(list.prefix(20)), forKey: Self.recentKey)
    }

    /// Display names used by the picker's section headers.
    public static func title(forCategory c: String) -> String {
        switch c {
        case "smileys-emotion": "Smileys & Emotion"
        case "people-body": "People & Body"
        case "component": "Components"
        case "animals-nature": "Animals & Nature"
        case "food-drink": "Food & Drink"
        case "travel-places": "Travel & Places"
        case "activities": "Activities"
        case "objects": "Objects"
        case "symbols": "Symbols"
        case "flags": "Flags"
        default: c.capitalized
        }
    }
}
