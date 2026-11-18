import UIKit

/// What the cursor is on, for autocomplete.
enum ComposerToken: Equatable {
    case mention(String), channel(String), emoji(String), slash(String)
}

/// Message composer matching the official `post_draft`: typing line, uploads strip, input in a
/// top-rounded bordered box, quick actions (attach, @, /, emoji) on the left, an 80×32 send button.
///
/// It sits on `keyboardLayoutGuide`, so iOS moves it in the same animation as the keyboard.
final class ComposerView: UIView, UITextViewDelegate {
    struct Upload {
        let id = UUID()
        var name: String
        var thumbnail: UIImage?
        var progress: Double = 0
        var info: FileInfo?
        var failed = false
    }

    var onSend: ((String, [FileInfo]) -> Void)?
    var onTextChange: ((String) -> Void)?
    var onToken: ((ComposerToken?) -> Void)?
    var onAttach: (() -> Void)?
    var onEmoji: (() -> Void)?
    var onPasteImage: ((UIImage) -> Void)?

    var text: String {
        get { textView.text }
        set { textView.text = newValue; updateState() }
    }

    var placeholder: String = "" {
        didSet { placeholderLabel.text = placeholder }
    }

    private let typingLabel = UILabel()
    private let box = ComposerBoxView()
    private let textView = PasteTextView()
    private let placeholderLabel = UILabel()
    private let uploadsScroll = UIScrollView()
    private let uploadsStack = UIStackView()
    private let attachButton = UIButton(type: .system)
    private let atButton = UIButton(type: .system)
    private let slashButton = UIButton(type: .system)
    private let emojiButton = UIButton(type: .system)
    private let sendButton = UIButton(type: .custom)
    private var textHeight: NSLayoutConstraint!
    private var uploadsHeight: NSLayoutConstraint!
    private var typingHeight: NSLayoutConstraint!
    private var maxTextHeight: CGFloat { (textView.font?.lineHeight ?? 20) * 6 + 12 }
    private(set) var uploads: [Upload] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        [typingLabel, box, textView, placeholderLabel, uploadsScroll, attachButton, atButton, slashButton, emojiButton, sendButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        addSubview(typingLabel)
        addSubview(box)
        [textView, placeholderLabel, uploadsScroll, attachButton, atButton, slashButton, emojiButton, sendButton].forEach(box.addSubview)
        uploadsStack.axis = .horizontal
        uploadsStack.spacing = 8
        uploadsStack.translatesAutoresizingMaskIntoConstraints = false
        uploadsScroll.addSubview(uploadsStack)
        uploadsScroll.showsHorizontalScrollIndicator = false

        textView.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: UIFont(name: "OpenSans", size: 15)!)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.delegate = self
        textView.accessibilityLabel = "Message"
        textView.onPasteImage = { [weak self] image in self?.onPasteImage?(image) }
        textView.onSend = { [weak self] in self?.sendTapped() }

        placeholderLabel.font = textView.font
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.isUserInteractionEnabled = false

        func quick(_ b: UIButton, _ icon: String, _ label: String, _ action: @escaping () -> Void) {
            b.setImage(CompassIcon.image(icon, size: 24), for: .normal)
            b.accessibilityLabel = label
            b.addAction(UIAction { _ in action() }, for: .primaryActionTriggered)
        }
        quick(attachButton, "plus", "Attach") { [weak self] in self?.onAttach?() }
        quick(atButton, "at", "Mention someone") { [weak self] in self?.insert("@") }
        quick(slashButton, "slash-forward-box-outline", "Slash command") { [weak self] in self?.insertSlash() }
        quick(emojiButton, "emoticon-happy-outline", "Emoji") { [weak self] in self?.onEmoji?() }

        sendButton.layer.cornerRadius = 4
        sendButton.setImage(CompassIcon.image("send", size: 24), for: .normal)
        sendButton.accessibilityLabel = "Send"
        sendButton.addAction(UIAction { [weak self] _ in self?.sendTapped() }, for: .primaryActionTriggered)

