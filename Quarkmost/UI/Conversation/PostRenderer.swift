import UIKit

/// Fonts and colors the renderer needs, captured on the main thread so rendering can run anywhere.
struct RenderStyle: Sendable {
    let body: UIFont, bodyBold: UIFont, bodyItalic: UIFont, bodyBoldItalic: UIFont
    let code: UIFont, small: UIFont, smallBold: UIFont
    let headings: [UIFont]           // h1…h6
    let bodyLineHeight: CGFloat
    let text: UIColor, secondary: UIColor, link: UIColor
    let codeBackground: UIColor, quoteBar: UIColor
    let mentionHighlightBg: UIColor, mentionHighlightLink: UIColor
    let myUsername: String

    @MainActor static func current(myUsername: String) -> RenderStyle {
        let theme = Theme.current
        let body = Typography.style(.body, 200)
        func h(_ size: Int) -> UIFont { Typography.style(.heading, size).font }
        let mono = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        return RenderStyle(
            body: body.font, bodyBold: Typography.style(.body, 200, .semibold).font,
            bodyItalic: Typography.style(.body, 200, italic: true).font,
            bodyBoldItalic: Typography.style(.body, 200, .semibold, italic: true).font,
            code: UIFontMetrics(forTextStyle: .body).scaledFont(for: mono),
            small: Typography.style(.body, 75).font, smallBold: Typography.style(.body, 75, .semibold).font,
            headings: [h(700), h(600), h(500), h(400), h(300), h(200)],
            bodyLineHeight: body.lineHeight,
            text: theme.centerChannelColor, secondary: theme.centerChannelColor.opacity(0.64),
            link: theme.linkColor,
            codeBackground: theme.centerChannelColor.blended(over: theme.centerChannelBg, opacity: 0.06),
            quoteBar: theme.centerChannelColor.opacity(0.16),
            mentionHighlightBg: theme.mentionHighlightBg, mentionHighlightLink: theme.mentionHighlightLink,
            myUsername: myUsername)
    }
}

/// Custom attribute keys the message view draws itself (backgrounds that NSString drawing can't).
extension NSAttributedString.Key {
    static let codeBlock = NSAttributedString.Key("quarkmost.codeBlock")
    static let quote = NSAttributedString.Key("quarkmost.quote")
    static let mentionUser = NSAttributedString.Key("quarkmost.mention")
    static let channelMention = NSAttributedString.Key("quarkmost.channelMention")
    static let customEmoji = NSAttributedString.Key("quarkmost.customEmoji")
    static let hashtag = NSAttributedString.Key("quarkmost.hashtag")
}

