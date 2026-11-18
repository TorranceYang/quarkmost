import UIKit

/// Search tab (`screens/home/search`): a field on the sidebar color, search options and recent
/// searches before you search, then Messages / Files results.
final class SearchViewController: UIViewController, UITextFieldDelegate {
    private let header = TabHeaderView(title: "Search")
    private let field = FlatSearchField(placeholder: "Search messages & files", onSidebar: true)
    private let initial = StackScreenViewController()
    private let segment = FlatTabs(["Messages", "Files"])
    private let container = UIView()
    private var results: PostResultsViewController?
    private var files: FileListViewController?
    private var pendingTerms: String?

    private static let recentKey = "recentSearches"
    private var recent: [String] {
        get { UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? [] }
        set { UserDefaults.standard.set(Array(newValue.prefix(15)), forKey: Self.recentKey) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let theme = Theme.current
        view.backgroundColor = theme.centerChannelBg
        let fieldWrap = UIView()
        fieldWrap.backgroundColor = theme.sidebarBg
        field.returnKeyType = .search
        field.delegate = self
        field.addAction(UIAction { [weak self] _ in
            if self?.field.text?.isEmpty ?? true { self?.showInitial() }
        }, for: .editingChanged)
        segment.onChange = { [weak self] _ in self?.showResultsTab() }
        segment.isHidden = true

        [header, fieldWrap, segment, container].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
        field.translatesAutoresizingMaskIntoConstraints = false
        fieldWrap.addSubview(field)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor), header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            fieldWrap.topAnchor.constraint(equalTo: header.bottomAnchor),
            fieldWrap.leadingAnchor.constraint(equalTo: view.leadingAnchor), fieldWrap.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            field.topAnchor.constraint(equalTo: fieldWrap.topAnchor),
            field.bottomAnchor.constraint(equalTo: fieldWrap.bottomAnchor, constant: -16),
            field.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            field.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            field.heightAnchor.constraint(equalToConstant: 40),
            segment.topAnchor.constraint(equalTo: fieldWrap.bottomAnchor, constant: 12),
            segment.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            segment.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            container.topAnchor.constraint(equalTo: fieldWrap.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor), container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        // The switch sits above the results area, which would otherwise swallow its taps.
        view.bringSubviewToFront(segment)
        addChild(initial)
        embed(initial.view)
        initial.didMove(toParent: self)
        showInitial()
        if let pendingTerms { run(pendingTerms) }
    }

    func focus() { field.becomeFirstResponder() }

