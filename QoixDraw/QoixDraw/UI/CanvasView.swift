import UIKit

/// The drawing surface: turns touches into strokes, keeps the document, and shows the pixels.
final class CanvasView: UIView {
    // MARK: Model

    private(set) var drawing: Drawing
    private let bitmap: BitmapCanvas

    /// Undo/redo history. The shake menu, a three-finger swipe, or ⌘Z steps through it.
    let history = UndoManager()

    /// The pen used for new strokes.
    let pen: PenSettings

    // MARK: Layers

    /// Shows the part of the strokes in progress that isn't committed yet, above the committed picture (which
    /// is this view's own layer).
    private let liveLayer = CALayer()
    private var presentedBaseVersion = -1

    // MARK: Touch state

    /// A finger that is down but hasn't moved far enough to start drawing yet.
    private struct PendingTouch {
        var startViewPoint: CGPoint
        var startTime: TimeInterval
        var samples: [StrokePoint]
    }

    private final class ActiveStroke {
        let session: StrokeSession
        let startTime: TimeInterval

        init(session: StrokeSession, startTime: TimeInterval) {
            self.session = session
            self.startTime = startTime
        }
    }

    private var pendingTouches: [AnyHashable: PendingTouch] = [:]
    /// Strokes currently being drawn, one per finger.
    private var activeStrokes: [AnyHashable: ActiveStroke] = [:]

    // MARK: Setup

