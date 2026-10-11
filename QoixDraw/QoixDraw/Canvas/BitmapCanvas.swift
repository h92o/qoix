import CoreGraphics
import Foundation

/// A fixed-size RGBA pixel buffer that strokes are painted into.
///
/// There are two layers of pixels, both in canvas pixels with the origin at the top-left corner (y grows
/// downward):
/// - the *committed* layer holds the finished picture, including finished chunks of strokes still being drawn;
/// - the *live* layer is transparent and holds only the part of the strokes in progress that isn't committed yet.
///   It is redrawn every frame, which is what lets a stroke be anti-aliased as a whole.
final class BitmapCanvas {
    let spec: CanvasSpec
    let background: RGBAColor
    private let base: CGContext
    private let live: CGContext
    /// The area of the live layer that currently has anything drawn in it.
    private var liveArea: CGRect = .null
    /// Goes up every time the committed pixels change, so whoever shows them knows when to refresh.
    private(set) var baseVersion = 0

    init?(spec: CanvasSpec, background: RGBAColor = .white) {
        guard let base = BitmapCanvas.makeContext(for: spec, flipped: true),
              let live = BitmapCanvas.makeContext(for: spec, flipped: true) else {
            return nil
        }
        self.spec = spec
        self.background = background
        self.base = base
        self.live = live
        clear()
    }

    private static func makeContext(for spec: CanvasSpec, flipped: Bool) -> CGContext? {
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
        if flipped {
            // Work in "screen" coordinates: origin top-left, y grows downward.
            context.translateBy(x: 0, y: CGFloat(spec.height))
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
        live.clear(fullRect)
        liveArea = .null
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

    /// Redraws the live layer: clears what was there and draws the uncommitted part of each stroke in progress.
    func updateLive(_ sessions: [StrokeSession]) {
        if !liveArea.isNull {
            live.clear(liveArea)
        }
        var area = CGRect.null
        for session in sessions {
            area = area.union(session.drawPending(into: live))
        }
        liveArea = area
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

    /// A snapshot of the live layer (transparent where nothing is being drawn).
    func makeLiveImage() -> CGImage? {
        live.makeImage()
    }

    /// The picture as it should be saved: committed pixels with any stroke still in progress on top. The image is
    /// immutable, so it is safe to encode on a background queue while the user keeps drawing.
    func makeSnapshot() -> CGImage? {
        guard let committed = base.makeImage() else { return nil }
        guard !liveArea.isNull,
              let overlay = live.makeImage(),
              let context = BitmapCanvas.makeContext(for: spec, flipped: false) else {
            return committed
        }
        context.draw(committed, in: fullRect)
        context.draw(overlay, in: fullRect)
        return context.makeImage() ?? committed
    }

    // MARK: Inspection (used by tests)

    /// The premultiplied RGBA bytes of the committed pixel at `x`, `y` (top-left origin).
    func pixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        BitmapCanvas.pixel(in: base, x: x, y: y, width: spec.width, height: spec.height)
    }

    /// The premultiplied RGBA bytes of the live-layer pixel at `x`, `y`.
    func livePixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        BitmapCanvas.pixel(in: live, x: x, y: y, width: spec.width, height: spec.height)
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
