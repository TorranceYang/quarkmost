import UIKit

/// Mattermost's Compass icon set, rendered from the bundled icon font into cached template images.
/// Template images take `tintColor`, so one cached image serves every color and state.
@MainActor
enum CompassIcon {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(_ name: String, size: CGFloat) -> UIImage? {
        let key = "\(name)@\(size)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let code = CompassGlyphs.codes[name], let scalar = Unicode.Scalar(code),
              let font = UIFont(name: "compass-icons", size: size) else {
            assertionFailure("Unknown Compass icon \(name)")
            return nil
        }
        let glyph = String(Character(scalar)) as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        let measured = glyph.size(withAttributes: attrs)
        let canvas = CGSize(width: size, height: size)
        let image = UIGraphicsImageRenderer(size: canvas).image { _ in
            glyph.draw(at: CGPoint(x: (canvas.width - measured.width) / 2, y: (canvas.height - measured.height) / 2),
                       withAttributes: attrs)
        }.withRenderingMode(.alwaysTemplate)
        cache.setObject(image, forKey: key)
        return image
    }
}
