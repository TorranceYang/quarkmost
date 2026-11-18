import UIKit

/// Everything a message row needs, computed off the main thread: rendered text, measured heights,
/// and frames. Cells only assign these; they never measure or parse while scrolling.
struct PostLayout: @unchecked Sendable {   // NSAttributedString is immutable once built
    struct Attachment {
        let color: UIColor
        let text: NSAttributedString
        let frame: CGRect          // text frame, relative to the cell
        let barFrame: CGRect
    }
    struct ReactionChip {
        let name: String
        let emoji: String        // unicode, or ":name:" when it's a custom emoji (drawn from its image)
        let count: Int
        let mine: Bool
        let frame: CGRect
    }
    struct Image {
        let previewURL: URL
        let fullURL: URL
        let frame: CGRect
        let isVideo: Bool
    }
    struct File {
        let info: FileInfo
        let frame: CGRect
    }
    /// Bordered box drawn behind a link preview.
    struct Card {
        let frame: CGRect
        let url: URL?
    }

    let id: String
    let post: Post
    let consecutive: Bool
    let pending: Bool
    let failed: Bool
    let isSystem: Bool
    let authorId: String
    let avatarURL: URL?
    let top: CGFloat                    // extra space above the header (pinned/saved line)
    let preHeader: NSAttributedString?
    let background: UIColor?
    let name: NSAttributedString?       // nil for consecutive posts
    let time: NSAttributedString?
    let isBot: Bool
    let nameWidth: CGFloat
    let message: NSAttributedString
    let messageFrame: CGRect
    let attachments: [Attachment]
    let cards: [Card]
    let images: [Image]
    let files: [File]
    let reactions: [ReactionChip]
    let addReactionFrame: CGRect?
    let footer: NSAttributedString?
    let footerFrame: CGRect
    /// "Show more" / "Show less" under a very long message (`show_more_button`).
    let showMore: NSAttributedString?
    let showMoreFrame: CGRect
    /// Replies shown inline in the channel (collapsed threads off): the gray bar left of the body.
    let replyBarFrame: CGRect?
    let replyBarHighlight: Bool
    /// "Commented on X's message:" under the header of the first reply in a run.
    let commentedOn: NSAttributedString?
    let commentedOnFrame: CGRect
    /// Reply count at the right of a root post's header (collapsed threads off).
    let headerReplies: String?
    let height: CGFloat

    // Official measurements: 16pt side padding, 32pt avatar, 10pt gap → text starts at 58.
    static let side: CGFloat = 16
    static let avatar: CGFloat = 32
    static let textX: CGFloat = 16 + 32 + 10
}

/// Inputs for one post, gathered on the main thread.
struct PostInput: Sendable {
    let post: Post
    let consecutive: Bool
    let displayName: String
    let isBot: Bool
    let avatarURL: URL?
    let time: String
    let myUserId: String
    var isSaved = false
    var highlighted = false
    var failed = false
    var following = false
    var useImageProxy = false
    var expanded = false
    /// Collapsed reply threads on: thread footer and Follow; off: inline replies and header count.
    var collapsedThreads = true
    var replyBar: ReplyBar?
    var commentedOn: String?

    struct ReplyBar: Sendable {
        var first: Bool
        var last: Bool
        var highlight: Bool
    }
}

enum PostLayoutBuilder {
    private static let inlineImageRegex = try! NSRegularExpression(pattern: "!\\[[^\\]]*\\]\\((\\S+?)(?:\\s+\"[^\"]*\")?\\)")