        textHeight = textView.heightAnchor.constraint(equalToConstant: 36)
        uploadsHeight = uploadsScroll.heightAnchor.constraint(equalToConstant: 0)
        typingHeight = typingLabel.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            typingLabel.topAnchor.constraint(equalTo: topAnchor),
            typingLabel.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16),
            typingLabel.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -16),
            typingHeight,
            // The box spans the full width, like the official input; only its contents respect the
            // safe area (the Duo's outer screen has its status bar down the right edge). It also runs
            // past the bottom so its side borders reach the screen edge instead of stopping mid-air.
            box.topAnchor.constraint(equalTo: typingLabel.bottomAnchor),
            box.leadingAnchor.constraint(equalTo: leadingAnchor),
            box.trailingAnchor.constraint(equalTo: trailingAnchor),
            box.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 120),

            textView.topAnchor.constraint(equalTo: box.topAnchor, constant: 7),
            textView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            textHeight,
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 12),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 6),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor, constant: -12),

            uploadsScroll.topAnchor.constraint(equalTo: textView.bottomAnchor),
            uploadsScroll.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            uploadsScroll.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            uploadsHeight,
            uploadsStack.topAnchor.constraint(equalTo: uploadsScroll.contentLayoutGuide.topAnchor, constant: 8),
            uploadsStack.bottomAnchor.constraint(equalTo: uploadsScroll.contentLayoutGuide.bottomAnchor),
            uploadsStack.leadingAnchor.constraint(equalTo: uploadsScroll.contentLayoutGuide.leadingAnchor, constant: 12),
            uploadsStack.trailingAnchor.constraint(equalTo: uploadsScroll.contentLayoutGuide.trailingAnchor, constant: -12),

            attachButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 4),
            attachButton.topAnchor.constraint(equalTo: uploadsScroll.bottomAnchor),
            attachButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            sendButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -8),
            sendButton.centerYAnchor.constraint(equalTo: attachButton.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 80),
            sendButton.heightAnchor.constraint(equalToConstant: 32),
        ])
        var previous = attachButton
        for b in [attachButton, atButton, slashButton, emojiButton] {
            b.widthAnchor.constraint(equalToConstant: 44).isActive = true
            b.heightAnchor.constraint(equalToConstant: 44).isActive = true
            if b !== attachButton {
                b.leadingAnchor.constraint(equalTo: previous.trailingAnchor).isActive = true
                b.centerYAnchor.constraint(equalTo: attachButton.centerYAnchor).isActive = true
            }
            previous = b
        }
        typingLabel.clipsToBounds = true
        applyTheme()
        updateState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func applyTheme() {
        let theme = Theme.current
        backgroundColor = theme.centerChannelBg
        box.backgroundColor = theme.centerChannelBg
        box.borderColor = theme.centerChannelColor.opacity(0.2)
        textView.textColor = theme.centerChannelColor
        textView.tintColor = theme.linkColor
        textView.keyboardAppearance = theme.centerChannelBg.luminance < 0.5 ? .dark : .light
        placeholderLabel.textColor = theme.centerChannelColor.opacity(0.64)
        [attachButton, atButton, slashButton, emojiButton].forEach { $0.tintColor = theme.centerChannelColor.opacity(0.64) }
        sendButton.tintColor = theme.buttonColor
        updateState()
    }

    func focus() { textView.becomeFirstResponder() }
    var isFocused_: Bool { textView.isFirstResponder }

    /// "x is typing…" above the input (`post_draft/typing`).
    func setTyping(_ names: [String]) {
        let text: String? = switch names.count {
        case 0: nil
        case 1: "\(names[0]) is typing..."
        case 2: "\(names[0]) and \(names[1]) are typing..."
        default: "\(names[0]) and \(names.count - 1) others are typing..."
        }
        if let text {
            typingLabel.attributedText = NSAttributedString(string: text, attributes:
                Typography.style(.body, 50).attributes(color: Theme.current.centerChannelColor.opacity(0.72)))
        }
        let target: CGFloat = text == nil ? 0 : 20
        guard typingHeight.constant != target else { return }
        typingHeight.constant = target
        UIView.animate(withDuration: 0.2) { self.superview?.layoutIfNeeded() }
    }

    // MARK: Text

    func textViewDidChange(_ textView: UITextView) {
        updateState()
        onTextChange?(textView.text)
        onToken?(currentToken())
    }

    func textViewDidChangeSelection(_ textView: UITextView) { onToken?(currentToken()) }

    /// The word under the cursor, if it starts an autocomplete.
    private func currentToken() -> ComposerToken? {
        guard let range = textView.selectedTextRange, range.isEmpty else { return nil }
        let offset = textView.offset(from: textView.beginningOfDocument, to: range.start)
        let before = String((textView.text as NSString).substring(to: min(offset, (textView.text as NSString).length)))
        if before.hasPrefix("/"), !before.contains(" "), !before.contains("\n") { return .slash(String(before.dropFirst())) }
        guard let word = before.split(omittingEmptySubsequences: false, whereSeparator: { $0 == " " || $0 == "\n" }).last else { return nil }
        if word.hasPrefix("@") { return .mention(String(word.dropFirst())) }
        if word.hasPrefix("~") { return .channel(String(word.dropFirst())) }
        if word.hasPrefix(":"), word.count >= 3, !word.dropFirst().contains(":") { return .emoji(String(word.dropFirst())) }
        return nil
    }

    /// Replaces the word under the cursor with an autocomplete result.
    func completeToken(with replacement: String) {
        guard let range = textView.selectedTextRange else { return }
        let offset = textView.offset(from: textView.beginningOfDocument, to: range.start)
        let ns = textView.text as NSString
        var start = offset
        while start > 0 {
            let c = ns.substring(with: NSRange(location: start - 1, length: 1))
            if c == " " || c == "\n" { break }
            start -= 1
        }
        guard let from = textView.position(from: textView.beginningOfDocument, offset: start),
              let r = textView.textRange(from: from, to: range.start) else { return }
        textView.replace(r, withText: replacement + " ")
        textViewDidChange(textView)
    }

    func insert(_ s: String) {
        textView.becomeFirstResponder()
        let before = textView.text ?? ""
        let needsSpace = !(before.isEmpty || before.hasSuffix(" ") || before.hasSuffix("\n"))
        textView.insertText((needsSpace ? " " : "") + s)
    }

    /// Slash commands only work at the start of a message, as in the official app.
    private func insertSlash() {
        textView.becomeFirstResponder()
        if textView.text.isEmpty { textView.insertText("/") }
    }

    // MARK: Uploads

    /// Adds a file to the strip and uploads it; the send button waits for it to finish.
    func addUpload(data: Data, filename: String, thumbnail: UIImage?, channelId: String) {
        guard uploads.count < 10 else { return }
        var upload = Upload(name: filename, thumbnail: thumbnail)
        upload.progress = 0.02
        uploads.append(upload)
        let id = upload.id
        rebuildUploads()
        Task { [weak self] in
            do {
                let info = try await AppSession.shared.client.uploadFile(data: data, filename: filename, channelId: channelId) { p in
                    Task { @MainActor in self?.update(id) { $0.progress = p } }
                }
                self?.update(id) { $0.info = info; $0.progress = 1 }
            } catch {
                self?.update(id) { $0.failed = true }
            }
        }
    }

    private func update(_ id: UUID, _ change: (inout Upload) -> Void) {
        guard let i = uploads.firstIndex(where: { $0.id == id }) else { return }
        change(&uploads[i])
        (uploadsStack.arrangedSubviews[safe: i] as? UploadThumb)?.configure(uploads[i])
        updateState()
    }

    private func rebuildUploads() {
        uploadsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for upload in uploads {
            let thumb = UploadThumb()
            thumb.configure(upload)
            let id = upload.id
            thumb.onRemove = { [weak self] in
                self?.uploads.removeAll { $0.id == id }
                self?.rebuildUploads()
            }
            uploadsStack.addArrangedSubview(thumb)
        }
        uploadsHeight.constant = uploads.isEmpty ? 0 : 80
        updateState()
        superview?.layoutIfNeeded()
    }

    private func updateState() {
        let hasText = !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let done = uploads.filter { $0.info != nil }.count
        let busy = uploads.contains { $0.info == nil && !$0.failed }
        let enabled = (hasText || done > 0) && !busy
        sendButton.isEnabled = enabled
        let theme = Theme.current
        sendButton.layer.backgroundColor = (enabled ? theme.buttonBg : theme.buttonBg.opacity(0.3)).cgColor
        placeholderLabel.isHidden = !textView.text.isEmpty

        let width = textView.bounds.width > 0 ? textView.bounds.width : bounds.width
        let fitting = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let target = min(max(fitting, 32), maxTextHeight)
        textView.isScrollEnabled = fitting > maxTextHeight
        if abs(textHeight.constant - target) > 0.5 { textHeight.constant = target }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateState()
    }

    private func sendTapped() {
        guard sendButton.isEnabled else { return }
        let message = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = uploads.compactMap(\.info)
        guard !message.isEmpty || !files.isEmpty else { return }
        text = ""
        uploads = []
        rebuildUploads()
        onTextChange?("")
        onToken?(nil)
        onSend?(message, files)
    }
}

