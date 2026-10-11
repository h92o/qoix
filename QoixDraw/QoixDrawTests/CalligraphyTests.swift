import XCTest
@testable import QoixDraw

// MARK: Hulls and tip shapes

final class ConvexHullTests: XCTestCase {
    private func signedArea(_ polygon: [CGPoint]) -> CGFloat {
        var sum: CGFloat = 0
        for index in polygon.indices {
            let a = polygon[index]
            let b = polygon[(index + 1) % polygon.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    func testTheHullOfASquareWithPointsInsideIsTheSquare() {
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10)]
        let inside = [CGPoint(x: 5, y: 5), CGPoint(x: 2, y: 7), CGPoint(x: 9, y: 1)]
        let hull = ConvexHull.hull(of: corners + inside)

        XCTAssertEqual(hull.count, 4)
        for corner in corners {
            XCTAssertTrue(hull.contains(corner), "missing corner \(corner)")
        }
        XCTAssertEqual(signedArea(hull), 100, accuracy: 0.0001)
    }

    func testHullsAreAlwaysWoundTheSameWayAndContainEveryPoint() {
        var seed: UInt64 = 12345
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(seed >> 11) / CGFloat(1 << 53) * 100
        }
        for _ in 0..<50 {
            let points = (0..<20).map { _ in CGPoint(x: next(), y: next()) }
            let hull = ConvexHull.hull(of: points)
            XCTAssertGreaterThanOrEqual(hull.count, 3)
            XCTAssertGreaterThan(signedArea(hull), 0, "hulls must all be wound the same way")
            for point in points {
                for index in hull.indices {
                    let a = hull[index]
                    let b = hull[(index + 1) % hull.count]
                    let cross = (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x)
                    XCTAssertGreaterThanOrEqual(cross, -0.0001, "a point lies outside the hull")
                }
            }
        }
    }

    func testPointsInALineHaveAtMostTwoCorners() {
        let hull = ConvexHull.hull(of: [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 5), CGPoint(x: 10, y: 10)])
        XCTAssertLessThanOrEqual(hull.count, 2)
    }
}

final class NibGeometryTests: XCTestCase {
    func testAFlatTipAtZeroDegreesIsAHorizontalBar() {
        let geometry = NibGeometry(nib: Nib(shape: .rectangle, length: 20, thickness: 4, angleDegrees: 0))
        let xs = geometry.outline.map { $0.x }
        let ys = geometry.outline.map { $0.y }
        XCTAssertEqual(xs.max() ?? 0, 10, accuracy: 0.0001)
        XCTAssertEqual(xs.min() ?? 0, -10, accuracy: 0.0001)
        XCTAssertEqual(ys.max() ?? 0, 2, accuracy: 0.0001)
        XCTAssertEqual(ys.min() ?? 0, -2, accuracy: 0.0001)
    }

    func testAFlatTipAtFortyFiveDegreesRunsUpAndToTheRightOnScreen() {
        // y grows downward on screen, so "up and to the right" means a negative y.
        let geometry = NibGeometry(nib: Nib(shape: .rectangle, length: 20, thickness: 2, angleDegrees: 45))
        XCTAssertTrue(geometry.outline.contains { $0.x > 5 && $0.y < -5 }, "one end of the edge is up and to the right")
        XCTAssertTrue(geometry.outline.contains { $0.x < -5 && $0.y > 5 }, "the other end is down and to the left")
        XCTAssertFalse(geometry.outline.contains { $0.x > 5 && $0.y > 5 }, "nothing sticks out the other diagonal")
    }

    func testAnOvalTipsPointsLieOnTheEllipse() {
        let geometry = NibGeometry(nib: Nib(shape: .ellipse, length: 20, thickness: 8, angleDegrees: 0))
        XCTAssertEqual(geometry.outline.count, 24)
        for point in geometry.outline {
            let value = (point.x / 10) * (point.x / 10) + (point.y / 4) * (point.y / 4)
            XCTAssertEqual(value, 1, accuracy: 0.001)
        }
    }

    func testATipIsNeverThinnerThanTheMinimum() {
        let geometry = NibGeometry(nib: Nib(shape: .rectangle, length: 20, thickness: 0, angleDegrees: 0))
        let ys = geometry.outline.map { $0.y }
        XCTAssertGreaterThanOrEqual((ys.max() ?? 0) - (ys.min() ?? 0), CGFloat(NibGeometry.minimumExtent) - 0.000001)
    }

