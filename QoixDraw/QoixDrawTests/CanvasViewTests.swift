import XCTest
@testable import QoixDraw

@MainActor
final class CanvasViewTests: XCTestCase {
    /// A 200 x 400 px canvas shown in a 100 x 200 pt view: two canvas pixels per point. The pen is a plain 4 pt
    /// marker (8 canvas pixels wide) unless a test asks for another, so where the ink lands is easy to predict.
    private func makeView(preset: BrushPreset = .marker) throws -> CanvasView {
        let pen = PenSettings(defaults: nil, preset: preset)
        let view = try XCTUnwrap(CanvasView(canvas: CanvasSpec(width: 200, height: 400), pen: pen))
        view.frame = CGRect(x: 0, y: 0, width: 100, height: 200)
        return view
    }

    private func drawLine(_ view: CanvasView, id: AnyHashable = 1, from: CGPoint, to: CGPoint, duration: TimeInterval = 0.1) {
        view.beginStroke(id: id, atViewPoint: from, time: 0)
        view.extendStroke(id: id, toViewPoint: to, time: duration)
        view.endStroke(id: id, time: duration)
    }

    private func isInked(_ view: CanvasView, _ x: Int, _ y: Int) throws -> Bool {
        let pixel = try XCTUnwrap(view.pixel(x: x, y: y), "pixel (\(x), \(y)) is outside the canvas")
        return pixel.r < 100
    }

    // MARK: Geometry

    func testViewPointsMapToCanvasPixels() throws {
        let view = try makeView()
        XCTAssertEqual(view.canvasPoint(forViewPoint: CGPoint(x: 50, y: 100)), CGPoint(x: 100, y: 200))
        XCTAssertEqual(view.canvasPoint(forViewPoint: .zero), .zero)
        XCTAssertEqual(view.canvasPoint(forViewPoint: CGPoint(x: 100, y: 200)), CGPoint(x: 200, y: 400))
    }

    func testTheCanvasIsCenteredWhenTheViewHasADifferentShape() throws {
        let view = try XCTUnwrap(CanvasView(canvas: CanvasSpec(width: 100, height: 100)))
        view.frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        XCTAssertEqual(view.canvasFrame, CGRect(x: 50, y: 0, width: 100, height: 100))
        XCTAssertEqual(view.canvasPoint(forViewPoint: CGPoint(x: 50, y: 0)), .zero)
        XCTAssertEqual(view.canvasPoint(forViewPoint: CGPoint(x: 100, y: 50)), CGPoint(x: 50, y: 50))
    }

    // MARK: Drawing

    func testDrawingAStrokeInksThePixelsAndRecordsIt() throws {
        let view = try makeView()
        drawLine(view, from: CGPoint(x: 25, y: 100), to: CGPoint(x: 75, y: 100))

        XCTAssertEqual(view.drawing.strokes.count, 1)
        XCTAssertEqual(view.drawing.strokes[0].points.first?.cgPoint, CGPoint(x: 50, y: 200))
        XCTAssertEqual(view.drawing.strokes[0].points.last?.cgPoint, CGPoint(x: 150, y: 200))
        XCTAssertTrue(try isInked(view, 100, 200))
        XCTAssertTrue(try isInked(view, 100, 203), "a 4 pt pen is 8 canvas pixels wide")
        XCTAssertFalse(try isInked(view, 100, 207))
        XCTAssertFalse(try isInked(view, 100, 100))
    }

    func testPenSizeIsConvertedFromPointsToCanvasPixels() throws {
        let view = try makeView()
        view.pen.preset.lengthPoints = 5
        view.pen.preset.thicknessPoints = 5
        drawLine(view, from: CGPoint(x: 25, y: 100), to: CGPoint(x: 75, y: 100))

        let nib = view.drawing.strokes[0].brush.nib
        XCTAssertEqual(nib.length, 10, accuracy: 0.0001)
        XCTAssertEqual(nib.thickness, 10, accuracy: 0.0001)
    }

