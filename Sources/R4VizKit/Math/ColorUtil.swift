import Foundation

/// Platform-independent HSB → RGB conversion.
///
/// Scenes pass raw RGB to ``GL/glColor(_:_:_:_:)``, so we compute colors here
/// rather than round-tripping through `Color` (which would require UIKit/AppKit
/// to read components back). Hue/sat/brightness are all `0...1`.
public func hsb(_ h: Double, _ s: Double, _ b: Double) -> (r: Double, g: Double, b: Double) {
    if s <= 0 { return (b, b, b) }
    let hue = (h.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
    let i = Int(hue)
    let f = hue - Double(i)
    let p = b * (1 - s)
    let q = b * (1 - s * f)
    let t = b * (1 - s * (1 - f))
    switch i % 6 {
    case 0: return (b, t, p)
    case 1: return (q, b, p)
    case 2: return (p, b, t)
    case 3: return (p, q, b)
    case 4: return (t, p, b)
    default: return (b, p, q)
    }
}
