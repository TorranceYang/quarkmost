import UIKit

/// Loads server images (profile pictures for now) with the session token, and decodes them
/// **off the main thread at the exact pixel size they'll be drawn**. Scrolling never pays for
/// JPEG decoding or downscaling, which is a large part of the official app's dropped frames.
actor ImageLoader {
    static let shared = ImageLoader()

    /// NSCache is thread-safe, so the synchronous lookup below can skip the actor hop.
    private nonisolated(unsafe) let memory = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 8 << 20, diskCapacity: 200 << 20)  // raw bytes survive relaunch
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
        memory.countLimit = 500
    }

    /// Synchronous memory-cache hit, so a cell being reused can show its image in the same frame.
    nonisolated func cached(_ url: URL, pointSize: CGFloat, scale: CGFloat) -> UIImage? {
        memory.object(forKey: Self.key(url, CGSize(width: pointSize, height: pointSize), scale, -1))
    }

    nonisolated func cached(_ url: URL, size: CGSize, scale: CGFloat, cornerRadius: CGFloat) -> UIImage? {
        memory.object(forKey: Self.key(url, size, scale, cornerRadius))
    }

    /// Round avatar.
    func image(_ url: URL, pointSize: CGFloat, scale: CGFloat) async -> UIImage? {
        await image(url, size: CGSize(width: pointSize, height: pointSize), scale: scale, cornerRadius: -1)
    }

    /// Aspect-fill into `size`, clipped to a rounded rect (`cornerRadius` < 0 means a circle).
    func image(_ url: URL, size: CGSize, scale: CGFloat, cornerRadius: CGFloat) async -> UIImage? {
        let key = Self.key(url, size, scale, cornerRadius)
        if let hit = memory.object(forKey: key) { return hit }
        if let running = inFlight[key as String] { return await running.value }

        let token = await AppSession.shared.client.token
        let session = self.session
        let task = Task<UIImage?, Never>.detached(priority: .userInitiated) {
            var request = URLRequest(url: url)
            request.setValue(ServerConfig.userAgent, forHTTPHeaderField: "User-Agent")
            if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            guard let (data, response) = try? await session.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let source = UIImage(data: data) else { return nil }
            return Self.render(source, size: size, scale: scale, cornerRadius: cornerRadius)
        }
        inFlight[key as String] = task
        let image = await task.value
        inFlight[key as String] = nil
        if let image { memory.setObject(image, forKey: key) }
        return image
    }

    /// Aspect-fill, clipped, fully decoded into a bitmap at the exact display size.
    private static func render(_ source: UIImage, size: CGSize, scale: CGFloat, cornerRadius: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let rect = CGRect(origin: .zero, size: size)
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            if cornerRadius < 0 { UIBezierPath(ovalIn: rect).addClip() }
            else if cornerRadius > 0 { UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).addClip() }
            let s = max(size.width / source.size.width, size.height / source.size.height)
            let drawn = CGSize(width: source.size.width * s, height: source.size.height * s)
            source.draw(in: CGRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2,
                                   width: drawn.width, height: drawn.height))
        }
    }

    /// Full-resolution image for the gallery (decoded off the main thread, not resized).
    func fullImage(_ url: URL) async -> UIImage? {
        let token = await AppSession.shared.client.token
        let session = self.session
        return await Task.detached(priority: .userInitiated) {
            var request = URLRequest(url: url)
            request.setValue(ServerConfig.userAgent, forHTTPHeaderField: "User-Agent")
            if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            guard let (data, _) = try? await session.data(for: request), let image = UIImage(data: data) else { return nil }
            return image.preparingForDisplay() ?? image
        }.value
    }

    private static func key(_ url: URL, _ size: CGSize, _ scale: CGFloat, _ radius: CGFloat) -> NSString {
        "\(url.absoluteString)#\(size.width)x\(size.height)@\(scale)r\(radius)" as NSString
    }

    static func filePreviewURL(fileId: String) -> URL { ServerConfig.apiURL.appendingPathComponent("files/\(fileId)/preview") }
    static func fileURL(fileId: String) -> URL { ServerConfig.apiURL.appendingPathComponent("files/\(fileId)") }

    static func profileImageURL(userId: String, lastPictureUpdate: Int64?) -> URL {
        var c = URLComponents(url: ServerConfig.apiURL.appendingPathComponent("users/\(userId)/image"),
                              resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "_", value: "\(lastPictureUpdate ?? 0)")]
        return c.url!
    }
}
