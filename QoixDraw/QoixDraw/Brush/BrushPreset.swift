import Foundation

/// A pen as you set it up. Sizes are in screen points, so the pen looks the same on every phone; they are
/// converted to canvas pixels when a stroke starts.
struct BrushPreset: Equatable, Codable, Identifiable {
    var name: String
    var shape: Nib.Shape
    /// Length of the tip's long side (the broad edge of a flat pen), in points.
    var lengthPoints: Double
    /// Thickness of the tip's short side (the hairline of a flat pen), in points.
    var thicknessPoints: Double
    /// Angle of the long side, in degrees counter-clockwise from horizontal.
    var angleDegrees: Double

    /// 0 keeps the tip rigid; 1 lets speed shrink it all the way to `minScale`.
    var speedResponse: Double
    var minScale: Double
    /// The speed (points per second) at which the tip is at its smallest.
    var referenceSpeedPoints: Double
    /// 0 ignores how hard the finger presses; 1 follows its contact area fully.
    var contactResponse: Double
    var taperInPoints: Double
    var startScale: Double
    var taperOutPoints: Double
    var endScale: Double
    /// 0 puts the ink right under the finger's path; 1 smooths the path as much as the pen allows.
    var smoothing: Double

    var id: String {
        name
    }

    /// How long the pen takes to catch up with the finger (seconds) for a smoothing setting from 0 to 1:
    /// 4 ms is almost raw, 60 ms is very fluid.
    static func followTime(forSmoothing smoothing: Double) -> Double {
        0.004 * pow(15.0, min(max(smoothing, 0), 1))
    }

    /// The brush to paint with, for a canvas that has `pixelsPerPoint` canvas pixels per screen point.
    func brush(color: RGBAColor, pixelsPerPoint scale: Double) -> Brush {
        Brush(
            color: color,
            nib: Nib(shape: shape,
                     length: lengthPoints * scale,
                     thickness: thicknessPoints * scale,
                     angleDegrees: angleDegrees),
            dynamics: Dynamics(speedResponse: speedResponse,
                               minScale: minScale,
                               referenceSpeed: referenceSpeedPoints * scale,
                               contactResponse: contactResponse,
                               taperIn: taperInPoints * scale,
                               startScale: startScale,
                               taperOut: taperOutPoints * scale,
                               endScale: endScale,
                               followTime: BrushPreset.followTime(forSmoothing: smoothing))
        )
    }
}

extension BrushPreset {
    /// A flat, broad-edge pen: thick across its edge, hairline along it. The classic italic/gothic look.
    static func flat(_ name: String, length: Double, angle: Double) -> BrushPreset {
        BrushPreset(name: name, shape: .rectangle, lengthPoints: length, thicknessPoints: max(length * 0.1, 1.2),
                    angleDegrees: angle, speedResponse: 0, minScale: 0.3, referenceSpeedPoints: 1000,
                    contactResponse: 0, taperInPoints: 0, startScale: 0.3, taperOutPoints: 0, endScale: 0.1,
                    smoothing: 0.6)
    }

    static let chisel45 = flat("Chisel 45°", length: 12, angle: 45)
    static let chisel30 = flat("Chisel 30°", length: 12, angle: 30)

    /// An oval tip: the same thick/thin rhythm as a flat pen with softer transitions.
    static let oval35 = BrushPreset(
        name: "Oval 35°", shape: .ellipse, lengthPoints: 13, thicknessPoints: 4, angleDegrees: 35,
        speedResponse: 0, minScale: 0.3, referenceSpeedPoints: 1000, contactResponse: 0,
        taperInPoints: 0, startScale: 0.3, taperOutPoints: 0, endScale: 0.1, smoothing: 0.6)

    /// A round brush: slow strokes are fat, fast strokes are thin, and strokes start and end in a point.
    static let roundBrush = BrushPreset(
        name: "Brush", shape: .ellipse, lengthPoints: 9, thicknessPoints: 9, angleDegrees: 0,
        speedResponse: 0.85, minScale: 0.2, referenceSpeedPoints: 900, contactResponse: 0,
        taperInPoints: 10, startScale: 0.3, taperOutPoints: 16, endScale: 0.05, smoothing: 0.7)

    /// A pointed pen: a fine round line that swells when you slow down and flicks out at the end.
    static let pointed = BrushPreset(
        name: "Pointed pen", shape: .ellipse, lengthPoints: 5.5, thicknessPoints: 5.5, angleDegrees: 0,
        speedResponse: 0.55, minScale: 0.35, referenceSpeedPoints: 900, contactResponse: 0,
        taperInPoints: 6, startScale: 0.5, taperOutPoints: 10, endScale: 0.2, smoothing: 0.6)

    /// A plain round marker of constant width.
    static let marker = BrushPreset(
        name: "Marker", shape: .ellipse, lengthPoints: 4, thicknessPoints: 4, angleDegrees: 0,
        speedResponse: 0, minScale: 0.3, referenceSpeedPoints: 1000, contactResponse: 0,
        taperInPoints: 0, startScale: 0.3, taperOutPoints: 0, endScale: 0.1, smoothing: 0.4)

    /// The built-in pens, in the order the brush sheet lists them.
    static let all: [BrushPreset] = [.chisel45, .chisel30, .oval35, .roundBrush, .pointed, .marker]
}