    func testScalingShrinksTheTipAroundItsCenter() {
        let geometry = NibGeometry(nib: Nib.round(diameter: 20))
        let half = geometry.polygon(center: CGPoint(x: 100, y: 50), scale: 0.5)
        let xs = half.map { $0.x }
        XCTAssertEqual((xs.max() ?? 0) - (xs.min() ?? 0), 10, accuracy: 0.001)
        XCTAssertEqual(((xs.max() ?? 0) + (xs.min() ?? 0)) / 2, 100, accuracy: 0.001)
    }

    func testTheReachOfACircleIsItsRadius() {
        XCTAssertEqual(NibGeometry(nib: Nib.round(diameter: 10)).reach, 5, accuracy: 0.001)
    }
}

// MARK: Turning finger samples into pen positions

final class StrokeBuilderTests: XCTestCase {
    private let marker = Brush.round(color: .black, diameter: 10)

    private func steps(of brush: Brush, _ points: [StrokePoint]) -> [StrokeStep] {
        let builder = StrokeBuilder(brush: brush, start: points[0])
        for point in points.dropFirst() {
            builder.add(point)
        }
        builder.finish()
        return builder.steps
    }

    func testATapIsOneStepAtFullSize() {
        let builder = StrokeBuilder(brush: marker, start: StrokePoint(x: 30, y: 40))
        builder.finish()
        XCTAssertEqual(builder.steps.count, 1)
        XCTAssertEqual(builder.steps[0].center, CGPoint(x: 30, y: 40))
        XCTAssertEqual(builder.steps[0].scale, 1, accuracy: 0.000001)
    }

