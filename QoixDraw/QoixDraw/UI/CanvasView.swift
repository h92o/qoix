import UIKit

/// The drawing surface: turns touches into strokes, keeps the document, and shows the pixels.
final class CanvasView: UIView {
    // MARK: Model

    private(set) var drawing: Drawing
    private let bitmap: BitmapCanvas

    /// Undo/redo history. Shaking the phone, a three-finger swipe, or ⌘Z steps through it.
    let history = UndoManager()

    // MARK: Pen

    var penColor: RGBAColor = AppConfig.penColor

    /// Thickness on screen, in points.
    var penWidthPoints: Double = AppConfig.penWidthPoints

    // MARK: Touch state

    private final class ActiveStroke {
        let painter: StrokePainter
        var stroke: Stroke

        init(painter: StrokePainter, stroke: Stroke) {
            self.painter = painter
            self.stroke = stroke
        }
    }

    /// Strokes currently being drawn, one per finger.
    private var activeStrokes: [AnyHashable: ActiveStroke] = [:]

    // MARK: Setup

    init?(canvas: CanvasSpec, background: RGBAColor = AppConfig.canvasBackground) {
        guard let bitmap = BitmapCanvas(spec: canvas, background: background) else { return nil }
        self.bitmap = bitmap
        self.drawing = Drawing(canvas: canvas, background: background)
        super.init(frame: .zero)

        // Each stroke registers its own undo step explicitly (see `commit`), independent of the run loop.
        history.groupsByEvent = false
        history.levelsOfUndo = 200

        isMultipleTouchEnabled = true
        isOpaque = true
        backgroundColor = UIColor(white: 0.1, alpha: 1)
        layer.contentsGravity = .resizeAspect

        isAccessibilityElement = true
        accessibilityLabel = "Drawing canvas"
        accessibilityHint = "Touch and drag to draw. Press Volume Down to save."
        accessibilityTraits = .allowsDirectInteraction

        present()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Geometry

    /// Where the canvas sits inside the view: aspect-fit, so it fills the view when the shapes match.
    var canvasFrame: CGRect {
        CanvasView.aspectFit(drawing.canvas.size, in: bounds)
    }

    static func aspectFit(_ content: CGSize, in container: CGRect) -> CGRect {
        guard content.width > 0, content.height > 0, container.width > 0, container.height > 0 else { return .zero }
        let scale = min(container.width / content.width, container.height / content.height)
        let size = CGSize(width: content.width * scale, height: content.height * scale)
        return CGRect(x: container.midX - size.width / 2, y: container.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// How many canvas pixels there are per point of screen.
    private var canvasPixelsPerPoint: CGFloat {
        let frame = canvasFrame
        return frame.width > 0 ? CGFloat(drawing.canvas.width) / frame.width : 1
    }

    /// Converts a point in this view to canvas pixels.
    func canvasPoint(forViewPoint point: CGPoint) -> CGPoint {
        let frame = canvasFrame
        let scale = canvasPixelsPerPoint
        return CGPoint(x: (point.x - frame.minX) * scale, y: (point.y - frame.minY) * scale)
    }

    // MARK: Strokes

    func beginStroke(id: AnyHashable, atViewPoint viewPoint: CGPoint) {
        let point = canvasPoint(forViewPoint: viewPoint)
        let brush = Brush(color: penColor, width: penWidthPoints * Double(canvasPixelsPerPoint))
        let painter = bitmap.beginStroke(brush: brush, at: point)
        activeStrokes[id] = ActiveStroke(painter: painter, stroke: Stroke(brush: brush, points: [point]))
    }

    func extendStroke(id: AnyHashable, toViewPoint viewPoint: CGPoint) {
        guard let active = activeStrokes[id] else { return }
        let point = canvasPoint(forViewPoint: viewPoint)
        if active.painter.extend(to: point) {
            active.stroke.points.append(point)
        }
    }

    func endStroke(id: AnyHashable) {
        guard let active = activeStrokes.removeValue(forKey: id) else { return }
        active.painter.finish()
        commit(active.stroke)
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            beginStroke(id: ObjectIdentifier(touch), atViewPoint: touch.location(in: self))
        }
        present()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            // iOS can report more finger positions than it delivers events; use them all for smoother lines.
            let samples = event?.coalescedTouches(for: touch) ?? [touch]
            for sample in samples {
                extendStroke(id: ObjectIdentifier(touch), toViewPoint: sample.location(in: self))
            }
        }
        present()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            extendStroke(id: id, toViewPoint: touch.location(in: self))
            endStroke(id: id)
        }
        present()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    // MARK: Whole-canvas operations

    /// An immutable snapshot of the pixels, at canvas resolution (never larger than 2000 x 2000).
    func makeSnapshot() -> CGImage? {
        bitmap.makeImage()
    }

    /// Clears the canvas for a new picture. Undoable: shake to bring the old picture back.
    func startNewCanvas() {
        // Fingers still down are cut off, and the dots they already painted are wiped with everything else.
        let hadStrokesInProgress = !activeStrokes.isEmpty
        activeStrokes.removeAll()
        guard !drawing.isEmpty else {
            if hadStrokesInProgress {
                repaint()
            }
            return
        }

        let removed = drawing.removeAllStrokes()
        history.beginUndoGrouping()
        history.registerUndo(withTarget: self, selector: #selector(restoreStrokes(_:)), object: StrokeBox(removed))
        history.setActionName("New Canvas")
        history.endUndoGrouping()
        repaint()
    }

    // MARK: Undo and redo
    //
    // Every edit registers its inverse with the undo manager. The selector-based API is used because it
    // carries no concurrency annotations to trip over; the handlers run synchronously on the main thread.

    /// Wraps strokes so they can ride along in an undo registration.
    private final class StrokeBox: NSObject {
        let strokes: [Stroke]

        init(_ strokes: [Stroke]) {
            self.strokes = strokes
        }
    }

    private func commit(_ stroke: Stroke) {
        drawing.append(stroke)
        history.beginUndoGrouping()
        history.registerUndo(withTarget: self, selector: #selector(undoLastStroke(_:)), object: nil)
        history.setActionName("Stroke")
        history.endUndoGrouping()
    }

    @objc private func undoLastStroke(_ unused: Any?) {
        guard let removed = drawing.removeLastStroke() else { return }
        history.registerUndo(withTarget: self, selector: #selector(redoStroke(_:)), object: StrokeBox([removed]))
        history.setActionName("Stroke")
        repaint()
    }

    @objc private func redoStroke(_ box: StrokeBox) {
        for stroke in box.strokes {
            drawing.append(stroke)
        }
        history.registerUndo(withTarget: self, selector: #selector(undoLastStroke(_:)), object: nil)
        history.setActionName("Stroke")
        repaint()
    }

    /// Swaps the drawing's strokes for `box.strokes`, registering the swap back (so it works both ways).
    @objc private func restoreStrokes(_ box: StrokeBox) {
        let current = drawing.removeAllStrokes()
        drawing.replaceStrokes(with: box.strokes)
        history.registerUndo(withTarget: self, selector: #selector(restoreStrokes(_:)), object: StrokeBox(current))
        history.setActionName("New Canvas")
        repaint()
    }

    // MARK: Display

    private func repaint() {
        bitmap.repaint(drawing.strokes)
        present()
    }

    private func present() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = bitmap.makeImage()
        CATransaction.commit()
    }

    // MARK: Inspection (used by tests)

    func pixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        bitmap.pixel(x: x, y: y)
    }
}
