import SwiftUI
import R4VizKit

/// Shared entry point for both the macOS and iOS apps. The SwiftUI `App`
/// lifecycle is fully cross-platform, so a single file drives both targets.
@main
struct R4VizApp: App {

    @StateObject private var engine = VisualizationEngine()

    var body: some Scene {
        WindowGroup {
            ContentView(engine: engine)
                #if os(macOS)
                .frame(minWidth: 480, minHeight: 360)
                #endif
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        #endif
    }
}