    func testTheFingerTimingAndContactAreRecordedWithTheStroke() throws {
        let view = try makeView()
        view.beginStroke(id: 1, atViewPoint: CGPoint(x: 25, y: 100), time: 10, contactRadius: 4)
        view.extendStroke(id: 1, toViewPoint: CGPoint(x: 75, y: 100), time: 10.25, contactRadius: 6)
        view.endStroke(id: 1, time: 10.25)

        let points = view.drawing.strokes[0].points
        XCTAssertEqual(points.first?.time ?? -1, 0, accuracy: 1e-9, "times count from the start of the stroke")
        XCTAssertEqual(points.last?.time ?? -1, 0.25, accuracy: 1e-9)
        XCTAssertEqual(points.first?.radius ?? -1, 8, accuracy: 1e-9, "contact radius is in canvas pixels")
        XCTAssertEqual(points.last?.radius ?? -1, 12, accuracy: 1e-9)
    }

    func testEachStrokeIsDrawnInTheInkThatWasChosenWhenItStarted() throws {
        let view = try makeView()
        drawLine(view, from: CGPoint(x: 10, y: 50), to: CGPoint(x: 90, y: 50))
        view.pen.cycleColor() // Vermilion
        drawLine(view, from: CGPoint(x: 10, y: 150), to: CGPoint(x: 90, y: 150))

        XCTAssertEqual(view.drawing.strokes[0].brush.color, Palette.colors[0].color)
        XCTAssertEqual(view.drawing.strokes[1].brush.color, Palette.colors[1].color)
        let red = try XCTUnwrap(view.pixel(x: 100, y: 300))
        XCTAssertGreaterThan(red.r, 150)
        XCTAssertLessThan(red.g, 100)
        let dark = try XCTUnwrap(view.pixel(x: 100, y: 100))
        XCTAssertLessThan(dark.r, 60)
    }

    func testChangingTheInkMidStrokeDoesNotRecolorTheStrokeInProgress() throws {
        let view = try makeView()
        view.beginStroke(id: 1, atViewPoint: CGPoint(x: 10, y: 100), time: 0)
        view.extendStroke(id: 1, toViewPoint: CGPoint(x: 40, y: 100), time: 0.1)
        view.pen.cycleColor()
        view.extendStroke(id: 1, toViewPoint: CGPoint(x: 90, y: 100), time: 0.2)
        view.endStroke(id: 1, time: 0.2)

        XCTAssertEqual(view.drawing.strokes[0].brush.color, Palette.colors[0].color)
        XCTAssertTrue(try isInked(view, 150, 200), "still the first ink at the far end")
    }

    func testATapMakesADot() throws {
        let view = try makeView()
        view.beginStroke(id: 1, atViewPoint: CGPoint(x: 50, y: 100), time: 0)
        view.endStroke(id: 1, time: 0.1)
        XCTAssertEqual(view.drawing.strokes.count, 1)
        XCTAssertTrue(try isInked(view, 100, 200))
        XCTAssertFalse(try isInked(view, 100, 210))
    }

    func testATapWithATinyWobbleStillMakesADotWhereItLanded() throws {
        let view = try makeView()
        view.beginStroke(id: 1, atViewPoint: CGPoint(x: 50, y: 100), time: 0)
        view.extendStroke(id: 1, toViewPoint: CGPoint(x: 51, y: 100.5), time: 0.05)
        view.endStroke(id: 1, time: 0.1)
        XCTAssertEqual(view.drawing.strokes.count, 1)
        XCTAssertEqual(view.drawing.strokes[0].points.map(\.cgPoint), [CGPoint(x: 100, y: 200)])
    }

    func testAFingerThatJustRestsOnTheScreenDrawsNothing() throws {
        let view = try makeView()
        view.beginStroke(id: 1, atViewPoint: CGPoint(x: 50, y: 100), time: 0)
        view.extendStroke(id: 1, toViewPoint: CGPoint(x: 51, y: 100.5), time: 0.5)
        view.endStroke(id: 1, time: 2)

        XCTAssertTrue(view.drawing.isEmpty)
        XCTAssertFalse(view.history.canUndo)
        XCTAssertFalse(try isInked(view, 100, 200))
    }

