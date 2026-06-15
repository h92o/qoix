import SwiftUI

/// Renders the active scene (plus fade + overlay) every display frame.
///
/// `TimelineView(.animation)` ticks at the display's refresh rate and feeds a
/// monotonic timestamp into the engine, which composites scene → fade → overlay
/// into a single GPU-backed `Canvas`. Smooth and resolution-independent on both
/// macOS and iOS.
public struct VisualizationView: View {

    @ObservedObject private var engine: VisualizationEngine
    private let startDate = Date()

    public init(engine: VisualizationEngine) {
        self.engine = engine
    }

    public var body: some View {
        TimelineView(.animation(paused: !engine.isRunning)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startDate)
            Canvas { context, size in
                engine.renderFrame(into: &context, size: size, at: elapsed)
            }
            .background(Color.black)
        }
    }
}