    static func layout(_ input: PostInput, width: CGFloat, style: RenderStyle) -> PostLayout {
        let post = input.post
        // Inline replies are indented by the reply bar (3pt bar, 1pt before, 7pt after) as in `post/body`.
        let x0 = PostLayout.textX + (input.replyBar != nil ? 11 : 0)
        let textWidth = max(40, width - x0 - PostLayout.side)
        let systemColor = style.text.withAlphaComponent(0.6)

        // Pinned / saved line above the header.
        var top: CGFloat = 0
        var preHeader: NSAttributedString?
        let pinned = post.isPinned ?? false
        if pinned || input.isSaved {
            let text = pinned && input.isSaved ? "Pinned and Saved" : (pinned ? "Pinned" : "Saved")
            preHeader = NSAttributedString(string: text, attributes: [.font: style.small, .foregroundColor: style.link])
            top = 22
        }
        var background: UIColor?
        if input.highlighted { background = style.mentionHighlightBg.withAlphaComponent(0.5) }
        else if pinned || input.isSaved { background = style.mentionHighlightBg.withAlphaComponent(0.2) }

        // Message
        let message = NSMutableAttributedString(attributedString:
            post.message.isEmpty ? NSAttributedString() :
            PostRenderer.render(post.message, style: style, baseColor: post.isSystemMessage ? systemColor : nil))
        if post.isEdited && !post.isSystemMessage {
            message.append(NSAttributedString(string: " Edited", attributes: [
                .font: style.small, .foregroundColor: style.text.withAlphaComponent(0.56)]))
        }

        var y: CGFloat = top + (input.consecutive ? 2 : 10 + 24)
        var commentedOn: NSAttributedString?
        var commentedOnFrame = CGRect.zero
        if let rootAuthor = input.commentedOn, !input.consecutive {
            let apostrophe = rootAuthor.hasSuffix("s") ? "'" : "'s"
            commentedOn = NSAttributedString(string: "Commented on \(rootAuthor)\(apostrophe) message:",
                                             attributes: [.font: style.body, .foregroundColor: style.text.withAlphaComponent(0.65)])
            commentedOnFrame = CGRect(x: PostLayout.textX, y: y, width: width - PostLayout.textX - PostLayout.side, height: 21)
            y += 24
        }
        let bodyTop = y
        let fullHeight = message.length == 0 ? 0 : TextMeasure.height(message, width: textWidth)
        // Very long posts collapse to about half a screen until expanded.
        let isLong = fullHeight > 640
        let messageHeight = isLong && !input.expanded ? 400 : fullHeight
        let messageFrame = CGRect(x: x0, y: y, width: textWidth, height: messageHeight)
        y += messageHeight
        var showMore: NSAttributedString?
        var showMoreFrame = CGRect.zero
        if isLong {
            showMore = NSAttributedString(string: input.expanded ? "Show less" : "Show more",
                                          attributes: [.font: style.smallBold, .foregroundColor: style.link])
            y += 4
            showMoreFrame = CGRect(x: x0, y: y, width: textWidth, height: 28)
            y += 28
        }

        var images: [PostLayout.Image] = []
        func addImage(preview: URL, full: URL, w: CGFloat, h: CGFloat, maxHeight: CGFloat = 320, isVideo: Bool = false, x: CGFloat = x0, available: CGFloat? = nil) {
            let avail = available ?? textWidth
            let scale = min(1, avail / w, maxHeight / h)
            let size = CGSize(width: max(60, (w * scale).rounded()), height: max(40, (h * scale).rounded()))
            y += 6
            images.append(.init(previewURL: preview, fullURL: full, frame: CGRect(x: x, y: y, width: size.width, height: size.height), isVideo: isVideo))
            y += size.height
        }
        func external(_ raw: String) -> URL? {
            guard let url = URL(string: raw, relativeTo: ServerConfig.baseURL)?.absoluteURL else { return nil }
            guard input.useImageProxy, url.host != ServerConfig.baseURL.host else { return url }
            var c = URLComponents(url: ServerConfig.apiURL.appendingPathComponent("image"), resolvingAgainstBaseURL: false)!
            c.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
            return c.url
        }
        let imageMeta = post.metadata?.images ?? [:]

        // Markdown images in the message: shown under the text at their real size.
        let ns = post.message as NSString
        for m in inlineImageRegex.matches(in: post.message, range: NSRange(location: 0, length: ns.length)).prefix(4) {
            let raw = ns.substring(with: m.range(at: 1))
            guard let url = external(raw) else { continue }
            let meta = imageMeta[raw]
            addImage(preview: url, full: url, w: CGFloat(meta?.width ?? 320), h: CGFloat(meta?.height ?? 200))
        }

        // Bot/webhook attachments: 4pt color bar, then pretext/author/title/text/fields.
        var attachments: [PostLayout.Attachment] = []
        for a in post.attachments {
            if let pretext = a.pretext {
                let pre = PostRenderer.render(pretext, style: style)
                let h = TextMeasure.height(pre, width: textWidth)
                y += 6
                attachments.append(.init(color: .clear, text: pre,
                                         frame: CGRect(x: x0, y: y, width: textWidth, height: h),
                                         barFrame: .zero))
                y += h
            }
            let body = NSMutableAttributedString()
            func line(_ s: NSAttributedString) {
                if body.length > 0 { body.append(NSAttributedString(string: "\n", attributes: [.font: style.small])) }
                body.append(s)
            }
            if let author = a.authorName {
                line(NSAttributedString(string: author, attributes: [.font: style.smallBold, .foregroundColor: style.secondary]))
            }
            if let title = a.title {
                var attrs: [NSAttributedString.Key: Any] = [.font: style.bodyBold, .foregroundColor: style.text]
                if let link = a.titleLink.flatMap(URL.init(string:)) { attrs[.link] = link; attrs[.foregroundColor] = style.link }
                line(NSAttributedString(string: title, attributes: attrs))
            }
            if let text = a.text { line(PostRenderer.render(text, style: style)) }
            for field in a.fields {
                if !field.title.isEmpty {
                    line(NSAttributedString(string: field.title, attributes: [.font: style.bodyBold, .foregroundColor: style.text]))
                }
                line(PostRenderer.render(field.value, style: style))
            }
            if let footer = a.footer {
                line(NSAttributedString(string: footer, attributes: [.font: style.small, .foregroundColor: style.secondary]))
            }
            let imageRaw = a.imageURL ?? a.thumbURL
            guard body.length > 0 || imageRaw != nil else { continue }
            let innerWidth = textWidth - 12 - 8
            let h = body.length > 0 ? TextMeasure.height(body, width: innerWidth) : 0
            y += 8
            let startY = y
            let color = a.color.flatMap(Self.attachmentColor) ?? style.text.withAlphaComponent(0.16)
            let textFrame = CGRect(x: x0 + 12, y: y + 6, width: innerWidth, height: h)
            y += h + 6
            if let imageRaw, let url = external(imageRaw) {
                let meta = imageMeta[imageRaw]
                addImage(preview: url, full: url, w: CGFloat(meta?.width ?? 320), h: CGFloat(meta?.height ?? 180),
                         maxHeight: 240, x: x0 + 12, available: innerWidth)
            }
            y += 6
            attachments.append(.init(color: color, text: body, frame: textFrame,
                                     barFrame: CGRect(x: x0, y: startY, width: 4, height: y - startY)))
        }

        // Link previews (OpenGraph), only when there are no bot attachments, like the official app.
        var cards: [PostLayout.Card] = []
        if post.attachments.isEmpty, let embed = post.metadata?.embeds?.first(where: { $0.type == "opengraph" }),
           let data = embed.data {
            let inner = textWidth - 24
            let body = NSMutableAttributedString()
            func line(_ s: String, _ font: UIFont, _ color: UIColor) {
                if body.length > 0 { body.append(NSAttributedString(string: "\n", attributes: [.font: style.small])) }
                let p = NSMutableParagraphStyle()
                p.lineBreakMode = .byWordWrapping
                body.append(NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: p]))
            }
            if let site = data["site_name"]?.stringValue, !site.isEmpty { line(site, style.small, style.secondary) }
            if let title = data["title"]?.stringValue, !title.isEmpty { line(String(title.prefix(140)), style.bodyBold, style.link) }
            if let d = data["description"]?.stringValue, !d.isEmpty { line(String(d.prefix(240)), style.small, style.secondary) }
            if body.length > 0 {
                y += 8
                let startY = y
                let h = TextMeasure.height(body, width: inner)
                attachments.append(.init(color: .clear, text: body,
                                         frame: CGRect(x: x0 + 12, y: y + 12, width: inner, height: h), barFrame: .zero))
                y += 12 + h
                if let img = data["images"]?.arrayValue?.first,
                   let raw = img["secure_url"]?.stringValue ?? img["url"]?.stringValue, !raw.isEmpty, let url = external(raw) {
                    let meta = imageMeta[raw]
                    let w = CGFloat(meta?.width ?? Int(img["width"]?.numberValue ?? 0))
                    let hh = CGFloat(meta?.height ?? Int(img["height"]?.numberValue ?? 0))
                    if w > 0, hh > 0 {
                        addImage(preview: url, full: url, w: w, h: hh, maxHeight: 180, x: x0 + 12, available: inner)
                    }
                }
                y += 12
                cards.append(.init(frame: CGRect(x: x0, y: startY, width: textWidth, height: y - startY),
                                   url: (embed.url ?? data["url"]?.stringValue).flatMap(URL.init(string:))))
            }
        }

        // Uploaded images and videos: inline previews at their real aspect ratio, max 320pt tall.
        let allFiles = post.metadata?.files ?? []
        var cardFiles: [FileInfo] = []
        for f in allFiles {
            let isImage = f.mimeType.hasPrefix("image/") && (f.width ?? 0) > 0 && (f.height ?? 0) > 0
            let isVideo = f.mimeType.hasPrefix("video/") && (f.hasPreviewImage ?? false) && (f.width ?? 0) > 0
            if isImage || isVideo {
                addImage(preview: ImageLoader.filePreviewURL(fileId: f.id), full: ImageLoader.fileURL(fileId: f.id),
                         w: CGFloat(f.width!), h: CGFloat(max(1, f.height ?? 1)), isVideo: isVideo)
            } else {
                cardFiles.append(f)
            }
        }

        // Other files: 64pt cards (icon, name, type and size), as in `components/files`.
        var files: [PostLayout.File] = []
        for f in cardFiles {
            y += 8
            files.append(.init(info: f, frame: CGRect(x: x0, y: y, width: min(textWidth, 340), height: 64)))
            y += 64
        }

        // Reactions: 32pt chips, emoji + count, wrapping; yours outlined in the button color.
        var chips: [PostLayout.ReactionChip] = []
        var addFrame: CGRect?
        let reactions = post.metadata?.reactions ?? []
        if !reactions.isEmpty {
            var order: [String] = []
            var counts: [String: Int] = [:]
            var mine: Set<String> = []
            for r in reactions.sorted(by: { ($0.createAt ?? 0) < ($1.createAt ?? 0) }) {
                if counts[r.emojiName] == nil { order.append(r.emojiName) }
                counts[r.emojiName, default: 0] += 1
                if r.userId == input.myUserId { mine.insert(r.emojiName) }
            }
            y += 8
            var x = x0
            let maxX = x0 + textWidth
            let countFont = style.smallBold
            for name in order {
                let count = counts[name] ?? 0
                let countWidth = ceil(("\(count)" as NSString).size(withAttributes: [.font: countFont]).width)
                let width = max(50, 5 + 22 + 5 + countWidth + 8)
                if x + width > maxX && x > x0 { x = x0; y += 32 + 8 }
                chips.append(.init(name: name, emoji: EmojiStore.shared.unicode(for: name) ?? ":\(name):",
                                   count: count, mine: mine.contains(name),
                                   frame: CGRect(x: x, y: y, width: width, height: 32)))
                x += width + 8
            }
            if x + 36 > maxX { x = x0; y += 32 + 8 }
            addFrame = CGRect(x: x, y: y, width: 36, height: 32)
            y += 32
        }

        // Thread footer: reply count and whether you follow it.
        var footer: NSAttributedString?
        var footerFrame = CGRect.zero
        if input.collapsedThreads, let replies = post.replyCount, replies > 0, !post.isReply {
            let f = NSMutableAttributedString(string: "\(replies) \(replies == 1 ? "reply" : "replies")",
                                              attributes: [.font: style.smallBold, .foregroundColor: style.link])
            f.append(NSAttributedString(string: input.following ? "   Following" : "   Follow",
                                        attributes: [.font: style.smallBold, .foregroundColor: style.text.withAlphaComponent(0.64)]))
            y += 8
            footerFrame = CGRect(x: x0, y: y, width: textWidth, height: 20)
            footer = f
            y += 20
        }

        // Header: display name (SemiBold 16), BOT tag drawn by the cell, time (12, 50%).
        var name: NSAttributedString?
        var time: NSAttributedString?
        var nameWidth: CGFloat = 0
        if !input.consecutive {
            let n = NSAttributedString(string: input.displayName, attributes: [.font: style.bodyBold, .foregroundColor: style.text])
            nameWidth = min(ceil(n.size().width), textWidth * 0.6)
            name = n
            time = NSAttributedString(string: input.time, attributes: [
                .font: style.small, .foregroundColor: style.text.withAlphaComponent(0.5)])
        }

        let bottom: CGFloat = 6
        let height = ceil(max(y + bottom, top + (input.consecutive ? 26 : PostLayout.avatar + 10 + 6)))

        // The reply bar runs the height of the body, and joins the next/previous reply in the same
        // thread by reaching the cell edge (cells sit flush, so consecutive bars read as one line).
        var replyBarFrame: CGRect?
        if let bar = input.replyBar {
            let barTop = bar.first ? bodyTop - 2 : 0
            let barBottom = bar.last ? y + 2 : height
            replyBarFrame = CGRect(x: PostLayout.textX + 1, y: barTop, width: 3, height: max(4, barBottom - barTop))
        }
        var headerReplies: String?
        if !input.collapsedThreads, !input.consecutive, !post.isReply, let n = post.replyCount, n > 0 { headerReplies = "\(n)" }
        return PostLayout(id: post.id, post: post, consecutive: input.consecutive,
                          pending: post.pendingPostId == post.id && !input.failed, failed: input.failed,
                          isSystem: post.isSystemMessage, authorId: post.userId, avatarURL: input.avatarURL,
                          top: top, preHeader: preHeader, background: background,
                          name: name, time: time, isBot: input.isBot, nameWidth: nameWidth, message: message,
                          messageFrame: messageFrame, attachments: attachments, cards: cards, images: images,
                          files: files, reactions: chips, addReactionFrame: addFrame, footer: footer,
                          footerFrame: footerFrame, showMore: showMore, showMoreFrame: showMoreFrame,
                          replyBarFrame: replyBarFrame, replyBarHighlight: input.replyBar?.highlight ?? false,
                          commentedOn: commentedOn, commentedOnFrame: commentedOnFrame, headerReplies: headerReplies,
                          height: height)
    }

    private static func attachmentColor(_ s: String) -> UIColor? {
        switch s {
        case "good": .hex(0x3DB887)
        case "warning": .hex(0xFFBC1F)
        case "danger": .hex(0xD24B4E)
        default: UIColor(hexString: s)
        }
    }
}

/// TextKit measuring/drawing shared by layout (background) and cells (main), so heights match exactly.
enum TextMeasure {
    static func height(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        let (storage, lm, container) = stack(text, width: width)
        lm.ensureLayout(for: container)
        return withExtendedLifetime(storage) { ceil(lm.usedRect(for: container).height) }
    }

    /// The storage must be kept alive by the caller: it owns the layout manager, not the reverse.
    static func stack(_ text: NSAttributedString, width: CGFloat) -> (NSTextStorage, NSLayoutManager, NSTextContainer) {
        let storage = NSTextStorage(attributedString: text)
        let lm = NSLayoutManager()
        lm.usesFontLeading = true
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        lm.addTextContainer(container)
        storage.addLayoutManager(lm)
        return (storage, lm, container)
    }
}