/// Mattermost-flavored markdown → NSAttributedString. Pure function of its inputs; safe off the main thread.
enum PostRenderer {
    static func render(_ markdown: String, style: RenderStyle, baseColor: UIColor? = nil) -> NSAttributedString {
        let textColor = baseColor ?? style.text
        let source = hardenLineBreaks(markdown)
        guard let parsed = try? AttributedString(
            markdown: source,
            options: .init(allowsExtendedAttributes: false, interpretedSyntax: .full,
                           failurePolicy: .returnPartiallyParsedIfPossible)) else {
            return NSAttributedString(string: markdown, attributes: paragraphAttrs(style.body, textColor, style))
        }

        let out = NSMutableAttributedString()
        var lastBlock: Int?
        var lastListItem: Int?
        var lastRow: Int?
        var lastCell: Int?

        for run in parsed.runs {
            var text = String(parsed[run.range].characters)
            let blocks = run.presentationIntent?.components ?? []
            let blockId = blocks.first?.identity

            // Tables: one line per row, cells separated by a thin bar; header row in bold.
            var rowId: Int?, cellId: Int?, headerRow = false
            for b in blocks {
                switch b.kind {
                case .tableHeaderRow: rowId = b.identity; headerRow = true
                case .tableRow: rowId = b.identity
                case .tableCell: cellId = b.identity
                default: break
                }
            }
            let sameRow = rowId != nil && rowId == lastRow
            if sameRow {
                if cellId != lastCell {
                    out.append(NSAttributedString(string: "  │  ", attributes: [.font: style.body, .foregroundColor: style.quoteBar]))
                }
            } else if let blockId, let lastBlock, blockId != lastBlock {
                // Separate blocks the way the official app spaces paragraphs.
                out.append(NSAttributedString(string: "\n", attributes: paragraphAttrs(style.body, textColor, style)))
            }
            lastRow = rowId
            lastCell = cellId

            var font = headerRow ? style.bodyBold : style.body
            var color = textColor
            var attrs: [NSAttributedString.Key: Any] = [:]
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            paragraph.minimumLineHeight = style.bodyLineHeight
            paragraph.paragraphSpacing = 6

            for block in blocks {
                switch block.kind {
                case .header(let level):
                    font = style.headings[min(max(level, 1), 6) - 1]
                    paragraph.minimumLineHeight = 0
                    paragraph.paragraphSpacingBefore = 4
                case .codeBlock:
                    font = style.code
                    attrs[.codeBlock] = true
                    paragraph.minimumLineHeight = 0
                    paragraph.firstLineHeadIndent = 10
                    paragraph.headIndent = 10
                    paragraph.tailIndent = -10
                    paragraph.lineBreakMode = .byCharWrapping
                    if text.hasSuffix("\n") { text.removeLast() }
                case .blockQuote:
                    attrs[.quote] = true
                    paragraph.firstLineHeadIndent += 14
                    paragraph.headIndent += 14
                    color = style.secondary
                case .listItem(let ordinal):
                    if lastListItem != block.identity {
                        let ordered = blocks.contains { if case .orderedList = $0.kind { return true }; return false }
                        text = (ordered ? "\(ordinal). " : "•  ") + text
                        lastListItem = block.identity
                    }
                    let depth = blocks.filter { if case .listItem = $0.kind { return true }; return false }.count
                    paragraph.firstLineHeadIndent = CGFloat(depth - 1) * 18 + 4
                    paragraph.headIndent = CGFloat(depth - 1) * 18 + 22
                    paragraph.paragraphSpacing = 2
                case .thematicBreak:
                    text = "———"
                    color = style.secondary
                default:
                    break
                }
            }

            if let inline = run.inlinePresentationIntent {
                let bold = inline.contains(.stronglyEmphasized)
                let italic = inline.contains(.emphasized)
                if bold && italic { font = style.bodyBoldItalic }
                else if bold { font = font == style.body ? style.bodyBold : font.withTraits(.traitBold) }
                else if italic { font = font == style.body ? style.bodyItalic : font.withTraits(.traitItalic) }
                if inline.contains(.code) {
                    font = style.code
                    attrs[.backgroundColor] = style.codeBackground
                }
                if inline.contains(.strikethrough) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                if inline.contains(.lineBreak) { text = "\u{2028}" }   // line separator keeps the paragraph
            }
            if let image = run.imageURL {
                // The picture itself is laid out under the message; here it's a link with its alt text.
                attrs[.link] = image
                color = style.link
                if text.isEmpty || text == "\u{FFFC}" { text = "image" }
            }
            if let url = run.link {
                attrs[.link] = url
                color = style.link
            }
            attrs[.font] = font
            attrs[.foregroundColor] = color
            attrs[.paragraphStyle] = paragraph
            out.append(NSAttributedString(string: text, attributes: attrs))
            lastBlock = blockId
        }

        highlightCode(out, style: style)
        replaceEmojiShortcodes(out, style: style)
        decorateMentionsAndLinks(out, style: style)
        makeJumboIfEmojiOnly(out)
        return out
    }

    private static let codeComment = try! NSRegularExpression(pattern: "(//[^\\n]*|#[^\\n]*|/\\*[\\s\\S]*?\\*/|--[^\\n]*)")
    private static let codeString = try! NSRegularExpression(pattern: "(\"(?:\\\\.|[^\"\\\\\\n])*\"|'(?:\\\\.|[^'\\\\\\n])*'|`[^`\\n]*`)")
    private static let codeNumber = try! NSRegularExpression(pattern: "\\b\\d+(?:\\.\\d+)?\\b")
    private static let codeKeyword = try! NSRegularExpression(pattern: "\\b(func|function|def|class|struct|enum|protocol|extension|interface|import|from|export|return|if|else|elif|for|while|do|switch|case|default|break|continue|let|var|const|static|public|private|protected|internal|final|override|async|await|try|catch|throw|throws|finally|new|nil|null|None|true|false|True|False|self|this|super|in|is|as|not|and|or|guard|defer|where|typealias|package|go|chan|select|type|void|int|string|bool|float|double|echo|then|fi|done|esac|SELECT|FROM|WHERE|INSERT|UPDATE|DELETE|JOIN|CREATE|TABLE|AND|OR|NOT|NULL)\\b")