    func testAStraightStrokeEndsWhereTheFingerLifted() throws {
        let result = steps(of: marker, linePoints(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 110, y: 20)))
        let last = try XCTUnwrap(result.last)
        XCTAssertEqual(last.center.x, 110, accuracy: 0.6)
        XCTAssertEqual(last.center.y, 20, accuracy: 0.001)
    }

    func testStepsStayOnTheLineNeverGoBackwardsAndAreCloselySpaced() {
        let result = steps(of: marker, linePoints(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 110, y: 20)))
        for index in result.indices {
            XCTAssertEqual(result[index].center.y, 20, accuracy: 0.001)
            guard index > 0 else { continue }
            let travelled = result[index].center.x - result[index - 1].center.x
            XCTAssertGreaterThanOrEqual(travelled, -0.0001, "the pen never goes backwards")
            // A curve is stepped evenly in its parameter, not its length, so where the pen speeds up or slows down
            // a step can be up to about twice the nominal length. Each hull still covers the whole gap exactly.
            XCTAssertLessThanOrEqual(travelled, StrokeBuilder.stepLength * 2 + 0.0001, "steps are close enough to look smooth")
        }
    }

    func testTinyMovementsAreIgnored() {
        let builder = StrokeBuilder(brush: marker, start: StrokePoint(x: 10, y: 10))
        XCTAssertFalse(builder.add(StrokePoint(x: 10.1, y: 10.1, time: 0.01)))
        XCTAssertTrue(builder.add(StrokePoint(x: 20, y: 10, time: 0.02)))
    }

    func testNothingCanBeAddedAfterFinishing() {
        let builder = StrokeBuilder(brush: marker, start: StrokePoint(x: 10, y: 10))
        builder.finish()
        XCTAssertFalse(builder.add(StrokePoint(x: 50, y: 10, time: 0.1)))
    }

    func testTheSameInputAlwaysGivesTheSameSteps() {
        let dynamics = Dynamics(speedResponse: 0.8, minScale: 0.2, referenceSpeed: 900, contactResponse: 0.5,
                                taperIn: 20, startScale: 0.3, taperOut: 40, endScale: 0.1)
        let brush = Brush(color: .black, nib: Nib.round(diameter: 12), dynamics: dynamics)
        let points = (0..<80).map { index in
            StrokePoint(x: 10 + Double(index) * 3, y: 50 + 20 * sin(Double(index) / 6), time: Double(index) * 0.01, radius: 10 + Double(index % 5))
        }
        XCTAssertEqual(steps(of: brush, points), steps(of: brush, points))
    }

    func testARigidBrushNeverChangesSize() {
        let result = steps(of: marker, linePoints(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 400, y: 120), speed: 900))
        XCTAssertTrue(result.allSatisfy { abs($0.scale - 1) < 0.000001 })
    }

    func testSlowStrokesAreThickerThanFastOnesForASpeedSensitiveBrush() throws {
        let dynamics = Dynamics(speedResponse: 1, minScale: 0.25, referenceSpeed: 400)
        let brush = Brush(color: .black, nib: Nib.round(diameter: 20), dynamics: dynamics)
        let slow = steps(of: brush, linePoints(from: CGPoint(x: 40, y: 60), to: CGPoint(x: 480, y: 60), speed: 20))
        let fast = steps(of: brush, linePoints(from: CGPoint(x: 40, y: 60), to: CGPoint(x: 480, y: 60), speed: 800))

        let slowScale = slow[slow.count / 2].scale
        let fastScale = fast[fast.count / 2].scale
        XCTAssertGreaterThan(slowScale, 0.9)
        XCTAssertLessThan(fastScale, 0.4)
    }

    func testTheTipGrowsAtTheStartOfAStrokeWithATaperIn() throws {
        let dynamics = Dynamics(taperIn: 60, startScale: 0.2)
        let brush = Brush(color: .black, nib: Nib.round(diameter: 20), dynamics: dynamics)
        let result = steps(of: brush, linePoints(from: CGPoint(x: 40, y: 60), to: CGPoint(x: 300, y: 60)))
        XCTAssertEqual(result[0].scale, 0.2, accuracy: 0.000001)
        XCTAssertLessThan(result[10].scale, 0.5)
        let middle = result[result.count / 2]
        XCTAssertEqual(middle.scale, 1, accuracy: 0.001)
    }

    func testABrushWithATailRunsOnPastTheEndWhileShrinking() throws {
        let dynamics = Dynamics(taperOut: 40, endScale: 0.1)
        let brush = Brush(color: .black, nib: Nib.round(diameter: 20), dynamics: dynamics)
        let result = steps(of: brush, linePoints(from: CGPoint(x: 10, y: 60), to: CGPoint(x: 110, y: 60)))

        let last = try XCTUnwrap(result.last)
        XCTAssertEqual(last.center.x, 150, accuracy: 1.5, "the tail is 40 px long")
        XCTAssertEqual(last.scale, 0.1, accuracy: 0.001)

        let tail = result.filter { $0.center.x > 112 }
        XCTAssertFalse(tail.isEmpty)
        for (earlier, later) in zip(tail, tail.dropFirst()) {
            XCTAssertLessThanOrEqual(later.scale, earlier.scale + 0.000001, "the tail only shrinks")
        }
    }

    func testATapIsAFullSizeDotEvenForABrushThatTapersIn() {
        let dynamics = Dynamics(taperIn: 30, startScale: 0.2, taperOut: 40, endScale: 0.1)
        let brush = Brush(color: .black, nib: Nib.round(diameter: 20), dynamics: dynamics)
        let result = steps(of: brush, [StrokePoint(x: 50, y: 50)])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].scale, 1, accuracy: 0.000001)
    }

    func testAStrokeThatMovesStillStartsSmallWhenTheBrushTapersIn() {
        let dynamics = Dynamics(taperIn: 30, startScale: 0.2)
        let brush = Brush(color: .black, nib: Nib.round(diameter: 20), dynamics: dynamics)
        let result = steps(of: brush, linePoints(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 100, y: 20)))
        XCTAssertEqual(result[0].scale, 0.2, accuracy: 0.000001)
    }

    func testADotGetsNoTail() {
        let dynamics = Dynamics(taperOut: 40, endScale: 0.1)
        let brush = Brush(color: .black, nib: Nib.round(diameter: 20), dynamics: dynamics)
        XCTAssertEqual(steps(of: brush, [StrokePoint(x: 50, y: 50)]).count, 1)
    }

    func testPressingHarderThanUsualMakesTheTipLarger() throws {
        let dynamics = Dynamics(contactResponse: 1)
        let brush = Brush(color: .black, nib: Nib.round(diameter: 20), dynamics: dynamics)
        let points = (0..<60).map { index in
            StrokePoint(x: 10 + Double(index) * 4, y: 50, time: Double(index) * 0.01, radius: index < 8 ? 10 : 15)
        }
        let result = steps(of: brush, points)
        XCTAssertEqual(result[2].scale, 1, accuracy: 0.05, "the first samples define what 'usual' is")
        XCTAssertGreaterThan(result[result.count - 20].scale, 1.3)
    }

    func testMoreSmoothingMakesThePenTrailFurtherBehindTheFinger() {
        func penPosition(followTime: Double) -> CGFloat {
            let brush = Brush(color: .black, nib: Nib.round(diameter: 10), dynamics: Dynamics(followTime: followTime))
            let points = linePoints(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 410, y: 20), speed: 600)
            let builder = StrokeBuilder(brush: brush, start: points[0])
            for point in points.dropFirst() {
                builder.add(point)
            }
            return builder.steps[builder.steps.count - 1].center.x // while the finger is still down
        }
        let tight = penPosition(followTime: 0.004)
        let fluid = penPosition(followTime: 0.06)
        XCTAssertGreaterThan(tight, 400, "a tight pen is right under the finger")
        XCTAssertLessThan(fluid, tight - 20, "a fluid pen lags well behind it: \(fluid) vs \(tight)")
    }

    func testTheStrokeEndsWhereTheFingerLiftedWhateverTheSmoothing() throws {
        // 0 and 5 seconds are outside what the pen allows and are held to its limits.
        for followTime in [0.0, 0.004, 0.06, 5.0] {
            let brush = Brush(color: .black, nib: Nib.round(diameter: 10), dynamics: Dynamics(followTime: followTime))
            let result = steps(of: brush, linePoints(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 410, y: 20), speed: 600))
            let last = try XCTUnwrap(result.last)
            XCTAssertEqual(last.center.x, 410, accuracy: 0.6, "follow time \(followTime)")
            XCTAssertEqual(last.center.y, 20, accuracy: 0.001)
            XCTAssertTrue(result.allSatisfy { $0.center.x.isFinite && $0.scale.isFinite })
        }
    }

    func testAHugeJumpDoesNotProduceAHugeNumberOfSteps() {
        // A million pixels would be nearly a million steps without the per-span cap (400); the catch-up at the
        // end of the stroke is capped the same way, so the total stays in the low thousands.
        let builder = StrokeBuilder(brush: marker, start: StrokePoint(x: 0, y: 0))
        builder.add(StrokePoint(x: 1_000_000, y: 1_000_000, time: 0.01))
        builder.finish()
        XCTAssertLessThan(builder.steps.count, 6_000)
    }
}