    init?(canvas: CanvasSpec,
          pen: PenSettings = PenSettings(defaults: nil),
          background: RGBAColor = AppConfig.canvasBackground) {
        guard let bitmap = BitmapCanvas(spec: canvas, background: background) else { return nil }
        self.bitmap = bitmap
        self.pen = pen
        self.drawing = Drawing(canvas: canvas, background: background)
        super.init(frame: .zero)

        // Each stroke registers its own undo step explicitly (see `commit`), independent of the run loop.
        history.groupsByEvent = false
        history.levelsOfUndo = 200

        isMultipleTouchEnabled = true
        isOpaque = true
        backgroundColor = UIColor(white: 0.1, alpha: 1)
        layer.contentsGravity = .resizeAspect
        liveLayer.contentsGravity = .resizeAspect
        layer.addSublayer(liveLayer)

        isAccessibilityElement = true
        accessibilityIdentifier = "canvas"
        accessibilityLabel = "Drawing canvas"
        accessibilityHint = "Touch and drag to draw. Press Volume Down to save."
        accessibilityTraits = .allowsDirectInteraction

        refreshDisplay()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        liveLayer.frame = bounds
        CATransaction.commit()
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
    var canvasPixelsPerPoint: CGFloat {
        let frame = canvasFrame
        return frame.width > 0 ? CGFloat(drawing.canvas.width) / frame.width : 1
    }

    /// Converts a point in this view to canvas pixels.
    func canvasPoint(forViewPoint point: CGPoint) -> CGPoint {
        let frame = canvasFrame
        let scale = canvasPixelsPerPoint
        return CGPoint(x: (point.x - frame.minX) * scale, y: (point.y - frame.minY) * scale)
    }

    private func makePoint(_ viewPoint: CGPoint, time: TimeInterval, contactRadius: CGFloat) -> StrokePoint {
        StrokePoint(canvasPoint(forViewPoint: viewPoint),
                    time: time,
                    radius: Double(contactRadius * canvasPixelsPerPoint))
    }

    // MARK: Strokes
    //
    // A finger touching down does not draw straight away. It starts a stroke once it has moved a little, and a
    // quick tap leaves a dot. So a thumb resting on the screen while the other hand draws never marks it.

    func beginStroke(id: AnyHashable, atViewPoint viewPoint: CGPoint,
                     time: TimeInterval = ProcessInfo.processInfo.systemUptime, contactRadius: CGFloat = 0) {
        accessibilityValue = nil // Any earlier status ("Saved to Photos") no longer describes the canvas.
        let first = makePoint(viewPoint, time: 0, contactRadius: contactRadius)
        pendingTouches[id] = PendingTouch(startViewPoint: viewPoint, startTime: time, samples: [first])
    }

    func extendStroke(id: AnyHashable, toViewPoint viewPoint: CGPoint,
                      time: TimeInterval = ProcessInfo.processInfo.systemUptime, contactRadius: CGFloat = 0) {
        if var pending = pendingTouches[id] {
            pending.samples.append(makePoint(viewPoint, time: time - pending.startTime, contactRadius: contactRadius))
            let moved = hypot(viewPoint.x - pending.startViewPoint.x, viewPoint.y - pending.startViewPoint.y)
            if moved >= AppConfig.strokeStartDistancePoints {
                pendingTouches[id] = nil
                startStroke(id: id, startTime: pending.startTime, samples: pending.samples)
            } else {
                pendingTouches[id] = pending
            }
            return
        }
        guard let active = activeStrokes[id] else { return }
        let point = makePoint(viewPoint, time: time - active.startTime, contactRadius: contactRadius)
        bitmap.extend(active.session, with: point)
    }

    func endStroke(id: AnyHashable, time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        if let pending = pendingTouches.removeValue(forKey: id) {
            // It never moved far enough to draw: a quick tap leaves a dot, a long rest leaves nothing.
            if time - pending.startTime <= AppConfig.tapMaxDuration {
                startStroke(id: id, startTime: pending.startTime, samples: [pending.samples[0]])
                finishStroke(id: id)
            }
            return
        }
        finishStroke(id: id)
    }

    private func startStroke(id: AnyHashable, startTime: TimeInterval, samples: [StrokePoint]) {
        let brush = pen.brush(pixelsPerPoint: Double(canvasPixelsPerPoint))
        let session = bitmap.beginStroke(brush: brush, start: samples[0])
        for sample in samples.dropFirst() {
            bitmap.extend(session, with: sample)
        }
        activeStrokes[id] = ActiveStroke(session: session, startTime: startTime)
    }

    private func finishStroke(id: AnyHashable) {
        guard let active = activeStrokes.removeValue(forKey: id) else { return }
        commit(bitmap.finish(active.session))
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            beginStroke(id: ObjectIdentifier(touch), atViewPoint: touch.location(in: self),
                        time: touch.timestamp, contactRadius: touch.majorRadius)
        }
        refreshDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            // iOS can report more finger positions than it delivers events; use them all for smoother lines.
            let samples = event?.coalescedTouches(for: touch) ?? [touch]
            for sample in samples {
                extendStroke(id: ObjectIdentifier(touch), toViewPoint: sample.location(in: self),
                             time: sample.timestamp, contactRadius: sample.majorRadius)
            }
        }
        refreshDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            extendStroke(id: id, toViewPoint: touch.location(in: self),
                         time: touch.timestamp, contactRadius: touch.majorRadius)
            endStroke(id: id, time: touch.timestamp)
        }
        refreshDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    // MARK: Whole-canvas operations

    /// An immutable snapshot of the pixels, at canvas resolution (never larger than 2000 x 2000).
    func makeSnapshot() -> CGImage? {
        bitmap.makeSnapshot()
    }

    /// Clears the canvas for a new picture. Undoable: shake, then Undo, brings the old picture back.
    func startNewCanvas() {
        // Fingers still down are cut off, and the ink they already laid down is wiped with everything else.
        let hadStrokesInProgress = !activeStrokes.isEmpty
        pendingTouches.removeAll()
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
        refreshDisplay()
    }

    /// Brings what is on screen up to date: redraws the live layer and, if the committed pixels changed,
    /// the picture itself, both in one transaction so nothing flickers when a chunk moves between them.
    func refreshDisplay() {
        bitmap.updateLive(activeStrokes.values.map { $0.session })
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if bitmap.baseVersion != presentedBaseVersion {
            layer.contents = bitmap.makeImage()
            presentedBaseVersion = bitmap.baseVersion
        }
        liveLayer.contents = activeStrokes.isEmpty ? nil : bitmap.makeLiveImage()
        CATransaction.commit()
    }

    // MARK: Inspection (used by tests)

    func pixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        bitmap.pixel(x: x, y: y)
    }

    func livePixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        bitmap.livePixel(x: x, y: y)
    }
}
