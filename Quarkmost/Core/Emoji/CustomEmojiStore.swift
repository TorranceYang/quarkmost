import UIKit

/// The server's custom emoji (`GET /api/v4/emoji`), with their images loaded once and kept in memory.
/// Thread-safe: the post renderer reads it off the main thread while layouts are built.
public final class CustomEmojiStore: @unchecked Sendable {
    public static let shared = CustomEmojiStore()
    /// Posted on the main thread when images finish loading, so on-screen posts can re-render.
    public static let didLoad = Notification.Name("CustomEmojiStore.didLoad")

    private let lock = NSLock()
    private var idsByName: [String: String] = [:]
    private var imagesByName: [String: UIImage] = [:]
    private var orderedNames: [String] = []

    public var names: [String] { lock.withLock { orderedNames } }
    public func isCustom(_ name: String) -> Bool { lock.withLock { idsByName[name] != nil } }
    public func image(_ name: String) -> UIImage? { lock.withLock { imagesByName[name] } }

    public func search(_ query: String) -> [String] {
        let q = query.lowercased()
        let all = names
        guard !q.isEmpty else { return all }
        return all.filter { $0.hasPrefix(q) } + all.filter { !$0.hasPrefix(q) && $0.contains(q) }
    }

    func reset() {
        lock.withLock { idsByName = [:]; imagesByName = [:]; orderedNames = [] }
    }

    /// Fetches the list, then every image in parallel (they're tiny). Each image is redrawn to a
    /// 64px square up front so drawing it later never decodes anything.
    @MainActor
    func load(client: MattermostClient) async {
        var all: [CustomEmoji] = []
        for page in 0..<20 {
            guard let batch = try? await client.customEmoji(page: page), !batch.isEmpty else { break }
            all += batch
            if batch.count < 200 { break }
        }
        let sorted = all.sorted { $0.name < $1.name }
        lock.withLock {
            idsByName = Dictionary(sorted.map { ($0.name, $0.id) }, uniquingKeysWith: { a, _ in a })
            orderedNames = sorted.map(\.name)
        }
        await withTaskGroup(of: (String, UIImage?).self) { group in
            for e in sorted {
                group.addTask {
                    let url = ServerConfig.apiURL.appendingPathComponent("emoji/\(e.id)/image")
                    guard let image = await ImageLoader.shared.fullImage(url) else { return (e.name, nil) }
                    return (e.name, Self.normalize(image))
                }
            }
            for await (name, image) in group {
                guard let image else { continue }
                lock.withLock { imagesByName[name] = image }
            }
        }
        NotificationCenter.default.post(name: Self.didLoad, object: nil)
    }

    private static func normalize(_ image: UIImage) -> UIImage {
        let side: CGFloat = 64
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let s = min(side / image.size.width, side / image.size.height)
            let size = CGSize(width: image.size.width * s, height: image.size.height * s)
            image.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2,
                                  width: size.width, height: size.height))
        }
    }
}

public struct CustomEmoji: Codable, Sendable {
    public let id: String
    public let name: String
}
