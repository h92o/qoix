import XCTest
@testable import QoixDraw

final class BitmapCanvasTests: XCTestCase {
    private let ink = Brush.round(color: .black, diameter: 6)

    private func makeCanvas(width: Int = 60, height: Int = 40, background: RGBAColor = .white) throws -> BitmapCanvas {
        try XCTUnwrap(BitmapCanvas(spec: CanvasSpec(width: width, height: height), background: background))
    }

    private func assertPixel(_ canvas: BitmapCanvas, _ x: Int, _ y: Int,
                             isDark: Bool, file: StaticString = #filePath, line: UInt = #line) {
        guard let p = canvas.pixel(x: x, y: y) else {
            return XCTFail("pixel (\(x), \(y)) is outside the canvas", file: file, line: line)
        }
        if isDark {
            XCTAssertLessThan(p.r, 60, "pixel (\(x), \(y)) should be inked", file: file, line: line)
        } else {
            XCTAssertGreaterThan(p.r, 195, "pixel (\(x), \(y)) should be blank", file: file, line: line)
        }
    }

    private func tap(_ canvas: BitmapCanvas, at point: CGPoint, brush: Brush) {
        let session = canvas.beginStroke(brush: brush, start: StrokePoint(point))
        _ = canvas.finish(session)
    }

    func testStartsFilledWithTheBackground() throws {
        let canvas = try makeCanvas(width: 20, height: 10)
        for (x, y) in [(0, 0), (19, 9), (10, 5)] {
            let p = try XCTUnwrap(canvas.pixel(x: x, y: y))
            XCTAssertEqual([p.r, p.g, p.b, p.a], [255, 255, 255, 255])
        }
    }

    func testCustomBackgroundColorIsUsed() throws {
        let canvas = try makeCanvas(width: 8, height: 8, background: RGBAColor(red: 1, green: 0, blue: 0))
        let p = try XCTUnwrap(canvas.pixel(x: 4, y: 4))
        XCTAssertEqual([p.r, p.g, p.b, p.a], [255, 0, 0, 255])
    }

    func testPixelOutsideTheCanvasIsNil() throws {
        let canvas = try makeCanvas(width: 10, height: 10)
        XCTAssertNil(canvas.pixel(x: -1, y: 0))
        XCTAssertNil(canvas.pixel(x: 0, y: 10))
        XCTAssertNil(canvas.pixel(x: 10, y: 0))
    }

    func testATapPaintsADot() throws {
        let canvas = try makeCanvas()
        tap(canvas, at: CGPoint(x: 30, y: 20), brush: Brush.round(color: .black, diameter: 10))
        assertPixel(canvas, 30, 20, isDark: true)
        assertPixel(canvas, 33, 20, isDark: true)
        assertPixel(canvas, 40, 20, isDark: false)
        assertPixel(canvas, 30, 30, isDark: false)
    }

    func testAHorizontalStrokeInksTheLineAndNothingElse() throws {
        let canvas = try makeCanvas()
        canvas.paint(Stroke(brush: ink, points: linePoints(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 50, y: 20))))