// MARK: What ends up on the canvas

final class CalligraphyRenderTests: XCTestCase {
    /// A flat pen, 20 px broad, held at 45° (its edge runs from lower left to upper right on screen).
    private let chisel = Brush(color: .black, nib: Nib(shape: .rectangle, length: 20, thickness: 2, angleDegrees: 45))

    private func paint(_ brush: Brush, _ points: [StrokePoint], width: Int = 220, height: Int = 220) throws -> BitmapCanvas {
        let canvas = try XCTUnwrap(BitmapCanvas(spec: CanvasSpec(width: width, height: height)))
        canvas.paint(Stroke(brush: brush, points: points))
        return canvas
    }

    func testAFlatPenDrawsAHairlineAlongItsEdge() throws {
        // The pen's edge runs up and to the right, and so does this stroke.
        let canvas = try paint(chisel, linePoints(from: CGPoint(x: 40, y: 180), to: CGPoint(x: 180, y: 40)))
        let width = inkWidth(in: canvas, through: CGPoint(x: 110, y: 110), direction: CGVector(dx: 1, dy: 1))
        XCTAssertGreaterThan(width, 1.0)
        XCTAssertLessThan(width, 4.0, "moving along the edge leaves only the hairline: \(width)")
    }

    func testAFlatPenDrawsItsFullWidthAcrossItsEdge() throws {
        // This stroke runs down and to the right, straight across the pen's edge.
        let canvas = try paint(chisel, linePoints(from: CGPoint(x: 40, y: 40), to: CGPoint(x: 180, y: 180)))
        let width = inkWidth(in: canvas, through: CGPoint(x: 110, y: 110), direction: CGVector(dx: 1, dy: -1))
        XCTAssertEqual(width, 20, accuracy: 2.5, "moving across the edge leaves the full width: \(width)")
    }

