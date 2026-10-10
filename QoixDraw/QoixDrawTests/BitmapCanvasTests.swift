import XCTest
@testable import QoixDraw

final class BitmapCanvasTests: XCTestCase {
    private let ink = Brush(color: .black, width: 6)

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
        let painter = canvas.beginStroke(brush: Brush(color: .black, width: 10), at: CGPoint(x: 30, y: 20))
        painter.finish()
        assertPixel(canvas, 30, 20, isDark: true)
        assertPixel(canvas, 33, 20, isDark: true)
        assertPixel(canvas, 40, 20, isDark: false)
        assertPixel(canvas, 30, 30, isDark: false)
    }

    func testAHorizontalStrokeInksTheLineAndNothingElse() throws {
        let canvas = try makeCanvas()
        let painter = canvas.beginStroke(brush: ink, at: CGPoint(x: 10, y: 20))
        painter.extend(to: CGPoint(x: 30, y: 20))
        painter.extend(to: CGPoint(x: 50, y: 20))
        painter.finish()

        for x in stride(from: 10, through: 50, by: 5) {
            assertPixel(canvas, x, 20, isDark: true)
        }
        assertPixel(canvas, 30, 10, isDark: false)
        assertPixel(canvas, 30, 30, isDark: false)
        assertPixel(canvas, 2, 20, isDark: false)
    }

    func testYGrowsDownward() throws {
        let canvas = try makeCanvas()
        let painter = canvas.beginStroke(brush: Brush(color: .black, width: 6), at: CGPoint(x: 30, y: 5))
        painter.finish()
        assertPixel(canvas, 30, 5, isDark: true)
        assertPixel(canvas, 30, 35, isDark: false)
    }

    func testPaintingOutsideTheCanvasIsHarmless() throws {
        let canvas = try makeCanvas()
        let painter = canvas.beginStroke(brush: ink, at: CGPoint(x: -50, y: -50))
        painter.extend(to: CGPoint(x: -40, y: -30))
        painter.extend(to: CGPoint(x: 500, y: 500))
        painter.finish()
        assertPixel(canvas, 0, 39, isDark: false)
    }

    func testJitterBelowTheMinimumStepIsIgnored() throws {
        let canvas = try makeCanvas()
        let painter = canvas.beginStroke(brush: ink, at: CGPoint(x: 10, y: 10))
        XCTAssertFalse(painter.extend(to: CGPoint(x: 10.1, y: 10.1)))
        XCTAssertTrue(painter.extend(to: CGPoint(x: 20, y: 10)))
    }

    func testPaintingBackInTheBackgroundColorErases() throws {
        let canvas = try makeCanvas()
        canvas.beginStroke(brush: Brush(color: .black, width: 12), at: CGPoint(x: 30, y: 20)).finish()
        assertPixel(canvas, 30, 20, isDark: true)
        canvas.beginStroke(brush: Brush(color: .white, width: 20), at: CGPoint(x: 30, y: 20)).finish()
        assertPixel(canvas, 30, 20, isDark: false)
    }

    func testReplayIsPixelIdenticalToLiveDrawing() throws {
        let points = [CGPoint(x: 5, y: 5), CGPoint(x: 15, y: 30), CGPoint(x: 30, y: 8),
                      CGPoint(x: 31, y: 8.1), CGPoint(x: 45, y: 33), CGPoint(x: 55, y: 12)]

        let live = try makeCanvas()
        let painter = live.beginStroke(brush: ink, at: points[0])
        var accepted = [points[0]]
        for point in points.dropFirst() where painter.extend(to: point) {
            accepted.append(point)
        }
        painter.finish()

        let replayed = try makeCanvas()
        replayed.paint(Stroke(brush: ink, points: accepted))

        XCTAssertEqual(try XCTUnwrap(live.rawBytes()), try XCTUnwrap(replayed.rawBytes()))
    }

    func testRepaintDropsStrokesThatWereRemoved() throws {
        let first = Stroke(brush: ink, points: [CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 10)])
        let second = Stroke(brush: ink, points: [CGPoint(x: 10, y: 30), CGPoint(x: 20, y: 30)])
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
        canvas.beginStroke(brush: Brush(color: .black, width: 20), at: CGPoint(x: 30, y: 20)).finish()

        let data = try XCTUnwrap(image.dataProvider?.data)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        let offset = 20 * image.bytesPerRow + 30 * 4
        XCTAssertEqual(bytes[offset], 255, "the earlier snapshot should still be blank")
        assertPixel(canvas, 30, 20, isDark: true)
    }

    func testTheLargestCanvasCanBeCreatedAndPainted() throws {
        let canvas = try makeCanvas(width: 2000, height: 2000)
        canvas.beginStroke(brush: Brush(color: .black, width: 30), at: CGPoint(x: 1000, y: 1000)).finish()
        assertPixel(canvas, 1000, 1000, isDark: true)
        assertPixel(canvas, 1999, 1999, isDark: false)
        XCTAssertEqual(canvas.makeImage()?.width, 2000)
        XCTAssertEqual(canvas.makeImage()?.height, 2000)
    }
}