/// Text view that accepts pasted images and sends on Return from a hardware keyboard.
final class PasteTextView: UITextView {
    var onPasteImage: ((UIImage) -> Void)?
    var onSend: (() -> Void)?

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)), UIPasteboard.general.hasImages { return true }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        if UIPasteboard.general.hasImages, let image = UIPasteboard.general.image {
            onPasteImage?(image)
            return
        }
        super.paste(sender)
    }

    /// Hardware keyboard: Return sends, Shift+Return adds a line. The on-screen Return key is untouched.
    override var keyCommands: [UIKeyCommand]? {
        let send = UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(sendCommand))
        send.wantsPriorityOverSystemBehavior = true
        return [send]
    }

    @objc private func sendCommand() { onSend?() }
}

/// 64pt upload thumbnail with a progress bar and a remove button.
final class UploadThumb: UIView {
    var onRemove: (() -> Void)?
    private let image = UIImageView()
    private let name = UILabel()
    private let bar = UIProgressView(progressViewStyle: .bar)
    private let remove = UIButton(type: .custom)

    override init(frame: CGRect) {
        super.init(frame: frame)
        let theme = Theme.current
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 64).isActive = true
        heightAnchor.constraint(equalToConstant: 64).isActive = true
        image.contentMode = .scaleAspectFill
        image.layer.cornerRadius = 4
        image.clipsToBounds = true
        image.backgroundColor = theme.centerChannelColor.opacity(0.08)
        image.tintColor = theme.centerChannelColor.opacity(0.64)
        name.font = Typography.style(.body, 25, scaled: false).font
        name.textColor = theme.centerChannelColor
        name.textAlignment = .center
        name.lineBreakMode = .byTruncatingMiddle
        bar.progressTintColor = theme.buttonBg
        remove.setImage(CompassIcon.image("close-circle", size: 22), for: .normal)
        remove.tintColor = theme.centerChannelColor
        remove.backgroundColor = theme.centerChannelBg
        remove.layer.cornerRadius = 11
        remove.accessibilityLabel = "Remove attachment"
        remove.addAction(UIAction { [weak self] _ in self?.onRemove?() }, for: .primaryActionTriggered)
        [image, name, bar, remove].forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ upload: ComposerView.Upload) {
        if let t = upload.thumbnail {
            image.image = t
            image.contentMode = .scaleAspectFill
            name.isHidden = true
        } else {
            image.image = CompassIcon.image("file-generic-outline", size: 32)
            image.contentMode = .center
            name.isHidden = false
            name.text = upload.name
        }
        bar.isHidden = upload.info != nil || upload.failed
        bar.progress = Float(upload.progress)
        alpha = upload.failed ? 0.4 : 1
        accessibilityLabel = upload.failed ? "\(upload.name), upload failed" : upload.name
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        image.frame = bounds
        name.frame = CGRect(x: 2, y: bounds.height - 16, width: bounds.width - 4, height: 14)
        bar.frame = CGRect(x: 4, y: bounds.height - 6, width: bounds.width - 8, height: 2)
        remove.frame = CGRect(x: bounds.width - 16, y: -6, width: 22, height: 22)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -8, dy: -8).contains(point)
    }
}