    func testAHorizontalStrokeFromAFortyFiveDegreePenIsAboutSeventyPercentOfTheEdge() throws {
        // 20 * sin(45°) + 2 * cos(45°) = 15.56 px
        let canvas = try paint(chisel, linePoints(from: CGPoint(x: 40, y: 110), to: CGPoint(x: 180, y: 110)))
        let width = inkWidth(in: canvas, through: CGPoint(x: 110, y: 110), direction: CGVector(dx: 0, dy: 1))
        XCTAssertEqual(width, 15.56, accuracy: 2.0)
    }

    func testAnOvalPenIsThickInOneDirectionAndThinInTheOther() throws {
        let oval = Brush(color: .black, nib: Nib(shape: .ellipse, length: 24, thickness: 6, angleDegrees: 0))
        let horizontal = try paint(oval, linePoints(from: CGPoint(x: 40, y: 110), to: CGPoint(x: 180, y: 110)))
        let vertical = try paint(oval, linePoints(from: CGPoint(x: 110, y: 40), to: CGPoint(x: 110, y: 180)))

        let across = inkWidth(in: horizontal, through: CGPoint(x: 110, y: 110), direction: CGVector(dx: 0, dy: 1))
        let along = inkWidth(in: vertical, through: CGPoint(x: 110, y: 110), direction: CGVector(dx: 1, dy: 0))
        XCTAssertEqual(across, 6, accuracy: 2.0)
        XCTAssertEqual(along, 24, accuracy: 2.5)
    }

    func testARoundPenDrawsTheSameWidthInEveryDirection() throws {
        let round = Brush.round(color: .black, diameter: 12)
        let horizontal = try paint(round, linePoints(from: CGPoint(x: 40, y: 110), to: CGPoint(x: 180, y: 110)))
        let diagonal = try paint(round, linePoints(from: CGPoint(x: 40, y: 40), to: CGPoint(x: 180, y: 180)))

        XCTAssertEqual(inkWidth(in: horizontal, through: CGPoint(x: 110, y: 110), direction: CGVector(dx: 0, dy: 1)), 12, accuracy: 2.0)
        XCTAssertEqual(inkWidth(in: diagonal, through: CGPoint(x: 110, y: 110), direction: CGVector(dx: 1, dy: -1)), 12, accuracy: 2.0)
    }

    func testAZigzagWithAFlatPenIsThickOnOneDiagonalAndThinOnTheOther() throws {
        // Up-right strokes run along the pen's edge (thin); down-right strokes cross it (thick).
        var points: [StrokePoint] = []
        var time = 0.0
        let corners = [CGPoint(x: 30, y: 190), CGPoint(x: 100, y: 120), CGPoint(x: 170, y: 190)]
        for pair in zip(corners, corners.dropFirst()) {
            let segment = linePoints(from: pair.0, to: pair.1)
            points += segment.map { StrokePoint(x: $0.x, y: $0.y, time: $0.time + time) }
            time += (segment.last?.time ?? 0)
        }
        let canvas = try paint(chisel, points)
        let upstroke = inkWidth(in: canvas, through: CGPoint(x: 65, y: 155), direction: CGVector(dx: 1, dy: 1), reach: 15)
        let downstroke = inkWidth(in: canvas, through: CGPoint(x: 135, y: 155), direction: CGVector(dx: 1, dy: -1), reach: 15)
        XCTAssertLessThan(upstroke, 5)
        XCTAssertGreaterThan(downstroke, 14)
    }

    func testASpeedSensitiveBrushDrawsAFastStrokeThinnerThanASlowOne() throws {
        let dynamics = Dynamics(speedResponse: 1, minScale: 0.25, referenceSpeed: 400)
        let brush = Brush(color: .black, nib: Nib.round(diameter: 20), dynamics: dynamics)
        let slow = try paint(brush, linePoints(from: CGPoint(x: 40, y: 60), to: CGPoint(x: 480, y: 60), speed: 20), width: 520, height: 120)
        let fast = try paint(brush, linePoints(from: CGPoint(x: 40, y: 60), to: CGPoint(x: 480, y: 60), speed: 800), width: 520, height: 120)

        let slowWidth = inkWidth(in: slow, through: CGPoint(x: 260, y: 60), direction: CGVector(dx: 0, dy: 1))
        let fastWidth = inkWidth(in: fast, through: CGPoint(x: 260, y: 60), direction: CGVector(dx: 0, dy: 1))
        XCTAssertGreaterThan(slowWidth, 16)
        XCTAssertLessThan(fastWidth, slowWidth * 0.5, "slow \(slowWidth) vs fast \(fastWidth)")
    }