    func testAStrokeStartsOnceTheFingerHasMovedFarEnough() throws {
        let view = try makeView()
        view.beginStroke(id: 1, atViewPoint: CGPoint(x: 20, y: 100), time: 0)
        view.extendStroke(id: 1, toViewPoint: CGPoint(x: 22, y: 100), time: 0.02)
        view.refreshDisplay()
        XCTAssertEqual(try XCTUnwrap(view.livePixel(x: 42, y: 200)).a, 0, "2 pt is not far enough to start a stroke")

        view.extendStroke(id: 1, toViewPoint: CGPoint(x: 30, y: 100), time: 0.06)
        view.refreshDisplay()
        XCTAssertGreaterThan(try XCTUnwrap(view.livePixel(x: 50, y: 200)).a, 200, "now it's drawing, in the live layer")
        XCTAssertFalse(try isInked(view, 50, 200), "and not yet in the committed picture")

        view.endStroke(id: 1, time: 0.06)
        view.refreshDisplay()
        XCTAssertTrue(try isInked(view, 50, 200))
        XCTAssertEqual(try XCTUnwrap(view.livePixel(x: 50, y: 200)).a, 0, "the live layer is emptied when the stroke ends")
    }

    func testSeveralFingersCanDrawIndependentStrokesWhenAllowed() throws {
        let view = try makeView()
        view.maximumSimultaneousStrokes = 2
        view.beginStroke(id: 1, atViewPoint: CGPoint(x: 10, y: 20), time: 0)
        view.beginStroke(id: 2, atViewPoint: CGPoint(x: 10, y: 150), time: 0)
        view.extendStroke(id: 1, toViewPoint: CGPoint(x: 60, y: 20), time: 0.1)
        view.extendStroke(id: 2, toViewPoint: CGPoint(x: 60, y: 150), time: 0.1)
        view.endStroke(id: 2, time: 0.1)
        view.endStroke(id: 1, time: 0.1)

        XCTAssertEqual(view.drawing.strokes.count, 2)
        XCTAssertTrue(try isInked(view, 70, 40))
        XCTAssertTrue(try isInked(view, 70, 300))
    }

    func testOnlyOneFingerWritesAtATimeByDefault() throws {
        let view = try makeView()
        XCTAssertEqual(view.maximumSimultaneousStrokes, 1)

        view.beginStroke(id: 1, atViewPoint: CGPoint(x: 10, y: 20), time: 0)
        view.extendStroke(id: 1, toViewPoint: CGPoint(x: 60, y: 20), time: 0.1) // finger 1 is now writing
        view.beginStroke(id: 2, atViewPoint: CGPoint(x: 10, y: 150), time: 0.1) // a knuckle lands
        view.extendStroke(id: 2, toViewPoint: CGPoint(x: 60, y: 150), time: 0.2)
        view.endStroke(id: 2, time: 0.2)
        view.endStroke(id: 1, time: 0.2)

        XCTAssertEqual(view.drawing.strokes.count, 1)
        XCTAssertTrue(try isInked(view, 70, 40))
        XCTAssertFalse(try isInked(view, 70, 300), "the second finger leaves no mark")
    }

    func testAFingerThatLandedWhileAnotherWasWritingStaysIgnoredEvenAfterTheWriterLifts() throws {
        let view = try makeView()
        view.beginStroke(id: 1, atViewPoint: CGPoint(x: 10, y: 20), time: 0)
        view.extendStroke(id: 1, toViewPoint: CGPoint(x: 60, y: 20), time: 0.1)
        view.beginStroke(id: 2, atViewPoint: CGPoint(x: 10, y: 150), time: 0.1)
        view.endStroke(id: 1, time: 0.2)

        view.extendStroke(id: 2, toViewPoint: CGPoint(x: 60, y: 150), time: 0.3)
        view.endStroke(id: 2, time: 0.3)

        XCTAssertEqual(view.drawing.strokes.count, 1, "it was never allowed to draw, so it doesn't start late")
        XCTAssertFalse(try isInked(view, 70, 300))
    }