    private func embed(_ v: UIView, top: CGFloat = 0) {
        container.subviews.forEach { $0.removeFromSuperview() }
        v.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: container.topAnchor, constant: top), v.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            v.leadingAnchor.constraint(equalTo: container.leadingAnchor), v.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }

    private func showInitial() {
        segment.isHidden = true
        embed(initial.view)
        initial.clear()
        initial.addSectionTitle("Search options")
        let modifiers = [("From:", "a specific user"), ("In:", "a specific channel"), ("On:", "a specific date"),
                         ("Before:", "before a date"), ("After:", "after a date"),
                         ("-", "exclude search terms"), ("\"\"", "messages with phrases")]
        for (term, description) in modifiers {
            initial.stack.addArrangedSubview(MenuRow(icon: "plus-box-outline".ifKnown("plus"), title: term, subtitle: description) { [weak self] in
                self?.insert(term)
            })
        }
        let recent = self.recent
        if !recent.isEmpty {
            initial.addDivider()
            initial.addSectionTitle("Recent searches in \(AppSession.shared.team?.displayName ?? "this team")")
            for term in recent {
                initial.stack.addArrangedSubview(MenuRow(icon: "clock-outline", title: term) { [weak self] in self?.run(term) })
            }
            initial.stack.addArrangedSubview(MenuRow(icon: "close", title: "Clear recent searches") { [weak self] in
                self?.recent = []
                self?.showInitial()
            })
        }
    }

    private func insert(_ term: String) {
        var text = field.text ?? ""
        if !text.isEmpty && !text.hasSuffix(" ") { text += " " }
        if term == "\"\"" {
            field.text = text + "\"\""
            field.becomeFirstResponder()
            if let end = field.position(from: field.endOfDocument, offset: -1) {
                field.selectedTextRange = field.textRange(from: end, to: end)
            }
            return
        }
        field.text = text + term.lowercased()
        field.becomeFirstResponder()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let terms = (textField.text ?? "").trimmingCharacters(in: .whitespaces)
        if !terms.isEmpty { run(terms) }
        textField.resignFirstResponder()
        return true
    }

    func run(_ terms: String) {
        guard isViewLoaded else { pendingTerms = terms; return }
        pendingTerms = nil
        field.text = terms
        field.resignFirstResponder()
        recent = [terms] + recent.filter { $0 != terms }

        results.map { $0.willMove(toParent: nil); $0.removeFromParent() }
        files.map { $0.willMove(toParent: nil); $0.removeFromParent() }
        let r = PostResultsViewController(
            title: nil, emptyState: .init(icon: "magnify", title: "No matches found for “\(terms)”",
                                          text: "Check the spelling or try another search.")) {
            guard let team = AppSession.shared.team else { return [] }
            return try await AppSession.shared.client.searchPosts(teamId: team.id, terms: terms).orderedPosts
        }
        let f = FileListViewController(emptyText: "No files matching “\(terms)”") {
            guard let team = AppSession.shared.team else { return [] }
            return try await AppSession.shared.client.searchFiles(teamId: team.id, terms: terms).ordered
        }
        addChild(r); addChild(f)
        r.didMove(toParent: self); f.didMove(toParent: self)
        results = r
        files = f
        segment.isHidden = false
        segment.select(0)
        showResultsTab()
    }

    private func showResultsTab() {
        guard let results, let files else { return }
        embed(segment.selectedIndex == 0 ? results.view : files.view, top: 56)
        view.bringSubviewToFront(segment)
    }
}

/// A list of file cards (search results, channel files). Tap previews or plays the file.
final class FileListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let loader: () async throws -> [FileInfo]
    private let emptyText: String
    private let table = UITableView(frame: .zero, style: .plain)
    private var items: [FileInfo] = []

    init(emptyText: String, loader: @escaping () async throws -> [FileInfo]) {
        self.loader = loader
        self.emptyText = emptyText
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.current.centerChannelBg
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.rowHeight = 76
        table.dataSource = self
        table.delegate = self
        table.register(FileRowCell.self, forCellReuseIdentifier: "file")
        table.frame = view.bounds
        table.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(table)
        load()
    }

    private func load() {
        contentUnavailableConfiguration = UIContentUnavailableConfiguration.loading()
        Task {
            items = (try? await loader()) ?? []
            table.reloadData()
            if items.isEmpty {
                var config = UIContentUnavailableConfiguration.empty()
                config.image = CompassIcon.image("file-text-outline", size: 64)
                config.imageProperties.tintColor = Theme.current.buttonBg.opacity(0.48)
                config.text = emptyText
                config.textProperties.color = Theme.current.centerChannelColor
                config.textProperties.font = Typography.style(.heading, 300).font
                contentUnavailableConfiguration = config
            } else {
                contentUnavailableConfiguration = nil
            }
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "file", for: indexPath) as! FileRowCell
        cell.card.configure(items[indexPath.row], theme: Theme.current)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let file = items[indexPath.row]
        if file.mimeType.hasPrefix("image/") {
            present(GalleryViewController(urls: [ImageLoader.fileURL(fileId: file.id)], startIndex: 0, author: file.name), animated: true)
        } else if file.mimeType.hasPrefix("video/") {
            VideoPlayer.play(ImageLoader.fileURL(fileId: file.id), from: self)
        } else {
            FilePreviewer.open(file, from: self)
        }
    }
}

final class FileRowCell: UITableViewCell {
    let card = FileCardView()
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        card.isUserInteractionEnabled = false
        contentView.addSubview(card)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() {
        super.layoutSubviews()
        card.frame = contentView.bounds.insetBy(dx: 20, dy: 6)
    }
}