/// Top-rounded box with borders on the top and sides only (the official input has no bottom border).
final class ComposerBoxView: UIView {
    var borderColor: UIColor = .clear { didSet { border.strokeColor = borderColor.cgColor } }
    private let border = CAShapeLayer()
    private let radius: CGFloat = 12

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = radius
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        border.fillColor = nil
        border.lineWidth = 1
        layer.addSublayer(border)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: b.minX, y: b.maxY))
        path.addLine(to: CGPoint(x: b.minX, y: b.minY + radius))
        path.addArc(withCenter: CGPoint(x: b.minX + radius, y: b.minY + radius), radius: radius,
                    startAngle: .pi, endAngle: .pi * 1.5, clockwise: true)
        path.addLine(to: CGPoint(x: b.maxX - radius, y: b.minY))
        path.addArc(withCenter: CGPoint(x: b.maxX - radius, y: b.minY + radius), radius: radius,
                    startAngle: .pi * 1.5, endAngle: 0, clockwise: true)
        path.addLine(to: CGPoint(x: b.maxX, y: b.maxY))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        border.frame = bounds
        border.path = path.cgPath
        CATransaction.commit()
    }
}

/// The autocomplete list that floats above the composer (`components/autocomplete`).
final class AutocompleteView: UIView, UITableViewDataSource, UITableViewDelegate {
    var onPick: ((SearchListViewController.Row) -> Void)?
    private let table = UITableView(frame: .zero, style: .plain)
    private var rows: [SearchListViewController.Row] = []
    private var height: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        let theme = Theme.current
        backgroundColor = theme.centerChannelBg
        layer.cornerRadius = 8
        layer.borderWidth = 1
        layer.borderColor = theme.centerChannelColor.opacity(0.16).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: -2)
        table.backgroundColor = .clear
        table.layer.cornerRadius = 8
        table.separatorStyle = .none
        table.rowHeight = 44
        table.dataSource = self
        table.delegate = self
        table.register(ListRowCell.self, forCellReuseIdentifier: "row")
        table.translatesAutoresizingMaskIntoConstraints = false
        addSubview(table)
        height = heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            table.topAnchor.constraint(equalTo: topAnchor), table.bottomAnchor.constraint(equalTo: bottomAnchor),
            table.leadingAnchor.constraint(equalTo: leadingAnchor), table.trailingAnchor.constraint(equalTo: trailingAnchor),
            height,
        ])
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(_ rows: [SearchListViewController.Row]) {
        self.rows = rows
        isHidden = rows.isEmpty
        height.constant = min(CGFloat(rows.count) * 44, 220)
        table.reloadData()
        if !rows.isEmpty { table.setContentOffset(.zero, animated: false) }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath) as! ListRowCell
        cell.configure(rows[indexPath.row], checked: nil)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        onPick?(rows[indexPath.row])
    }
}
