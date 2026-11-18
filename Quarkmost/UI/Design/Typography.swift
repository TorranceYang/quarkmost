import UIKit

/// The official app's type scale (`app/utils/typography.ts`):
/// Open Sans for body text and small headings, Metropolis for headings above size 100.
/// Sizes scale with Dynamic Type, which the official app doesn't do well.
enum Typography {
    enum Kind { case heading, body }
    enum Weight { case light, regular, semibold, bold }

    struct Style {
        let font: UIFont
        let lineHeight: CGFloat
        let letterSpacing: CGFloat

        /// Attributes that reproduce the exact line height, with text vertically centered in it.
        func attributes(color: UIColor, alignment: NSTextAlignment = .natural) -> [NSAttributedString.Key: Any] {
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = lineHeight
            paragraph.maximumLineHeight = lineHeight
            paragraph.alignment = alignment
            paragraph.lineBreakMode = .byTruncatingTail
            return [.font: font, .foregroundColor: color, .paragraphStyle: paragraph,
                    .baselineOffset: (lineHeight - font.lineHeight) / 4,
                    .kern: letterSpacing * font.pointSize]
        }
    }

    private static let sizes: [Int: (CGFloat, CGFloat, CGFloat)] = [   // size: (points, lineHeight, letterSpacing em)
        1200: (66, 48, -0.02), 1000: (40, 48, -0.02), 900: (36, 44, -0.02), 800: (32, 40, -0.01),
        700: (28, 36, 0), 600: (25, 30, 0), 500: (22, 28, 0), 400: (20, 28, 0), 300: (18, 24, 0),
        200: (16, 24, 0), 100: (14, 20, 0), 75: (12, 16, 0), 50: (11, 16, 0), 25: (10, 16, 0),
    ]

    static func style(_ kind: Kind, _ size: Int, _ weight: Weight? = nil,
                      italic: Bool = false, scaled: Bool = true) -> Style {
        let (points, lineHeight, spacing) = sizes[size] ?? (14, 20, 0)
        let weight = weight ?? (kind == .heading ? .semibold : .regular)
        let metropolis = kind == .heading && size > 100
        let name: String
        if metropolis {
            name = weight == .regular || weight == .light ? "Metropolis" : "Metropolis-SemiBold"
        } else {
            let base: String = switch weight {
            case .light, .regular: italic ? "OpenSans-Italic" : "OpenSans"
            case .semibold: italic ? "OpenSans-SemiBoldItalic" : "OpenSans-SemiBold"
            case .bold: italic ? "OpenSans-BoldItalic" : "OpenSans-Bold"
            }
            name = base
        }
        let base = UIFont(name: name, size: points) ?? .systemFont(ofSize: points)
        guard scaled else { return Style(font: base, lineHeight: lineHeight, letterSpacing: spacing) }
        let metrics = UIFontMetrics(forTextStyle: kind == .heading ? .headline : .body)
        let font = metrics.scaledFont(for: base)
        return Style(font: font, lineHeight: (lineHeight * font.pointSize / points).rounded(), letterSpacing: spacing)
    }
}
