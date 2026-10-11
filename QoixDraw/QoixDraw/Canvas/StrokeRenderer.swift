import CoreGraphics
import Foundation

/// Paints one stroke into bitmaps as the finger moves, and again later when a drawing is replayed.
///
/// The pen tip is dragged along the path; the ink laid down between two neighboring tip positions is the convex
/// hull of the tip at both, which is exact for any convex tip (a flat edge, an oval, a circle) and for a tip whose
/// size changes along the way. Hulls are filled together as one shape, so the edge of the stroke is
/// anti-aliased as a whole instead of being darkened where hulls overlap.
///
/// To make that cheap while drawing, the hulls are painted in fixed-size chunks (by position in the stroke, not by
/// when finger events happened to arrive):
/// - a *complete* chunk is painted once into the permanent bitmap,
/// - the *pending* hulls after the last complete chunk are redrawn each frame into a small transparent layer.
///
/// Because chunks depend only on the stroke itself, painting a stroke live and painting it later from its saved
/// points produce identical pixels.
final class StrokeSession {
    /// How many hulls are painted together as one chunk.
    static let chunkSize = 40

    let brush: Brush
    private let builder: StrokeBuilder
    private let geometry: NibGeometry
    /// The points that were kept (jitter removed), exactly what is needed to paint this stroke again.
    private(set) var points: [StrokePoint]
    private var bakedCount = 0

    init(brush: Brush, start: StrokePoint) {
        self.brush = brush
        self.builder = StrokeBuilder(brush: brush, start: start)
        self.geometry = NibGeometry(nib: brush.nib)
        self.points = [start]
    }

    /// The number of pen-tip positions so far (mostly useful in tests).
    var stepCount: Int {
        builder.steps.count
    }

    /// Adds a point. Returns false if it was too close to the last one and was skipped.
    @discardableResult
    func add(_ point: StrokePoint) -> Bool {
        guard builder.add(point) else { return false }
        points.append(point)
        return true
    }

    /// Paints every complete chunk that hasn't been painted yet into `context`. Returns true if it painted any.
    @discardableResult
    func bakeCompleteChunks(into context: CGContext) -> Bool {
        var painted = false
        while builder.steps.count - bakedCount >= Self.chunkSize {
            fill(bakedCount..<(bakedCount + Self.chunkSize), into: context)
            bakedCount += Self.chunkSize
            painted = true
        }
        return painted
    }

    /// A rectangle (canvas pixels) covering the ink of the hulls that aren't painted into the permanent bitmap
    /// yet, with room for anti-aliasing. `.null` when there are none.
    var pendingArea: CGRect {
        area(of: bakedCount..<builder.steps.count)
    }

    /// Paints the hulls after the last complete chunk into `context`, a transparent layer that is cleared
    /// before every frame.
    func drawPending(into context: CGContext) {
        fill(bakedCount..<builder.steps.count, into: context)
    }

    /// Ends the stroke and paints everything not yet painted into `context`. Returns the finished stroke.
    func finish(into context: CGContext) -> Stroke {
        builder.finish()
        bakeCompleteChunks(into: context)
        let range = bakedCount..<builder.steps.count
        fill(range, into: context)
        bakedCount = builder.steps.count
        return Stroke(brush: brush, points: points)
    }

    // MARK: Painting

    private func fill(_ range: Range<Int>, into context: CGContext) {
        guard !range.isEmpty else { return }
        let steps = builder.steps
        let path = CGMutablePath()

        for index in range {
            let current = geometry.polygon(center: steps[index].center, scale: steps[index].scale)
            let outline: [CGPoint]
            if index == 0 {
                outline = ConvexHull.hull(of: current)
            } else {
                let previous = geometry.polygon(center: steps[index - 1].center, scale: steps[index - 1].scale)
                outline = ConvexHull.hull(of: previous + current)
            }
            guard outline.count >= 3 else { continue }
            path.addLines(between: outline)
            path.closeSubpath()
        }

        context.setFillColor(brush.color.cgColor)
        context.addPath(path)
        context.fillPath()
    }

    /// A rectangle covering the ink the hulls in `range` can have laid down, with room for anti-aliasing.
    private func area(of range: Range<Int>) -> CGRect {
        guard !range.isEmpty else { return .null }
        let steps = builder.steps
        let first = max(range.lowerBound - 1, 0)
        var minX = CGFloat.infinity
        var minY = CGFloat.infinity
        var maxX = -CGFloat.infinity
        var maxY = -CGFloat.infinity
        for index in first..<range.upperBound {
            let center = steps[index].center
            minX = min(minX, center.x)
            minY = min(minY, center.y)
            maxX = max(maxX, center.x)
            maxY = max(maxY, center.y)
        }
        // The tip may be drawn up to 1.6x its size when the finger presses hard.
        let margin = geometry.reach * 1.6 + 3
        return CGRect(x: minX - margin, y: minY - margin, width: maxX - minX + 2 * margin, height: maxY - minY + 2 * margin)
    }
}

enum StrokeRenderer {
    /// Paints a whole stroke into `context` in one go. Used to replay strokes and to draw previews.
    static func render(_ stroke: Stroke, into context: CGContext) {
        guard let first = stroke.points.first else { return }
        let session = StrokeSession(brush: stroke.brush, start: first)
        for point in stroke.points.dropFirst() {
            session.add(point)
        }
        _ = session.finish(into: context)
    }
}
