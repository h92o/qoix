import XCTest
@testable import QoixDraw

@MainActor
final class CanvasViewTests: XCTestCase {
    /// A 200 x 400 px canvas shown in a 100 x 200 pt view: two canvas pixels per point.
    private func makeView() throws -> CanvasView {
        let view = try XCTUnwrap(CanvasView(canvas: CanvasSpec(width: 200, height: 400)))
        view.frame = CGRect(x: 0, y: 0, width: 100, height: 200)
        return view
    }

    private func drawLine(_ view: CanvasView, id: AnyHashable = 1, from: CGPoint, to: CGPoint) {
        view.beginStroke(id: id, atViewPoint: from)
        view.extendStroke(id: id, toViewPoint: to)
        view.endStroke(id: id)
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
        XCTAssertEqual(view.drawing.strokes[0].points.first, CGPoint(x: 50, y: 200))
        XCTAssertEqual(view.drawing.strokes[0].points.last, CGPoint(x: 150, y: 200))
        XCTAssertTrue(try isInked(view, 100, 200))
        XCTAssertTrue(try isInked(view, 100, 203), "a 4 pt pen is 8 canvas pixels wide")
        XCTAssertFalse(try isInked(view, 100, 207))
        XCTAssertFalse(try isInked(view, 100, 100))
    }

    func testPenWidthIsConvertedFromPointsToCanvasPixels() throws {
        let view = try makeView()
        view.penWidthPoints = 5
        drawLine(view, from: CGPoint(x: 25, y: 100), to: CGPoint(x: 75, y: 100))
        XCTAssertEqual(view.drawing.strokes[0].brush.width, 10, accuracy: 0.0001)
    }

    func testATapMakesADot() throws {
        let view = try makeView()
        view.beginStroke(id: 1, atViewPoint: CGPoint(x: 50, y: 100))
        view.endStroke(id: 1)
        XCTAssertEqual(view.drawing.strokes.count, 1)
        XCTAssertTrue(try isInked(view, 100, 200))
    }

    func testSeveralFingersDrawIndependentStrokes() throws {
        let view = try makeView()
        view.beginStroke(id: 1, atViewPoint: CGPoint(x: 10, y: 20))
        view.beginStroke(id: 2, atViewPoint: CGPoint(x: 10, y: 150))
        view.extendStroke(id: 1, toViewPoint: CGPoint(x: 60, y: 20))
        view.extendStroke(id: 2, toViewPoint: CGPoint(x: 60, y: 150))
        view.endStroke(id: 2)
        view.endStroke(id: 1)

        XCTAssertEqual(view.drawing.strokes.count, 2)
        XCTAssertTrue(try isInked(view, 70, 40))
        XCTAssertTrue(try isInked(view, 70, 300))
    }

    func testExtendingOrEndingAStrokeThatNeverStartedIsHarmless() throws {
        let view = try makeView()
        view.extendStroke(id: 9, toViewPoint: CGPoint(x: 5, y: 5))
        view.endStroke(id: 9)
        XCTAssertTrue(view.drawing.isEmpty)
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
        view.beginStroke(id: 1, atViewPoint: CGPoint(x: 10, y: 50))
        view.startNewCanvas()
        view.extendStroke(id: 1, toViewPoint: CGPoint(x: 90, y: 50))
        view.endStroke(id: 1)

        XCTAssertTrue(view.drawing.isEmpty)
        XCTAssertFalse(try isInked(view, 20, 100), "the dot painted before the cut must be wiped too")
        XCTAssertFalse(try isInked(view, 100, 100))
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
        let controller = CanvasViewController(saver: saver)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.layoutIfNeeded()
        let canvas = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? CanvasView }.first)
        return (controller, canvas)
    }

    private func scribble(on canvas: CanvasView) {
        canvas.beginStroke(id: 1, atViewPoint: CGPoint(x: 50, y: 100))
        canvas.extendStroke(id: 1, toViewPoint: CGPoint(x: 300, y: 400))
        canvas.endStroke(id: 1)
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
}

final class ShakeMenuTests: XCTestCase {
    func testABlankCanvasWithNoHistoryOffersNothing() {
        XCTAssertEqual(ShakeMenu.items(canUndo: false, canRedo: false, canClear: false), [])
    }

    func testADrawingOffersUndoAndClear() {
        XCTAssertEqual(ShakeMenu.items(canUndo: true, canRedo: false, canClear: true), [.undo, .clearCanvas])
    }

    func testAfterUndoingEverythingRedoIsOfferedButClearIsNot() {
        XCTAssertEqual(ShakeMenu.items(canUndo: false, canRedo: true, canClear: false), [.redo])
    }

    func testEverythingAtOnce() {
        XCTAssertEqual(ShakeMenu.items(canUndo: true, canRedo: true, canClear: true), [.undo, .redo, .clearCanvas])
    }

    func testAfterSavingAndClearingTheOldDrawingCanBeBroughtBack() {
        // Saved -> canvas cleared: nothing to clear, but the clear itself can be undone.
        XCTAssertEqual(ShakeMenu.items(canUndo: true, canRedo: false, canClear: false), [.undo])
    }
}