    func testARestingThumbDoesNotStopTheFingerThatWritesNextToIt() throws {
        let view = try makeView()
        view.beginStroke(id: 1, atViewPoint: CGPoint(x: 90, y: 190), time: 0) // thumb holding the phone
        view.beginStroke(id: 2, atViewPoint: CGPoint(x: 10, y: 100), time: 0.5)
        view.extendStroke(id: 2, toViewPoint: CGPoint(x: 60, y: 100), time: 0.6)
        view.endStroke(id: 2, time: 0.6)
        view.endStroke(id: 1, time: 2)

        XCTAssertEqual(view.drawing.strokes.count, 1)
        XCTAssertTrue(try isInked(view, 70, 200))
        XCTAssertFalse(try isInked(view, 180, 380), "the thumb left no mark")
    }

    func testTheWriterCanDrawAgainAfterIgnoringAnotherFinger() throws {
        let view = try makeView()
        view.beginStroke(id: 1, atViewPoint: CGPoint(x: 10, y: 20), time: 0)
        view.extendStroke(id: 1, toViewPoint: CGPoint(x: 60, y: 20), time: 0.1)
        view.beginStroke(id: 2, atViewPoint: CGPoint(x: 10, y: 150), time: 0.1)
        view.endStroke(id: 1, time: 0.2)
        view.endStroke(id: 2, time: 0.3)

        drawLine(view, id: 3, from: CGPoint(x: 10, y: 100), to: CGPoint(x: 90, y: 100))
        XCTAssertEqual(view.drawing.strokes.count, 2)
    }

    func testTheLiveLayerIsAPatchOverTheStrokeInProgress() throws {
        let view = try makeView()
        let live = try XCTUnwrap(view.layer.sublayers?.first)
        XCTAssertTrue(live.isHidden, "nothing is being drawn")

        view.beginStroke(id: 1, atViewPoint: CGPoint(x: 20, y: 100), time: 0)
        view.extendStroke(id: 1, toViewPoint: CGPoint(x: 60, y: 100), time: 0.1)
        view.refreshDisplay()
        XCTAssertFalse(live.isHidden)
        XCTAssertNotNil(live.contents)
        XCTAssertTrue(live.frame.contains(CGPoint(x: 38, y: 100)), "it sits over the new ink: \(live.frame)")
        XCTAssertLessThan(live.frame.width, 60, "and only over it: \(live.frame)")
        XCTAssertLessThan(live.frame.height, 30)

        view.endStroke(id: 1, time: 0.1)
        view.refreshDisplay()
        XCTAssertTrue(live.isHidden)
        XCTAssertNil(live.contents)
    }

    func testExtendingOrEndingAStrokeThatNeverStartedIsHarmless() throws {
        let view = try makeView()
        view.extendStroke(id: 9, toViewPoint: CGPoint(x: 5, y: 5), time: 0.1)
        view.endStroke(id: 9, time: 0.2)
        XCTAssertTrue(view.drawing.isEmpty)
    }

    func testTheSnapshotIncludesAStrokeStillBeingDrawn() throws {
        let view = try makeView()
        view.beginStroke(id: 1, atViewPoint: CGPoint(x: 20, y: 100), time: 0)
        view.extendStroke(id: 1, toViewPoint: CGPoint(x: 60, y: 100), time: 0.1)
        view.refreshDisplay()
        XCTAssertTrue(view.drawing.isEmpty, "the stroke isn't finished")

        let snapshot = try XCTUnwrap(view.makeSnapshot())
        let bytes = try XCTUnwrap(pixelBytes(of: snapshot))
        XCTAssertLessThan(bytes[200 * snapshot.bytesPerRow + 80 * 4], 80, "Volume Down mid-stroke still saves the stroke")
    }

    // MARK: Undo and redo

