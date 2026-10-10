import CoreGraphics
import Foundation

/// A fixed-size RGBA pixel buffer that strokes are painted into.
///
/// Coordinates are canvas pixels with the origin at the top-left corner (y grows downward).
final class BitmapCanvas {
    let spec: CanvasSpec
    let background: RGBAColor
    private let context: CGContext

    init?(spec: CanvasSpec, background: RGBAColor = .white) {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: spec.width,
            height: spec.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        // Work in "screen" coordinates: origin top-left, y grows downward.
        context.translateBy(x: 0, y: CGFloat(spec.height))
        context.scaleBy(x: 1, y: -1)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.interpolationQuality = .high

        self.spec = spec
        self.background = background
        self.context = context
        clear()
    }

    /// Fills the whole canvas with the background color.
    func clear() {
        context.setFillColor(background.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: spec.width, height: spec.height))
    }

    /// Starts a stroke: paints its first dot and returns the painter that continues it.
    func beginStroke(brush: Brush, at point: CGPoint) -> StrokePainter {
        StrokePainter(brush: brush, start: point, context: context)
    }

    /// Paints a complete stroke in one go (used when replaying a drawing).
    func paint(_ stroke: Stroke) {
        guard let first = stroke.points.first else { return }
        let painter = beginStroke(brush: stroke.brush, at: first)
        for point in stroke.points.dropFirst() {
            painter.extend(to: point)
        }
        painter.finish()
    }

    /// Clears the canvas and repaints `strokes` in order.
    func repaint(_ strokes: [Stroke]) {
        clear()
        for stroke in strokes {
            paint(stroke)
        }
    }

    /// A snapshot of the pixels. The image is immutable: painting afterwards does not change it, so it is
    /// safe to encode on a background queue while the user keeps drawing.
    func makeImage() -> CGImage? {
        context.makeImage()
    }

    // MARK: Inspection (used by tests)

    /// The premultiplied RGBA bytes of the pixel at `x`, `y` (top-left origin).
    func pixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        guard x >= 0, y >= 0, x < spec.width, y < spec.height, let base = context.data else { return nil }
        let p = base.assumingMemoryBound(to: UInt8.self) + y * context.bytesPerRow + x * 4
        return (p[0], p[1], p[2], p[3])
    }

    /// A copy of the raw pixel bytes, row by row.
    func rawBytes() -> Data? {
        guard let base = context.data else { return nil }
        return Data(bytes: base, count: context.bytesPerRow * spec.height)
    }
}

/// Paints one stroke into a bitmap as the finger moves.
///
/// Points are joined with quadratic curves that run from midpoint to midpoint, using each raw point as the
/// control point. That keeps lines smooth without lagging behind the finger. Replaying a stored stroke runs
/// exactly the same code, so a repaint after undo/redo is pixel-identical to what was drawn live.
final class StrokePainter {
    /// Points closer together than this (in canvas pixels) are treated as jitter and skipped.
    static let minimumStep: CGFloat = 0.25

    let brush: Brush
    private let context: CGContext
    private var last: CGPoint
    private var lastMid: CGPoint

    init(brush: Brush, start: CGPoint, context: CGContext) {
        self.brush = brush
        self.context = context
        self.last = start
        self.lastMid = start
        paintDot(at: start)
    }

    /// Adds a point to the stroke. Returns `false` (and paints nothing) when the point is too close to the
    /// previous one to matter.
    @discardableResult
    func extend(to point: CGPoint) -> Bool {
        let dx = point.x - last.x
        let dy = point.y - last.y
        guard dx * dx + dy * dy >= Self.minimumStep * Self.minimumStep else { return false }

        let mid = CGPoint(x: (last.x + point.x) / 2, y: (last.y + point.y) / 2)
        applyBrush()
        context.beginPath()
        context.move(to: lastMid)
        context.addQuadCurve(to: mid, control: last)
        context.strokePath()

        lastMid = mid
        last = point
        return true
    }

    /// Ends the stroke by running the line out to the final point.
    func finish() {
        guard lastMid != last else { return }
        applyBrush()
        context.beginPath()
        context.move(to: lastMid)
        context.addLine(to: last)
        context.strokePath()
        lastMid = last
    }

    private func applyBrush() {
        context.setStrokeColor(brush.color.cgColor)
        context.setLineWidth(CGFloat(brush.width))
        context.setLineCap(.round)
        context.setLineJoin(.round)
    }

    private func paintDot(at point: CGPoint) {
        let radius = CGFloat(brush.width) / 2
        context.setFillColor(brush.color.cgColor)
        context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
    }
}
