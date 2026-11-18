import UIKit

/// Full-screen image viewer (`screens/gallery`): pinch / double-tap zoom, swipe between a post's
/// images, swipe down to close, share. Black background, controls fade on tap.
final class GalleryViewController: UIViewController, UIScrollViewDelegate {
    private let urls: [URL]
    private var index: Int
    private let author: String
    private let pager = UIScrollView()
    private var pages: [ZoomPage] = []
    private let header = UIView(), footer = UIView()
    private let closeButton = UIButton(type: .custom), shareButton = UIButton(type: .custom)
    private let saveButton = UIButton(type: .custom)
    private let titleLabel = UILabel(), counterLabel = UILabel()
    private var controlsHidden = false

    init(urls: [URL], startIndex: Int, author: String) {
        self.urls = urls
        self.index = startIndex
        self.author = author
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var prefersStatusBarHidden: Bool { controlsHidden }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        pager.isPagingEnabled = true
        pager.showsHorizontalScrollIndicator = false
        pager.delegate = self
        pager.contentInsetAdjustmentBehavior = .never
        view.addSubview(pager)
        for url in urls {
            let page = ZoomPage(url: url)
            page.onSingleTap = { [weak self] in self?.toggleControls() }
            pager.addSubview(page)
            pages.append(page)
        }

        for bar in [header, footer] {
            bar.backgroundColor = UIColor.black.withAlphaComponent(0.5)
            view.addSubview(bar)
        }
        closeButton.setImage(CompassIcon.image("close", size: 24), for: .normal)
        closeButton.tintColor = .white
        closeButton.accessibilityLabel = "Close"
        closeButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .primaryActionTriggered)
        shareButton.setImage(CompassIcon.image("share-variant-outline", size: 24), for: .normal)
        shareButton.tintColor = .white
        shareButton.accessibilityLabel = "Share"
        shareButton.addAction(UIAction { [weak self] _ in self?.share() }, for: .primaryActionTriggered)
        saveButton.setImage(CompassIcon.image("download-outline", size: 24), for: .normal)
        saveButton.tintColor = .white
        saveButton.accessibilityLabel = "Save to Photos"
        saveButton.addAction(UIAction { [weak self] _ in self?.save() }, for: .primaryActionTriggered)
        footer.addSubview(saveButton)
        titleLabel.attributedText = NSAttributedString(
            string: author, attributes: Typography.style(.body, 200, .semibold).attributes(color: .white))
        counterLabel.textColor = .white.withAlphaComponent(0.72)
        counterLabel.font = Typography.style(.body, 100).font
        header.addSubview(closeButton)
        header.addSubview(counterLabel)
        footer.addSubview(titleLabel)
        footer.addSubview(shareButton)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)
        updateCounter()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds, safe = view.safeAreaInsets
        pager.frame = b
        pager.contentSize = CGSize(width: b.width * CGFloat(pages.count), height: b.height)
        for (i, p) in pages.enumerated() { p.frame = CGRect(x: CGFloat(i) * b.width, y: 0, width: b.width, height: b.height) }
        pager.contentOffset.x = CGFloat(index) * b.width
        header.frame = CGRect(x: 0, y: 0, width: b.width, height: safe.top + 52)
        closeButton.frame = CGRect(x: safe.left + 8, y: safe.top + 4, width: 44, height: 44)
        counterLabel.sizeToFit()
        counterLabel.center = CGPoint(x: b.midX, y: safe.top + 26)
        footer.frame = CGRect(x: 0, y: b.height - safe.bottom - 56, width: b.width, height: safe.bottom + 56)
        titleLabel.frame = CGRect(x: safe.left + 16, y: 0, width: b.width - safe.left - safe.right - 80, height: 56)
        shareButton.frame = CGRect(x: b.width - safe.right - 56, y: 6, width: 44, height: 44)
        saveButton.frame = CGRect(x: b.width - safe.right - 104, y: 6, width: 44, height: 44)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let newIndex = Int((scrollView.contentOffset.x / max(1, scrollView.bounds.width)).rounded())
        if newIndex != index { pages[safe: index]?.resetZoom() }
        index = newIndex
        updateCounter()
    }

    private func updateCounter() {
        counterLabel.text = pages.count > 1 ? "\(index + 1) of \(pages.count)" : nil
        counterLabel.sizeToFit()
    }

    private func toggleControls() {
        controlsHidden.toggle()
        UIView.animate(withDuration: 0.2) {
            self.header.alpha = self.controlsHidden ? 0 : 1
            self.footer.alpha = self.controlsHidden ? 0 : 1
            self.setNeedsStatusBarAppearanceUpdate()
        }
    }

    private func save() {
        guard let image = pages[safe: index]?.image else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        showToast("Saved to Photos")
    }

    private func share() {
        guard let image = pages[safe: index]?.image else { return }
        let sheet = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = shareButton
        present(sheet, animated: true)
    }

    /// Swipe down (when not zoomed) drags the image away and dismisses past a threshold.
    @objc private func panned(_ g: UIPanGestureRecognizer) {
        guard let page = pages[safe: index] else { return }
        let t = g.translation(in: view)
        switch g.state {
        case .changed:
            page.transform = CGAffineTransform(translationX: 0, y: max(0, t.y))
            view.backgroundColor = UIColor.black.withAlphaComponent(1 - min(0.8, max(0, t.y) / 400))
        case .ended, .cancelled:
            if t.y > 120 || g.velocity(in: view).y > 1000 {
                dismiss(animated: true)
            } else {
                UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
                    page.transform = .identity
                    self.view.backgroundColor = .black
                }
            }
        default: break
        }
    }
}

extension GalleryViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let pan = g as? UIPanGestureRecognizer, let page = pages[safe: index] else { return true }
        let v = pan.velocity(in: view)
        return page.isAtMinimumZoom && v.y > abs(v.x)
    }
}

/// One zoomable image. Loads the full image off the main thread.
final class ZoomPage: UIScrollView, UIScrollViewDelegate {
    var onSingleTap: (() -> Void)?
    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .large)
    var image: UIImage? { imageView.image }
    var isAtMinimumZoom: Bool { zoomScale <= minimumZoomScale + 0.01 }

    init(url: URL) {
        super.init(frame: .zero)
        delegate = self
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        maximumZoomScale = 4
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        spinner.color = .white
        addSubview(spinner)
        spinner.startAnimating()
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(singleTapped))
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
        accessibilityLabel = "Image"
        Task { [weak self] in
            let image = await ImageLoader.shared.fullImage(url)
            guard let self else { return }
            self.spinner.stopAnimating()
            self.imageView.image = image
            self.setNeedsLayout()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        spinner.center = CGPoint(x: bounds.midX, y: bounds.midY)
        guard zoomScale == minimumZoomScale else { return }
        imageView.frame = bounds
        contentSize = bounds.size
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func resetZoom() { setZoomScale(minimumZoomScale, animated: false) }

    @objc private func singleTapped() { onSingleTap?() }

    @objc private func doubleTapped(_ g: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let p = g.location(in: imageView)
            let size = CGSize(width: bounds.width / 2.5, height: bounds.height / 2.5)
            zoom(to: CGRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height),
                 animated: true)
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
