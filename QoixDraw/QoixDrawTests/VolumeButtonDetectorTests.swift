import XCTest
@testable import QoixDraw

final class VolumeButtonDetectorTests: XCTestCase {
    func testAVolumeDownPressIsRecognised() {
        var detector = VolumeButtonDetector(baseline: 0.5)
        XCTAssertEqual(detector.ingest(0.4375), .down)
    }

    func testAVolumeUpPressIsRecognised() {
        var detector = VolumeButtonDetector(baseline: 0.5)
        XCTAssertEqual(detector.ingest(0.5625), .up)
    }

    func testTheRestingLevelSurvivesAPressSoTheObserverCanRestoreIt() {
        var detector = VolumeButtonDetector(baseline: 0.5)
        _ = detector.ingest(0.4375)
        XCTAssertEqual(detector.baseline, 0.5)
    }

    func testTheEchoOfRestoringTheVolumeIsNotAPress() {
        var detector = VolumeButtonDetector(baseline: 0.5)
        XCTAssertEqual(detector.ingest(0.4375), .down)
        XCTAssertNil(detector.ingest(0.5))
        XCTAssertEqual(detector.ingest(0.4375), .down, "the next press must still be seen")
    }

    func testRepeatedPressesBeforeTheRestoreLandsAreAllSeen() {
        var detector = VolumeButtonDetector(baseline: 0.5)
        XCTAssertEqual(detector.ingest(0.4375), .down)
        XCTAssertEqual(detector.ingest(0.375), .down)
        XCTAssertNil(detector.ingest(0.5))
    }

    func testSmallDriftIsAdoptedNotTreatedAsAPress() {
        var detector = VolumeButtonDetector(baseline: 0.5)
        XCTAssertNil(detector.ingest(0.51))
        XCTAssertEqual(detector.baseline, 0.51)
        XCTAssertEqual(detector.ingest(0.51 - VolumeButtonDetector.hardwareStep), .down)
    }

    func testAPressAtTheBottomOfTheRangeIsRecognised() {
        var detector = VolumeButtonDetector(baseline: VolumeButtonDetector.hardwareStep)
        XCTAssertEqual(detector.ingest(0), .down)
    }

    func testAPartialStepAtTheTopIsRecognised() {
        var detector = VolumeButtonDetector(baseline: 0.96)
        XCTAssertEqual(detector.ingest(1.0), .up)
    }

    func testRebaseAdoptsTheNewLevel() {
        var detector = VolumeButtonDetector(baseline: 0.5)
        detector.rebase(to: 0.25)
        XCTAssertEqual(detector.baseline, 0.25)
        XCTAssertEqual(detector.ingest(0.1875), .down)
    }

    func testVolumeDownCannotBeDetectedWhenTheVolumeIsAtZero() {
        XCTAssertFalse(VolumeButtonDetector.canDetectDownPress(atVolume: 0))
        XCTAssertTrue(VolumeButtonDetector.canDetectDownPress(atVolume: VolumeButtonDetector.hardwareStep))
        XCTAssertTrue(VolumeButtonDetector.canDetectDownPress(atVolume: 0.5))
        XCTAssertTrue(VolumeButtonDetector.canDetectDownPress(atVolume: 1))
    }
}
