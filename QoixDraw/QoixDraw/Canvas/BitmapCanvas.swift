import CoreGraphics
import Foundation

/// A fixed-size RGBA pixel buffer that strokes are painted into.
///
/// Pixels are in canvas pixels with the origin at the top-left corner (y grows downward). There are two layers:
/// - the *committed* layer holds the finished picture, including finished chunks of strokes still being drawn;
/// - the *live* layer is a small transparent bitmap that covers only the area touched by the part of the strokes
///   in progress that isn't committed yet. It is redrawn every frame, which is what lets a stroke be anti-aliased
///   as a whole, and being small keeps each frame cheap however large the canvas is.
final class BitmapCanvas {
    let spec: CanvasSpec
    let background: RGBAColor
    private let base: CGContext
    private var liveContext: CGContext?
    /// Where the live layer sits on the canvas (whole canvas pixels), or `.null` when nothing is being drawn.
    private(set) var liveRect: CGRect = .null
    /// Goes up every time the committed pixels change, so whoever shows them knows when to refresh.
    private(set) var baseVersion = 0

    init?(spec: CanvasSpec, background: RGBAColor = .white) {
        guard let base = BitmapCanvas.makeContext(width: spec.width, height: spec.height, flipped: true) else {
            return nil
        }
        self.spec = spec
        self.background = background
        self.base = base
        clear()
    }

    private static func makeContext(width: Int, height: Int, flipped: Bool) -> CGContext? {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        if flipped {
            // Work in "screen" coordinates: origin top-left, y grows downward.
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
        }
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.interpolationQuality = .high
        return context
    }

    private var fullRect: CGRect {
        CGRect(x: 0, y: 0, width: spec.width, height: spec.height)
    }

    /// Fills the whole canvas with the background color and empties the live layer.
    func clear() {
        base.setFillColor(background.cgColor)
        base.fill(fullRect)
        liveContext = nil
        liveRect = .null
        baseVersion += 1
    }

    // MARK: Painting strokes

    /// Starts a stroke at `start`. Nothing is painted until the session is updated or finished.
    func beginStroke(brush: Brush, start: StrokePoint) -> StrokeSession {
        StrokeSession(brush: brush, start: start)
    }

    /// Adds a point to a stroke in progress and paints any chunk it completes into the committed layer.
    /// Returns false if the point was too close to the last one and was skipped.
    @discardableResult
    func extend(_ session: StrokeSession, with point: StrokePoint) -> Bool {
        guard session.add(point) else { return false }
        if session.bakeCompleteChunks(into: base) {
            baseVersion += 1
        }
        return true
    }

    /// Redraws the live layer: a fresh transparent bitmap that covers the part of each stroke in progress that
    /// isn't committed yet (and nothing else).
    func updateLive(_ sessions: [StrokeSession]) {
        var area = CGRect.null
        for session in sessions {
            area = area.union(session.pendingArea)
        }
        let bounds = area.isNull ? CGRect.null : area.integral.intersection(fullRect)
        guard !bounds.isNull, !bounds.isEmpty,
              let context = BitmapCanvas.makeContext(width: Int(bounds.width), height: Int(bounds.height), flipped: true) else {
            liveContext = nil
            liveRect = .null
            return
        }
        // Canvas pixel (x, y) lands at (x - minX, y - minY) in the small bitmap, on the same pixel grid as the
        // full canvas, so a stroke looks the same here as when it is committed.
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        for session in sessions {
            session.drawPending(into: context)
        }
        liveContext = context
        liveRect = bounds
    }

    /// Ends a stroke: paints the rest of it into the committed layer and returns the finished stroke.
    func finish(_ session: StrokeSession) -> Stroke {
        let stroke = session.finish(into: base)
        baseVersion += 1
        return stroke
    }

    /// Paints a complete stroke in one go (used when replaying a drawing).
    func paint(_ stroke: Stroke) {
        StrokeRenderer.render(stroke, into: base)
        baseVersion += 1
    }

    /// Clears the canvas and repaints `strokes` in order.
    func repaint(_ strokes: [Stroke]) {
        clear()
        for stroke in strokes {
            paint(stroke)
        }
    }

    // MARK: Images

    /// A snapshot of the committed pixels. The image is immutable: painting afterwards does not change it.
    func makeImage() -> CGImage? {
        base.makeImage()
    }

    /// A snapshot of the live layer, to be shown at `liveRect`. Nil when nothing is being drawn.
    func makeLiveImage() -> CGImage? {
        liveContext?.makeImage()
    }

    /// The picture as it should be saved: committed pixels with any stroke still in progress on top. The image is
    /// immutable, so it is safe to encode on a background queue while the user keeps drawing.
    func makeSnapshot() -> CGImage? {
        guard let committed = base.makeImage() else { return nil }
        guard !liveRect.isNull,
              let overlay = liveContext?.makeImage(),
              let context = BitmapCanvas.makeContext(width: spec.width, height: spec.height, flipped: false) else {
            return committed
        }
        context.draw(committed, in: fullRect)
        // This context has its origin at the bottom-left, the live rectangle is measured from the top-left.
        context.draw(overlay, in: CGRect(x: liveRect.minX, y: CGFloat(spec.height) - liveRect.maxY,
                                         width: liveRect.width, height: liveRect.height))
        return context.makeImage() ?? committed
    }

    // MARK: Inspection (used by tests)

    /// The premultiplied RGBA bytes of the committed pixel at `x`, `y` (top-left origin).
    func pixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        BitmapCanvas.pixel(in: base, x: x, y: y, width: spec.width, height: spec.height)
    }

    /// The premultiplied RGBA bytes of the live layer at canvas pixel `x`, `y`: transparent wherever nothing is
    /// being drawn, and nil outside the canvas.
    func livePixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        guard x >= 0, y >= 0, x < spec.width, y < spec.height else { return nil }
        if let context = liveContext, !liveRect.isNull,
           let local = BitmapCanvas.pixel(in: context, x: x - Int(liveRect.minX), y: y - Int(liveRect.minY),
                                          width: context.width, height: context.height) {
            return local
        }
        return (0, 0, 0, 0)
    }

    /// A copy of the raw committed pixel bytes, row by row.
    func rawBytes() -> Data? {
        guard let data = base.data else { return nil }
        return Data(bytes: data, count: base.bytesPerRow * spec.height)
    }

    private static func pixel(in context: CGContext, x: Int, y: Int, width: Int, height: Int)
        -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        guard x >= 0, y >= 0, x < width, y < height, let data = context.data else { return nil }
        let p = data.assumingMemoryBound(to: UInt8.self) + y * context.bytesPerRow + x * 4
        return (p[0], p[1], p[2], p[3])
    }
}
