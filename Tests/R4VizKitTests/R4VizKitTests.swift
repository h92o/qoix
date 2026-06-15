import XCTest
import SwiftUI
@testable import R4VizKit

final class R4VizKitTests: XCTestCase {

    func testDefaultRegistryHasScenes() {
        let registry = SceneRegistry.makeDefault()
        XCTAssertFalse(registry.scenes.isEmpty)
        XCTAssertNotNil(registry.scene(withID: "spinner"))
        XCTAssertNotNil(registry.scene(withID: "thumper"))
        XCTAssertNotNil(registry.scene(withID: "cubefield"))
        XCTAssertNotNil(registry.scene(withID: "spectrum"))
    }

    func testSceneIdentifiersAreUnique() {
        let ids = SceneRegistry.makeDefault().scenes.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testSyntheticSourceProducesNormalizedFrame() {
        let source = SyntheticSignalSource(binCount: 32)
        let frame = source.frame(at: 1.5, timepass: 0.016)

        XCTAssertEqual(frame.spectrum.count, 32)
        XCTAssertTrue(frame.spectrum.allSatisfy { $0 >= 0 && $0 <= 1 })
        XCTAssertTrue(frame.sounda >= -1 && frame.sounda <= 1)
        XCTAssertEqual(frame.timepass, 0.016, accuracy: 1e-9)
    }

    func testBeatFiresOnBeatBoundary() {
        let source = SyntheticSignalSource(bpm: 120) // one beat every 0.5s
        // Stepping across a beat boundary should report a beat exactly once.
        _ = source.frame(at: 0.49, timepass: 0.49)
        let crossed = source.frame(at: 0.51, timepass: 0.02)
        XCTAssertTrue(crossed.beat)
        let same = source.frame(at: 0.52, timepass: 0.01)
        XCTAssertFalse(same.beat)
    }

    func testBandAveragesSpectrum() {
        let frame = AudioFrame(spectrum: [0, 0.5, 1, 0.5])
        XCTAssertEqual(frame.band(0, 0.5), 0.25, accuracy: 1e-6)   // first two bins
        XCTAssertEqual(frame.band(0.5, 1.0), 0.75, accuracy: 1e-6) // last two bins
    }

    func testHSBConversion() {
        XCTAssertEqual(hsb(0, 1, 1).r, 1, accuracy: 1e-6)   // pure red
        let gray = hsb(0.3, 0, 0.5)
        XCTAssertEqual(gray.r, 0.5, accuracy: 1e-6)
        XCTAssertEqual(gray.g, 0.5, accuracy: 1e-6)
        XCTAssertEqual(gray.b, 0.5, accuracy: 1e-6)
    }

    func testMatrixPerspectiveProjectsForward() {
        // A point straight ahead should land near the screen center (NDC ~0).
        let proj = Matrix4.perspective(fovYDegrees: 60, aspect: 1, near: 0.1, far: 100)
        let mv = Matrix4.translation(0, 0, -5)
        let clip = proj.m * mv.m * SIMD4<Float>(0, 0, 0, 1)
        XCTAssertGreaterThan(clip.w, 0)
        XCTAssertEqual(clip.x / clip.w, 0, accuracy: 1e-5)
        XCTAssertEqual(clip.y / clip.w, 0, accuracy: 1e-5)
    }

    @MainActor
    func testCycleSceneWrapsAround() {
        let engine = VisualizationEngine()
        let start = engine.selectedSceneID
        for _ in engine.registry.scenes { engine.cycleScene() }
        XCTAssertEqual(engine.selectedSceneID, start)
    }
}
