import XCTest
@testable import QoixDraw

final class CanvasSpecTests: XCTestCase {
    func testTheCapIs2000() {
        XCTAssertEqual(CanvasSpec.maxDimension, 2000)
    }

    func testSizesWithinTheCapAreKept() {
        let largest = CanvasSpec(width: 2000, height: 2000)
        XCTAssertEqual(largest.width, 2000)
        XCTAssertEqual(largest.height, 2000)

        let small = CanvasSpec(width: 300, height: 120)
        XCTAssertEqual(small.size, CGSize(width: 300, height: 120))
    }

    func testOversizeIsScaledDownKeepingProportions() {
        let wide = CanvasSpec(width: 4000, height: 3000)
        XCTAssertEqual(wide, CanvasSpec(width: 2000, height: 1500))

        let tall = CanvasSpec(width: 1000, height: 5000)
        XCTAssertEqual(tall.width, 400)
        XCTAssertEqual(tall.height, 2000)

        let huge = CanvasSpec(width: 100_000, height: 100_000)
        XCTAssertEqual(huge.width, 2000)
        XCTAssertEqual(huge.height, 2000)
    }

    func testNeverSmallerThanOnePixel() {
        let tiny = CanvasSpec(width: 0, height: -10)
        XCTAssertEqual(tiny.width, 1)
        XCTAssertEqual(tiny.height, 1)

        let sliver = CanvasSpec(width: 100_000, height: 3)
        XCTAssertEqual(sliver.width, 2000)
        XCTAssertEqual(sliver.height, 1)
    }

    func testFittingAPhoneScreenUsesTheFull2000OnTheLongSide() {
        let portrait = CanvasSpec.fitting(aspectOf: CGSize(width: 393, height: 852))
        XCTAssertEqual(portrait.height, 2000)
        XCTAssertEqual(portrait.width, 923)

        let landscape = CanvasSpec.fitting(aspectOf: CGSize(width: 852, height: 393))
        XCTAssertEqual(landscape.width, 2000)
        XCTAssertEqual(landscape.height, 923)

        XCTAssertEqual(CanvasSpec.fitting(aspectOf: CGSize(width: 50, height: 50)),
                       CanvasSpec(width: 2000, height: 2000))
    }

    func testFittingDegenerateSizesFallsBackToTheLargestSquare() {
        let largestSquare = CanvasSpec(width: 2000, height: 2000)
        XCTAssertEqual(CanvasSpec.fitting(aspectOf: .zero), largestSquare)
        XCTAssertEqual(CanvasSpec.fitting(aspectOf: CGSize(width: CGFloat.infinity, height: 10)), largestSquare)
    }

    func testDecodingAnOversizeCanvasClampsIt() throws {
        let json = Data(#"{"width":5000,"height":100}"#.utf8)
        let spec = try JSONDecoder().decode(CanvasSpec.self, from: json)
        XCTAssertEqual(spec.width, 2000)
        XCTAssertEqual(spec.height, 40)
    }

    func testCodableRoundTrip() throws {
        let original = CanvasSpec(width: 923, height: 2000)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(CanvasSpec.self, from: data), original)
    }
}