    func testUndoAndRedoWalkThroughTheStrokes() throws {
        let view = try makeView()
        drawLine(view, from: CGPoint(x: 10, y: 50), to: CGPoint(x: 90, y: 50))
        drawLine(view, from: CGPoint(x: 10, y: 150), to: CGPoint(x: 90, y: 150))
        XCTAssertEqual(view.drawing.strokes.count, 2)

        view.history.undo()
        XCTAssertEqual(view.drawing.strokes.count, 1)
        XCTAssertTrue(try isInked(view, 100, 100))
        XCTAssertFalse(try isInked(view, 100, 300), "the undone stroke must leave the pixels too")

        view.history.undo()
        XCTAssertTrue(view.drawing.isEmpty)
        XCTAssertFalse(try isInked(view, 100, 100))

        view.history.redo()
        view.history.redo()
        XCTAssertEqual(view.drawing.strokes.count, 2)
        XCTAssertTrue(try isInked(view, 100, 100))
        XCTAssertTrue(try isInked(view, 100, 300))
    }

    func testDrawingAfterAnUndoDiscardsTheRedoHistory() throws {
        let view = try makeView()
        drawLine(view, from: CGPoint(x: 10, y: 50), to: CGPoint(x: 90, y: 50))
        view.history.undo()
        XCTAssertTrue(view.history.canRedo)

        drawLine(view, from: CGPoint(x: 10, y: 150), to: CGPoint(x: 90, y: 150))
        XCTAssertFalse(view.history.canRedo)
        XCTAssertEqual(view.drawing.strokes.count, 1)
    }

    /// Undo repaints the picture from the saved points. That must give back exactly the pixels that were drawn
    /// live, or strokes would shift a little every time something was undone.
    func testUndoRepaintsTheRemainingStrokesExactlyAsTheyWereDrawn() throws {
        let view = try makeView(preset: .chisel45)
        view.beginStroke(id: 1, atViewPoint: CGPoint(x: 10, y: 100), time: 0)
        for index in 1...120 {
            let x = 10 + Double(index) * 0.7
            let y = 100 + 30 * sin(Double(index) / 12)
            view.extendStroke(id: 1, toViewPoint: CGPoint(x: x, y: y), time: Double(index) * 0.008)
            view.refreshDisplay()
        }
        view.endStroke(id: 1, time: 1)
        view.refreshDisplay()
        XCTAssertEqual(view.drawing.strokes.count, 1)
        let before = try XCTUnwrap(pixelBytes(of: try XCTUnwrap(view.makeSnapshot())))

        drawLine(view, from: CGPoint(x: 10, y: 20), to: CGPoint(x: 90, y: 60))
        let during = try XCTUnwrap(pixelBytes(of: try XCTUnwrap(view.makeSnapshot())))
        XCTAssertNotEqual(during, before, "the second stroke changed the picture")

        view.history.undo()
        let after = try XCTUnwrap(pixelBytes(of: try XCTUnwrap(view.makeSnapshot())))
        XCTAssertTrue(after == before, "undo must restore the picture to the exact pixels it had")
    }

    // MARK: New canvas

    func testNewCanvasClearsEverythingAndCanBeUndone() throws {
        let view = try makeView()
        drawLine(view, from: CGPoint(x: 10, y: 50), to: CGPoint(x: 90, y: 50))
        drawLine(view, from: CGPoint(x: 10, y: 150), to: CGPoint(x: 90, y: 150))

        view.startNewCanvas()
        XCTAssertTrue(view.drawing.isEmpty)
        XCTAssertFalse(try isInked(view, 100, 100))
        XCTAssertFalse(try isInked(view, 100, 300))

        view.history.undo()
        XCTAssertEqual(view.drawing.strokes.count, 2)
        XCTAssertTrue(try isInked(view, 100, 100))
        XCTAssertTrue(try isInked(view, 100, 300))

        view.history.redo()
        XCTAssertTrue(view.drawing.isEmpty)
        XCTAssertFalse(try isInked(view, 100, 100))
    }

    func testNewCanvasOnABlankCanvasRegistersNothing() throws {
        let view = try makeView()
        view.startNewCanvas()
        XCTAssertFalse(view.history.canUndo)
    }

