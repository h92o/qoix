import XCTest
@testable import R4VizKit

final class R4VizKitTests: XCTestCase {

    func testDefaultRegistryHasPlugins() {
        let registry = PluginRegistry.makeDefault()
        XCTAssertFalse(registry.plugins.isEmpty)
        XCTAssertNotNil(registry.plugin(withID: "waveform"))
        XCTAssertNotNil(registry.plugin(withID: "spectrum-bars"))
        XCTAssertNotNil(registry.plugin(withID: "particle-field"))
    }

    func testPluginIdentifiersAreUnique() {
        let ids = PluginRegistry.makeDefault().plugins.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testSyntheticSourceProducesNormalizedFrame() {
        let source = SyntheticSignalSource(sampleCount: 64, binCount: 16)
        let frame = source.frame(at: 1.5)

        XCTAssertEqual(frame.samples.count, 64)
        XCTAssertEqual(frame.spectrum.count, 16)
        XCTAssertTrue(frame.samples.allSatisfy { $0 >= -1 && $0 <= 1 })
        XCTAssertTrue(frame.spectrum.allSatisfy { $0 >= 0 && $0 <= 1 })
        XCTAssertTrue((0...1).contains(frame.level))
    }

    func testSyntheticSourceIsDeterministic() {
        let source = SyntheticSignalSource()
        XCTAssertEqual(source.frame(at: 2.0).samples, source.frame(at: 2.0).samples)
    }

    @MainActor
    func testCyclePluginWrapsAround() {
        let engine = VisualizationEngine()
        // Cycle through every plugin and confirm we return to the start.
        let start = engine.selectedPluginID
        for _ in engine.registry.plugins { engine.cyclePlugin() }
        XCTAssertEqual(engine.selectedPluginID, start)
    }
}