        for x in stride(from: 10, through: 50, by: 5) {
            assertPixel(canvas, x, 20, isDark: true)
        }
        assertPixel(canvas, 30, 10, isDark: false)
        assertPixel(canvas, 30, 30, isDark: false)
        assertPixel(canvas, 2, 20, isDark: false)
    }

    func testYGrowsDownward() throws {
        let canvas = try makeCanvas()
        tap(canvas, at: CGPoint(x: 30, y: 5), brush: ink)
        assertPixel(canvas, 30, 5, isDark: true)
        assertPixel(canvas, 30, 35, isDark: false)
    }

    func testPaintingOutsideTheCanvasIsHarmless() throws {
        let canvas = try makeCanvas()
        canvas.paint(Stroke(brush: ink, points: linePoints(from: CGPoint(x: -50, y: -50), to: CGPoint(x: -40, y: -30))))
        canvas.paint(Stroke(brush: ink, points: linePoints(from: CGPoint(x: 500, y: 500), to: CGPoint(x: 600, y: 650))))
        assertPixel(canvas, 0, 39, isDark: false)
    }

    func testPaintingBackInTheBackgroundColorErases() throws {
        let canvas = try makeCanvas()
        tap(canvas, at: CGPoint(x: 30, y: 20), brush: Brush.round(color: .black, diameter: 12))
        assertPixel(canvas, 30, 20, isDark: true)
        tap(canvas, at: CGPoint(x: 30, y: 20), brush: Brush.round(color: .white, diameter: 20))
        assertPixel(canvas, 30, 20, isDark: false)
    }

    func testRepaintDropsStrokesThatWereRemoved() throws {
        let first = Stroke(brush: ink, points: linePoints(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 20, y: 10)))
        let second = Stroke(brush: ink, points: linePoints(from: CGPoint(x: 10, y: 30), to: CGPoint(x: 20, y: 30)))
        let canvas = try makeCanvas()

        canvas.repaint([first, second])
        assertPixel(canvas, 15, 10, isDark: true)
        assertPixel(canvas, 15, 30, isDark: true)

        canvas.repaint([first])
        assertPixel(canvas, 15, 10, isDark: true)
        assertPixel(canvas, 15, 30, isDark: false)

        canvas.repaint([])
        assertPixel(canvas, 15, 10, isDark: false)
    }

    func testSnapshotImageHasTheCanvasSize() throws {
        let canvas = try makeCanvas(width: 123, height: 45)
        let image = try XCTUnwrap(canvas.makeImage())
        XCTAssertEqual(image.width, 123)
        XCTAssertEqual(image.height, 45)
    }

    func testSnapshotIsNotAffectedByLaterPainting() throws {
        let canvas = try makeCanvas()
        let image = try XCTUnwrap(canvas.makeImage())
        tap(canvas, at: CGPoint(x: 30, y: 20), brush: Brush.round(color: .black, diameter: 20))

        let data = try XCTUnwrap(image.dataProvider?.data)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        let offset = 20 * image.bytesPerRow + 30 * 4
        XCTAssertEqual(bytes[offset], 255, "the earlier snapshot should still be blank")
        assertPixel(canvas, 30, 20, isDark: true)
    }

    func testTheLargestCanvasCanBeCreatedAndPainted() throws {
        let canvas = try makeCanvas(width: 2000, height: 2000)
        tap(canvas, at: CGPoint(x: 1000, y: 1000), brush: Brush.round(color: .black, diameter: 30))
        assertPixel(canvas, 1000, 1000, isDark: true)
        assertPixel(canvas, 1999, 1999, isDark: false)
        XCTAssertEqual(canvas.makeImage()?.width, 2000)
        XCTAssertEqual(canvas.makeImage()?.height, 2000)
    }

    // MARK: Live layer

    func testTheLiveLayerShowsAStrokeInProgressAndTheCommittedLayerDoesNot() throws {
        let canvas = try makeCanvas(width: 200, height: 100)
        let session = canvas.beginStroke(brush: Brush.round(color: .black, diameter: 10), start: StrokePoint(x: 20, y: 50))
        canvas.extend(session, with: StrokePoint(x: 60, y: 50, time: 0.1))
        canvas.updateLive([session])

        XCTAssertGreaterThan(try XCTUnwrap(canvas.livePixel(x: 40, y: 50)).a, 200, "the stroke so far is in the live layer")
        assertPixel(canvas, 40, 50, isDark: false)

        _ = canvas.finish(session)
        canvas.updateLive([])
        XCTAssertEqual(try XCTUnwrap(canvas.livePixel(x: 40, y: 50)).a, 0, "the live layer is empty once the stroke is done")
        assertPixel(canvas, 40, 50, isDark: true)
    }

    func testTheLiveLayerCoversOnlyTheStrokeInProgressNotTheWholeCanvas() throws {
        let canvas = try makeCanvas(width: 2000, height: 2000)
        XCTAssertTrue(canvas.liveRect.isNull, "nothing is being drawn yet")
        XCTAssertNil(canvas.makeLiveImage())

        let session = canvas.beginStroke(brush: Brush.round(color: .black, diameter: 10), start: StrokePoint(x: 1000, y: 1000))
        canvas.extend(session, with: StrokePoint(x: 1030, y: 1000, time: 0.05))
        canvas.updateLive([session])

        let rect = canvas.liveRect
        XCTAssertFalse(rect.isNull)
        XCTAssertLessThan(rect.width, 150, "the live layer is a small patch: \(rect)")
        XCTAssertLessThan(rect.height, 60, "the live layer is a small patch: \(rect)")
        XCTAssertTrue(rect.contains(CGPoint(x: 1015, y: 1000)))
        XCTAssertEqual(rect.minX, rect.minX.rounded(), "it sits on whole canvas pixels")
        XCTAssertEqual(rect.minY, rect.minY.rounded(), "it sits on whole canvas pixels")
        XCTAssertEqual(try XCTUnwrap(canvas.livePixel(x: 1010, y: 1000)).a, 255)
        XCTAssertEqual(try XCTUnwrap(canvas.livePixel(x: 100, y: 100)).a, 0, "far from the stroke it is transparent")
        XCTAssertNil(canvas.livePixel(x: 2000, y: 0), "outside the canvas there is nothing")
        let image = try XCTUnwrap(canvas.makeLiveImage())
        XCTAssertEqual(image.width, Int(rect.width))
        XCTAssertEqual(image.height, Int(rect.height))
    }

    func testTheLiveLayerIsClippedToTheCanvas() throws {
        let canvas = try makeCanvas(width: 100, height: 100)
        let session = canvas.beginStroke(brush: Brush.round(color: .black, diameter: 10), start: StrokePoint(x: 2, y: 2))
        canvas.extend(session, with: StrokePoint(x: 30, y: 2, time: 0.05))
        canvas.updateLive([session])

        XCTAssertEqual(canvas.liveRect.minX, 0)
        XCTAssertEqual(canvas.liveRect.minY, 0)
        XCTAssertGreaterThan(try XCTUnwrap(canvas.livePixel(x: 10, y: 2)).a, 200)
    }

    func testAStrokeEntirelyOffTheCanvasLeavesNoLiveLayer() throws {
        let canvas = try makeCanvas(width: 100, height: 100)
        let session = canvas.beginStroke(brush: Brush.round(color: .black, diameter: 10), start: StrokePoint(x: -500, y: -500))
        canvas.extend(session, with: StrokePoint(x: -450, y: -450, time: 0.05))
        canvas.updateLive([session])

        XCTAssertTrue(canvas.liveRect.isNull)
        XCTAssertNil(canvas.makeLiveImage())
        XCTAssertEqual(try XCTUnwrap(canvas.livePixel(x: 5, y: 5)).a, 0)
    }

    func testClearingEmptiesTheLiveLayer() throws {
        let canvas = try makeCanvas(width: 200, height: 100)
        let session = canvas.beginStroke(brush: Brush.round(color: .black, diameter: 10), start: StrokePoint(x: 20, y: 50))
        canvas.extend(session, with: StrokePoint(x: 60, y: 50, time: 0.1))
        canvas.updateLive([session])
        XCTAssertFalse(canvas.liveRect.isNull)

        canvas.clear()
        XCTAssertTrue(canvas.liveRect.isNull)
        XCTAssertEqual(try XCTUnwrap(canvas.livePixel(x: 40, y: 50)).a, 0)
    }

    func testTwoStrokesInProgressShareOneLiveLayer() throws {
        let canvas = try makeCanvas(width: 300, height: 100)
        let brush = Brush.round(color: .black, diameter: 10)
        let first = canvas.beginStroke(brush: brush, start: StrokePoint(x: 20, y: 30))
        let second = canvas.beginStroke(brush: brush, start: StrokePoint(x: 20, y: 70))
        canvas.extend(first, with: StrokePoint(x: 60, y: 30, time: 0.1))
        canvas.extend(second, with: StrokePoint(x: 60, y: 70, time: 0.1))
        canvas.updateLive([first, second])

        XCTAssertGreaterThan(try XCTUnwrap(canvas.livePixel(x: 40, y: 30)).a, 200)
        XCTAssertGreaterThan(try XCTUnwrap(canvas.livePixel(x: 40, y: 70)).a, 200)
        XCTAssertEqual(try XCTUnwrap(canvas.livePixel(x: 40, y: 50)).a, 0, "nothing between them")
    }

    func testFinishedChunksOfALongStrokeAreCommittedWhileItIsStillBeingDrawn() throws {
        let canvas = try makeCanvas(width: 400, height: 100)
        let session = canvas.beginStroke(brush: Brush.round(color: .black, diameter: 8), start: StrokePoint(x: 10, y: 50))
        let before = canvas.baseVersion
        for point in linePoints(from: CGPoint(x: 10, y: 50), to: CGPoint(x: 380, y: 50)).dropFirst() {
            canvas.extend(session, with: point)
        }
        XCTAssertGreaterThan(canvas.baseVersion, before, "complete chunks are committed as the stroke grows")
        assertPixel(canvas, 40, 50, isDark: true)
    }

    func testTheSnapshotIncludesAStrokeStillInProgress() throws {
        let canvas = try makeCanvas(width: 200, height: 100)
        let session = canvas.beginStroke(brush: Brush.round(color: .black, diameter: 10), start: StrokePoint(x: 20, y: 50))
        canvas.extend(session, with: StrokePoint(x: 60, y: 50, time: 0.1))
        canvas.updateLive([session])

        let snapshot = try XCTUnwrap(canvas.makeSnapshot())
        let data = try XCTUnwrap(snapshot.dataProvider?.data)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        XCTAssertLessThan(bytes[50 * snapshot.bytesPerRow + 40 * 4], 80, "the saved picture shows the unfinished stroke")
    }
}
