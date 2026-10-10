import XCTest
@testable import QoixDraw

final class DrawingTests: XCTestCase {
    private func stroke(_ x: CGFloat) -> Stroke {
        Stroke(brush: Brush(color: .black, width: 4), points: [CGPoint(x: x, y: 0), CGPoint(x: x, y: 10)])
    }

    private func makeDrawing() -> Drawing {
        Drawing(canvas: CanvasSpec(width: 100, height: 200))
    }

    func testStartsEmpty() {
        XCTAssertTrue(makeDrawing().isEmpty)
    }

    func testAppendAndRemoveLast() {
        var drawing = makeDrawing()
        drawing.append(stroke(1))
        drawing.append(stroke(2))
        XCTAssertEqual(drawing.strokes.count, 2)
        XCTAssertFalse(drawing.isEmpty)

        XCTAssertEqual(drawing.removeLastStroke(), stroke(2))
        XCTAssertEqual(drawing.strokes, [stroke(1)])
        XCTAssertEqual(drawing.removeLastStroke(), stroke(1))
        XCTAssertNil(drawing.removeLastStroke())
        XCTAssertTrue(drawing.isEmpty)
    }

    func testRemoveAllReturnsWhatWasThere() {
        var drawing = makeDrawing()
        drawing.append(stroke(1))
        drawing.append(stroke(2))
        XCTAssertEqual(drawing.removeAllStrokes(), [stroke(1), stroke(2)])
        XCTAssertTrue(drawing.isEmpty)
        XCTAssertEqual(drawing.removeAllStrokes(), [])
    }

    func testReplaceStrokes() {
        var drawing = makeDrawing()
        drawing.append(stroke(1))
        drawing.replaceStrokes(with: [stroke(5), stroke(6)])
        XCTAssertEqual(drawing.strokes, [stroke(5), stroke(6)])
    }

    func testCodableRoundTripKeepsEverything() throws {
        var drawing = Drawing(canvas: CanvasSpec(width: 923, height: 2000), background: RGBAColor(red: 0.1, green: 0.2, blue: 0.3))
        drawing.append(stroke(1))
        drawing.append(Stroke(brush: Brush(color: RGBAColor(red: 1, green: 0, blue: 0, alpha: 0.5), width: 9.5),
                              points: [CGPoint(x: 1.5, y: 2.5), CGPoint(x: 100, y: 200)]))

        let data = try JSONEncoder().encode(drawing)
        let decoded = try JSONDecoder().decode(Drawing.self, from: data)
        XCTAssertEqual(decoded, drawing)
    }
}
