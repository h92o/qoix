import CoreGraphics
import Foundation

/// Convex hulls of small point sets.
enum ConvexHull {
    /// The smallest convex polygon containing `points`, always wound the same way (so overlapping hulls add up
    /// under the non-zero fill rule instead of cancelling). Fewer than three points are returned as they are.
    static func hull(of points: [CGPoint]) -> [CGPoint] {
        let sorted = points.sorted { first, second in
            first.x != second.x ? first.x < second.x : first.y < second.y
        }
        guard sorted.count > 2 else { return sorted }

        var lower: [CGPoint] = []
        for point in sorted {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 {
                lower.removeLast()
            }
            lower.append(point)
        }
        var upper: [CGPoint] = []
        for point in sorted.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 {
                upper.removeLast()
            }
            upper.append(point)
        }
        lower.removeLast()
        upper.removeLast()
        return lower + upper
    }

    private static func cross(_ origin: CGPoint, _ first: CGPoint, _ second: CGPoint) -> CGFloat {
        (first.x - origin.x) * (second.y - origin.y) - (first.y - origin.y) * (second.x - origin.x)
    }
}

/// The outline of a pen tip, and where it lands when the tip is placed on the canvas.
struct NibGeometry {
    /// The tip can never be thinner than this (canvas pixels): a perfectly flat tip would leave no ink.
    static let minimumExtent: Double = 0.8

    /// Corners of the tip relative to its center, at full size. Convex.
    let outline: [CGPoint]

    init(nib: Nib) {
        let angle = CGFloat(nib.angleDegrees * Double.pi / 180)
        // The tip's own axes on screen. y grows downward, so "counter-clockwise" flips the sign of y.
        let along = CGPoint(x: cos(angle), y: -sin(angle))
        let across = CGPoint(x: sin(angle), y: cos(angle))
        let halfLength = CGFloat(max(nib.length, Self.minimumExtent)) / 2
        let halfThickness = CGFloat(max(nib.thickness, Self.minimumExtent)) / 2

        func place(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            CGPoint(x: along.x * u + across.x * v, y: along.y * u + across.y * v)
        }

        switch nib.shape {
        case .rectangle:
            outline = [
                place(-halfLength, -halfThickness),
                place(halfLength, -halfThickness),
                place(halfLength, halfThickness),
                place(-halfLength, halfThickness),
            ]
        case .ellipse:
            let count = 24
            outline = (0..<count).map { index in
                let theta = 2 * CGFloat.pi * CGFloat(index) / CGFloat(count)
                return place(halfLength * cos(theta), halfThickness * sin(theta))
            }
        }
    }

    /// The tip's corners when it is centered on `center` and scaled to `scale` of its full size.
    func polygon(center: CGPoint, scale: CGFloat) -> [CGPoint] {
        outline.map { corner in
            CGPoint(x: center.x + corner.x * scale, y: center.y + corner.y * scale)
        }
    }

    /// How far any part of the tip can reach from its center at full size.
    var reach: CGFloat {
        outline.reduce(0) { farthest, corner in
            max(farthest, hypot(corner.x, corner.y))
        }
    }
}
