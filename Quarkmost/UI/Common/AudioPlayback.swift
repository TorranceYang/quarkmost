import AVFoundation
import UIKit

/// Inline playback for audio attachments (e.g. voice notes): one player shared by the app.
/// Tapping an audio card toggles it; tapping another switches to that one.
@MainActor
final class AudioPlayback {
    static let shared = AudioPlayback()
    nonisolated static let didChange = Notification.Name("AudioPlayback.didChange")

    private(set) var playingFileId: String?
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?

    func toggle(fileId: String) {
        if playingFileId == fileId {
            stop()
            return
        }
        stop()
        Task {
            var options: [String: Any] = [:]
            var headers = ["User-Agent": ServerConfig.userAgent]
            if let token = await AppSession.shared.client.token { headers["Authorization"] = "Bearer \(token)" }
            options["AVURLAssetHTTPHeaderFieldsKey"] = headers
            let asset = AVURLAsset(url: ImageLoader.fileURL(fileId: fileId), options: options)
            let item = AVPlayerItem(asset: asset)
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try? AVAudioSession.sharedInstance().setActive(true)
            let player = AVPlayer(playerItem: item)
            self.player = player
            playingFileId = fileId
            endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            }
            player.play()
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    func stop() {
        player?.pause()
        player = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        playingFileId = nil
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}

/// Downloads a file with the session token and previews it with QuickLook (PDFs, documents, video…).
@MainActor
enum FilePreviewer {
    static func open(_ file: FileInfo, from presenter: UIViewController) {
        if file.mimeType.hasPrefix("audio/") { AudioPlayback.shared.toggle(fileId: file.id); return }
        presenter.showToast("Downloading \(file.name)…")
        Task {
            guard let url = await download(file) else { presenter.showToast("Couldn't download the file"); return }
            let preview = PreviewController(url: url)
            presenter.present(preview, animated: true)
        }
    }

    static func download(_ file: FileInfo) async -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("files/\(file.id)", isDirectory: true)
        let target = dir.appendingPathComponent(file.name)
        if FileManager.default.fileExists(atPath: target.path) { return target }
        var request = URLRequest(url: ImageLoader.fileURL(fileId: file.id))
        request.setValue(ServerConfig.userAgent, forHTTPHeaderField: "User-Agent")
        if let token = await AppSession.shared.client.token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        guard let (tmp, response) = try? await URLSession.shared.download(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.moveItem(at: tmp, to: target)
        return FileManager.default.fileExists(atPath: target.path) ? target : nil
    }
}

import QuickLook

final class PreviewController: QLPreviewController, QLPreviewControllerDataSource {
    private let url: URL
    init(url: URL) {
        self.url = url
        super.init(nibName: nil, bundle: nil)
        dataSource = self
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
}
