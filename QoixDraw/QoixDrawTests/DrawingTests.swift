import XCTest
@testable import QoixDraw

final class DrawingTests: XCTestCase {
    private func stroke(_ x: Double) -> Stroke {
        Stroke(brush: Brush.round(color: .black, diameter: 4),
               points: [StrokePoint(x: x, y: 0), StrokePoint(x: x, y: 10, time: 0.02)])
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
        let nib = Nib(shape: .rectangle, length: 21.5, thickness: 2.5, angleDegrees: 45)
        let dynamics = Dynamics(speedResponse: 0.8, minScale: 0.2, referenceSpeed: 900, contactResponse: 0.5,
                                taperIn: 30, startScale: 0.3, taperOut: 60, endScale: 0.05)
        drawing.append(Stroke(brush: Brush(color: RGBAColor(red: 1, green: 0, blue: 0, alpha: 0.5), nib: nib, dynamics: dynamics),
                              points: [StrokePoint(x: 1.5, y: 2.5, time: 0, radius: 11), StrokePoint(x: 100, y: 200, time: 0.5, radius: 14)]))

        let data = try JSONEncoder().encode(drawing)
        let decoded = try JSONDecoder().decode(Drawing.self, from: data)
        XCTAssertEqual(decoded, drawing)
    }
}