    func testNewCanvasCutsOffStrokesStillInProgress() throws {
        let view = try makeView()
        view.beginStroke(id: 1, atViewPoint: CGPoint(x: 5, y: 50), time: 0)
        // Long enough that part of the stroke has already been committed to the picture, not just shown live.
        view.extendStroke(id: 1, toViewPoint: CGPoint(x: 90, y: 50), time: 0.2)
        view.refreshDisplay()
        XCTAssertTrue(try isInked(view, 40, 100), "part of the stroke is already in the picture")

        view.startNewCanvas()
        view.extendStroke(id: 1, toViewPoint: CGPoint(x: 90, y: 90), time: 0.3)
        view.endStroke(id: 1, time: 0.3)
        view.refreshDisplay()

        XCTAssertTrue(view.drawing.isEmpty)
        XCTAssertFalse(try isInked(view, 40, 100), "the ink laid down before the cut must be wiped too")
        XCTAssertFalse(try isInked(view, 100, 100))
        XCTAssertEqual(try XCTUnwrap(view.livePixel(x: 100, y: 100)).a, 0)
    }

    // MARK: Snapshot

    func testSnapshotIsAtCanvasResolutionAndNeverOverTheCap() throws {
        let view = try XCTUnwrap(CanvasView(canvas: CanvasSpec(width: 9000, height: 3000)))
        let image = try XCTUnwrap(view.makeSnapshot())
        XCTAssertEqual(image.width, 2000)
        XCTAssertEqual(image.height, 667)
    }
}

/// The controller wired to a fake photo library: the whole "press Volume Down" flow minus the physical button.
@MainActor
final class CanvasViewControllerTests: XCTestCase {
    private func makeController(photos: PhotoSaving, filesFolder: URL) throws -> (CanvasViewController, CanvasView) {
        let saver = DrawingSaver(photos: photos, files: DocumentsSaver(directory: filesFolder))
        let pen = PenSettings(defaults: nil, preset: .marker)
        let controller = CanvasViewController(saver: saver, penSettings: pen)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.layoutIfNeeded()
        let canvas = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? CanvasView }.first)
        return (controller, canvas)
    }

    private func scribble(on canvas: CanvasView) {
        canvas.beginStroke(id: 1, atViewPoint: CGPoint(x: 50, y: 100), time: 0)
        canvas.extendStroke(id: 1, toViewPoint: CGPoint(x: 300, y: 400), time: 0.3)
        canvas.endStroke(id: 1, time: 0.3)
    }

    private func waitUntil(_ description: String, timeout: TimeInterval = 10, _ condition: @escaping () -> Bool) {
        let predicate = NSPredicate { _, _ in condition() }
        wait(for: [expectation(for: predicate, evaluatedWith: nil)], timeout: timeout)
    }

    func testTheCanvasTakesTheShapeOfTheScreenAtTheLargestAllowedSize() throws {
        let (_, canvas) = try makeController(photos: SpyPhotos(), filesFolder: makeTemporaryFolder())
        XCTAssertEqual(canvas.drawing.canvas, CanvasSpec(width: 923, height: 2000))
        XCTAssertLessThanOrEqual(canvas.drawing.canvas.width, 2000)
        XCTAssertLessThanOrEqual(canvas.drawing.canvas.height, 2000)
    }

    func testSavingABlankCanvasSavesNothing() throws {
        let photos = SpyPhotos()
        let (controller, _) = try makeController(photos: photos, filesFolder: makeTemporaryFolder())
        controller.saveDrawing()
        letMainQueueRun()
        XCTAssertTrue(photos.filenames.isEmpty)
    }

    func testSavingStoresAFullSizePNGThenStartsANewCanvas() throws {
        let photos = SpyPhotos()
        let (controller, canvas) = try makeController(photos: photos, filesFolder: makeTemporaryFolder())
        scribble(on: canvas)

        controller.saveDrawing()
        waitUntil("canvas cleared after save") { canvas.drawing.isEmpty }

        XCTAssertEqual(photos.filenames.count, 1)
        let payload = try XCTUnwrap(photos.payloads.first)
        XCTAssertEqual(Array(payload.prefix(8)), pngSignature)
        let size = try pixelSize(ofPNG: payload)
        XCTAssertEqual(size.width, 923)
        XCTAssertEqual(size.height, 2000)

        canvas.history.undo()
        XCTAssertEqual(canvas.drawing.strokes.count, 1, "undo brings the saved drawing back")
    }

    func testPressingTwiceInARowSavesOnce() throws {
        let photos = SpyPhotos()
        let (controller, canvas) = try makeController(photos: photos, filesFolder: makeTemporaryFolder())
        scribble(on: canvas)

        controller.saveDrawing()
        controller.saveDrawing()
        waitUntil("canvas cleared after save") { canvas.drawing.isEmpty }
        letMainQueueRun()
        XCTAssertEqual(photos.filenames.count, 1)
    }

    func testAFailedSaveKeepsTheDrawingOnScreen() throws {
        let photos = SpyPhotos()
        photos.result = .failure(.failed("no space"))
        let unwritable = URL(fileURLWithPath: "/dev/null/qoixdraw")
        let (controller, canvas) = try makeController(photos: photos, filesFolder: unwritable)
        scribble(on: canvas)

        controller.saveDrawing()
        waitUntil("photo library asked") { photos.filenames.count == 1 }
        letMainQueueRun()
        XCTAssertEqual(canvas.drawing.strokes.count, 1, "nothing was saved, so nothing may be cleared")
    }

    // MARK: Ink (Volume Up)

    func testVolumeUpMovesToTheNextInkForTheNextStroke() throws {
        let (controller, canvas) = try makeController(photos: SpyPhotos(), filesFolder: makeTemporaryFolder())
        XCTAssertEqual(controller.penSettings.colorIndex, 0)

        controller.cycleColor()
        XCTAssertEqual(controller.penSettings.colorIndex, 1)
        scribble(on: canvas)
        XCTAssertEqual(canvas.drawing.strokes[0].brush.color, Palette.colors[1].color)
    }

    func testTheInksWrapAroundAfterTheLastOne() throws {
        let (controller, _) = try makeController(photos: SpyPhotos(), filesFolder: makeTemporaryFolder())
        for _ in Palette.colors {
            controller.cycleColor()
        }
        XCTAssertEqual(controller.penSettings.colorIndex, 0)
    }

    func testChangingTheInkLeavesTheDrawingAndItsHistoryAlone() throws {
        let (controller, canvas) = try makeController(photos: SpyPhotos(), filesFolder: makeTemporaryFolder())
        scribble(on: canvas)
        controller.cycleColor()
        controller.cycleColor()

        XCTAssertEqual(canvas.drawing.strokes.count, 1)
        XCTAssertEqual(canvas.drawing.strokes[0].brush.color, Palette.colors[0].color)
        XCTAssertTrue(canvas.history.canUndo)
    }
}

