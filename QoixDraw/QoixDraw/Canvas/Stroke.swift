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

/// One sample of a finger moving over the canvas.
struct StrokePoint: Equatable, Codable {
    /// Canvas pixels, origin at the top-left corner, y growing downward.
    var x: Double
    var y: Double
    /// Seconds since the stroke began.
    var time: Double
    /// Finger contact radius in canvas pixels, a rough stand-in for pressure. 0 when unknown.
    var radius: Double

    init(x: Double, y: Double, time: Double = 0, radius: Double = 0) {
        self.x = x
        self.y = y
        self.time = time
        self.radius = radius
    }

    init(_ point: CGPoint, time: Double = 0, radius: Double = 0) {
        self.init(x: Double(point.x), y: Double(point.y), time: time, radius: radius)
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

/// The shape of the pen tip, in canvas pixels.
///
/// A *rectangle* is the flat edge of a broad-edge calligraphy pen; an *ellipse* is an oval tip (a circle when
/// `length == thickness`). Held at a fixed angle, a flat tip draws thick strokes across its edge and hairlines
/// along it, which is what gives calligraphy its look.
struct Nib: Equatable, Codable {
    enum Shape: String, Codable {
        case rectangle
        case ellipse
    }

    var shape: Shape
    /// Length of the tip's long side (the broad edge), in canvas pixels.
    var length: Double
    /// Thickness of the tip's short side, in canvas pixels. For a flat pen this is the hairline width.
    var thickness: Double
    /// Angle of the long side, in degrees counter-clockwise from horizontal as seen on screen.
    var angleDegrees: Double

    static func round(diameter: Double) -> Nib {
        Nib(shape: .ellipse, length: diameter, thickness: diameter, angleDegrees: 0)
    }
}

/// How the pen tip changes size as you draw. All distances are canvas pixels, speeds are pixels per second.
struct Dynamics: Equatable, Codable {
    /// 0 keeps the tip rigid; 1 lets speed shrink it all the way to `minScale` at `referenceSpeed`.
    var speedResponse: Double = 0
    /// How small the tip gets at `referenceSpeed`, as a fraction of its full size.
    var minScale: Double = 0.3
    var referenceSpeed: Double = 2000
    /// 0 ignores how hard the finger presses (its contact area); 1 follows it fully.
    var contactResponse: Double = 0
    /// The tip grows from `startScale` to full size over this distance at the start of a stroke. 0 = no taper.
    var taperIn: Double = 0
    var startScale: Double = 0.3
    /// When the finger lifts the stroke runs on for this distance, shrinking to `endScale`. 0 = no tail.
    var taperOut: Double = 0
    var endScale: Double = 0.1
    /// How quickly the pen catches up with the finger, as a time constant in seconds. A larger value smooths the
    /// line more (wobble disappears, curves become fluid) and lets the pen trail further behind the finger.
    var followTime: Double = 0.012

    /// A tip that never changes size.
    static let rigid = Dynamics()
}

/// Everything about how a stroke looks.
struct Brush: Equatable, Codable {
    var color: RGBAColor
    var nib: Nib
    var dynamics: Dynamics = .rigid

    /// A plain round pen of constant width.
    static func round(color: RGBAColor, diameter: Double) -> Brush {
        Brush(color: color, nib: .round(diameter: diameter))
    }
}

/// One finger-down-to-finger-up line, stored as the points the finger passed through. Together with its brush
/// this is enough to paint the stroke again exactly, at any time.
struct Stroke: Equatable, Codable {
    var brush: Brush
    var points: [StrokePoint]
}
