import CoreGraphics

/// A color with components in 0...1 (sRGB).
struct RGBAColor: Equatable, Codable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    static let black = RGBAColor(red: 0, green: 0, blue: 0)
    static let white = RGBAColor(red: 1, green: 1, blue: 1)

    var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }
}

/// How a stroke looks. `width` is in canvas pixels.
struct Brush: Equatable, Codable {
    var color: RGBAColor
    var width: Double
}

/// One finger-down-to-finger-up line, stored as the points the finger passed through.
struct Stroke: Equatable, Codable {
    var brush: Brush
    /// Canvas pixels, origin at the top-left corner, y growing downward.
    var points: [CGPoint]
}