    func testABrushTailExtendsTheInkPastTheEndOfTheStroke() throws {
        let dynamics = Dynamics(taperOut: 40, endScale: 0.1)
        let brush = Brush(color: .black, nib: Nib.round(diameter: 10), dynamics: dynamics)
        let canvas = try paint(brush, linePoints(from: CGPoint(x: 40, y: 60), to: CGPoint(x: 160, y: 60)), width: 260, height: 120)

        XCTAssertLessThan(try XCTUnwrap(canvas.pixel(x: 185, y: 60)).r, 128, "the tail carries on past where the finger lifted")
        XCTAssertGreaterThan(try XCTUnwrap(canvas.pixel(x: 208, y: 60)).r, 200, "and ends in a point")
    }

    func testTheStartOfAStrokeIsNarrowWhenTheBrushTapersIn() throws {
        let dynamics = Dynamics(taperIn: 60, startScale: 0.2)
        let brush = Brush(color: .black, nib: Nib.round(diameter: 20), dynamics: dynamics)
        let canvas = try paint(brush, linePoints(from: CGPoint(x: 40, y: 60), to: CGPoint(x: 300, y: 60)), width: 340, height: 120)

        let atStart = inkWidth(in: canvas, through: CGPoint(x: 52, y: 60), direction: CGVector(dx: 0, dy: 1))
        let later = inkWidth(in: canvas, through: CGPoint(x: 200, y: 60), direction: CGVector(dx: 0, dy: 1))
        XCTAssertLessThan(atStart, later * 0.6, "start \(atStart) vs later \(later)")
    }

    func testPaintingALiveStrokeGivesExactlyTheSamePixelsAsReplayingIt() throws {
        let dynamics = Dynamics(speedResponse: 0.8, minScale: 0.2, referenceSpeed: 600, contactResponse: 0,
                                taperIn: 30, startScale: 0.3, taperOut: 50, endScale: 0.05)
        let brush = Brush(color: RGBAColor(red: 0.1, green: 0.2, blue: 0.5),
                          nib: Nib(shape: .ellipse, length: 16, thickness: 7, angleDegrees: 35),
                          dynamics: dynamics)
        let points = (0..<600).map { index in
            StrokePoint(x: 20 + Double(index) * 1.2, y: 150 + 80 * sin(Double(index) / 25), time: Double(index) * 0.008)
        }

        let live = try XCTUnwrap(BitmapCanvas(spec: CanvasSpec(width: 800, height: 300)))
        let session = live.beginStroke(brush: brush, start: points[0])
        for point in points.dropFirst() {
            live.extend(session, with: point)
            live.updateLive([session])
        }
        let stroke = live.finish(session)
        XCTAssertGreaterThan(session.stepCount, StrokeSession.chunkSize * 5, "the stroke spans many chunks")

        let replay = try XCTUnwrap(BitmapCanvas(spec: CanvasSpec(width: 800, height: 300)))
        replay.paint(stroke)
        XCTAssertEqual(try XCTUnwrap(live.rawBytes()), try XCTUnwrap(replay.rawBytes()))
    }

    func testAVeryLongStrokeIsFast() throws {
        let brush = Brush(color: .black, nib: Nib(shape: .rectangle, length: 20, thickness: 2, angleDegrees: 40))
        let points = (0..<4000).map { index in
            StrokePoint(x: 1000 + 900 * cos(Double(index) / 150), y: 1000 + 900 * sin(Double(index) / 130), time: Double(index) * 0.008)
        }
        let canvas = try XCTUnwrap(BitmapCanvas(spec: CanvasSpec(width: 2000, height: 2000)))
        let started = Date()
        canvas.paint(Stroke(brush: brush, points: points))
        XCTAssertLessThan(Date().timeIntervalSince(started), 10, "painting 4000 points should take a fraction of a second")
    }
}