    /// Light syntax coloring for fenced code blocks (GitHub-style colors, adjusted for dark themes).
    /// Language-agnostic: comments, strings, numbers and common keywords.
    private static func highlightCode(_ text: NSMutableAttributedString, style: RenderStyle) {
        let dark = style.codeBackground.luminance < 0.5
        let comment = dark ? UIColor.hex(0x8B949E) : UIColor.hex(0x6A737D)
        let string = dark ? UIColor.hex(0xA5D6FF) : UIColor.hex(0x032F62)
        let number = dark ? UIColor.hex(0x79C0FF) : UIColor.hex(0x005CC5)
        let keyword = dark ? UIColor.hex(0xFF7B72) : UIColor.hex(0xD73A49)
        let full = NSRange(location: 0, length: text.length)
        var blocks: [NSRange] = []
        text.enumerateAttribute(.codeBlock, in: full) { value, range, _ in if value != nil { blocks.append(range) } }
        let source = text.string
        for block in blocks where block.length < 20_000 {
            var taken: [NSRange] = []
            func paint(_ regex: NSRegularExpression, _ color: UIColor, exclusive: Bool) {
                for m in regex.matches(in: source, range: block) {
                    if taken.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) { continue }
                    text.addAttribute(.foregroundColor, value: color, range: m.range)
                    if exclusive { taken.append(m.range) }
                }
            }
            paint(codeString, string, exclusive: true)
            paint(codeComment, comment, exclusive: true)
            paint(codeKeyword, keyword, exclusive: false)
            paint(codeNumber, number, exclusive: false)
        }
    }

    private static let shortcodeRegex = try! NSRegularExpression(pattern: ":([a-zA-Z0-9_+\\-]+):")

    /// `:smile:` → 😄, outside code. Unknown names (custom emoji for now) stay as typed.
    private static func replaceEmojiShortcodes(_ text: NSMutableAttributedString, style: RenderStyle) {
        let matches = shortcodeRegex.matches(in: text.string, range: NSRange(location: 0, length: text.length))
        for match in matches.reversed() {
            let name = (text.string as NSString).substring(with: match.range(at: 1)).lowercased()
            guard text.attribute(.codeBlock, at: match.range.location, effectiveRange: nil) == nil,
                  (text.attribute(.font, at: match.range.location, effectiveRange: nil) as? UIFont) != style.code
            else { continue }
            let attrs = text.attributes(at: match.range.location, effectiveRange: nil)
            if let emoji = EmojiStore.shared.unicode(for: name) {
                text.replaceCharacters(in: match.range, with: NSAttributedString(string: emoji, attributes: attrs))
            } else if let image = CustomEmojiStore.shared.image(name) {
                let font = (attrs[.font] as? UIFont) ?? style.body
                text.replaceCharacters(in: match.range, with: customEmoji(image, name: name, font: font, attrs: attrs))
            }
        }
    }

    /// An inline image the height of the line's capitals, sitting on the baseline like a glyph.
    static func customEmoji(_ image: UIImage, name: String, font: UIFont,
                            attrs: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.image = image
        let side = (font.pointSize * 1.25).rounded()
        attachment.bounds = CGRect(x: 0, y: (font.capHeight - side) / 2, width: side, height: side)
        let out = NSMutableAttributedString(attachment: attachment)
        var a = attrs
        a[.customEmoji] = name
        out.addAttributes(a, range: NSRange(location: 0, length: out.length))
        return out
    }

    /// Messages made only of emoji render at 50pt, like the official jumbo emoji.
    private static func makeJumboIfEmojiOnly(_ text: NSMutableAttributedString) {
        let trimmed = text.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 8,
              trimmed.allSatisfy({ $0.isWhitespace || $0.isEmojiCharacter || $0 == "\u{FFFC}" }) else { return }
        let full = NSRange(location: 0, length: text.length)
        text.enumerateAttribute(.attachment, in: full) { value, _, _ in
            guard let a = value as? NSTextAttachment else { return }
            a.bounds = CGRect(x: 0, y: -8, width: 50, height: 50)
        }
        text.enumerateAttribute(.font, in: full) { value, range, _ in
            let base = (value as? UIFont) ?? UIFont.systemFont(ofSize: 16)
            text.addAttribute(.font, value: base.withSize(50), range: range)
        }
        let p = NSMutableParagraphStyle()
        p.minimumLineHeight = 60
        p.maximumLineHeight = 60
        text.addAttribute(.paragraphStyle, value: p, range: full)
    }

    /// Mattermost treats every newline as a line break; CommonMark folds single newlines into spaces.
    /// Adds hard breaks outside fenced code blocks.
    static func hardenLineBreaks(_ s: String) -> String {
        var inFence = false
        var lines = s.components(separatedBy: "\n")
        for i in lines.indices {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { inFence.toggle(); continue }
            guard !inFence, i < lines.count - 1, !trimmed.isEmpty,
                  !lines[i + 1].trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            lines[i] += "  "
        }
        return lines.joined(separator: "\n")
    }

    private static let mentionRegex = try! NSRegularExpression(pattern: "(?<![\\w@])@([a-z0-9][a-z0-9._-]*[a-z0-9]|[a-z0-9])",
                                                               options: [.caseInsensitive])
    private static let channelRegex = try! NSRegularExpression(pattern: "(?<![\\w~])~([a-z0-9][a-z0-9_-]*)",
                                                               options: [.caseInsensitive])
    private static let hashtagRegex = try! NSRegularExpression(pattern: "(?<![\\w#/])#[A-Za-z][\\w-]{2,}")
    private static let linkDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// @mentions in link color (highlighted when they mention you or @here/@channel/@all),
    /// ~channel links, and bare URLs.
    private static func decorateMentionsAndLinks(_ text: NSMutableAttributedString, style: RenderStyle) {
        let string = text.string as NSString
        let full = NSRange(location: 0, length: string.length)
        func isCode(_ range: NSRange) -> Bool {
            text.attribute(.codeBlock, at: range.location, effectiveRange: nil) != nil
                || (text.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont) == style.code
        }
        for match in mentionRegex.matches(in: string as String, range: full) where !isCode(match.range) {
            var name = string.substring(with: match.range(at: 1)).lowercased()
            if name.hasSuffix(".") { name.removeLast() }
            let me = name == style.myUsername.lowercased() || ["here", "channel", "all"].contains(name)
            let range = NSRange(location: match.range.location, length: name.count + 1)
            text.addAttribute(.mentionUser, value: name, range: range)
            if me {
                text.addAttributes([.backgroundColor: style.mentionHighlightBg,
                                    .foregroundColor: style.mentionHighlightLink], range: range)
            } else {
                text.addAttribute(.foregroundColor, value: style.link, range: range)
            }
        }
        for match in channelRegex.matches(in: string as String, range: full) where !isCode(match.range) {
            text.addAttributes([.channelMention: string.substring(with: match.range(at: 1)),
                                .foregroundColor: style.link], range: match.range)
        }
        for match in hashtagRegex.matches(in: string as String, range: full) where !isCode(match.range) {
            guard text.attribute(.link, at: match.range.location, effectiveRange: nil) == nil else { continue }
            text.addAttributes([.hashtag: string.substring(with: match.range), .foregroundColor: style.link], range: match.range)
        }
        for match in linkDetector.matches(in: string as String, range: full) where !isCode(match.range) {
            guard let url = match.url, text.attribute(.link, at: match.range.location, effectiveRange: nil) == nil
            else { continue }
            text.addAttributes([.link: url, .foregroundColor: style.link], range: match.range)
        }
    }

    private static func paragraphAttrs(_ font: UIFont, _ color: UIColor, _ style: RenderStyle) -> [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        p.minimumLineHeight = style.bodyLineHeight
        return [.font: font, .foregroundColor: color, .paragraphStyle: p]
    }
}

extension Character {
    /// True for characters that render as emoji (not digits or # which are technically "emoji").
    var isEmojiCharacter: Bool {
        guard let first = unicodeScalars.first else { return false }
        return first.properties.isEmojiPresentation
            || (first.properties.isEmoji && (unicodeScalars.count > 1 || first.value > 0x238C))
    }
}