final class ShakeMenuTests: XCTestCase {
    func testABlankCanvasWithNoHistoryOffersOnlyTheBrushSheet() {
        XCTAssertEqual(ShakeMenu.items(canUndo: false, canRedo: false, canClear: false), [.brushSettings])
    }

    func testADrawingOffersUndoClearAndTheBrushSheet() {
        XCTAssertEqual(ShakeMenu.items(canUndo: true, canRedo: false, canClear: true),
                       [.undo, .clearCanvas, .brushSettings])
    }

    func testAfterUndoingEverythingRedoIsOfferedButClearIsNot() {
        XCTAssertEqual(ShakeMenu.items(canUndo: false, canRedo: true, canClear: false), [.redo, .brushSettings])
    }

    func testEverythingAtOnce() {
        XCTAssertEqual(ShakeMenu.items(canUndo: true, canRedo: true, canClear: true),
                       [.undo, .redo, .clearCanvas, .brushSettings])
    }

    func testAfterSavingAndClearingTheOldDrawingCanBeBroughtBack() {
        // Saved -> canvas cleared: nothing to clear, but the clear itself can be undone.
        XCTAssertEqual(ShakeMenu.items(canUndo: true, canRedo: false, canClear: false), [.undo, .brushSettings])
    }

    func testTheBrushSheetIsAlwaysTheLastChoice() {
        for undo in [false, true] {
            for redo in [false, true] {
                for clear in [false, true] {
                    XCTAssertEqual(ShakeMenu.items(canUndo: undo, canRedo: redo, canClear: clear).last, .brushSettings)
                }
            }
        }
    }
}
