import SwiftUI

/// Renders the active plugin every display frame.
///
/// `TimelineView(.animation)` ticks at the display's refresh rate and feeds a
/// monotonic timestamp into the engine, so the visualization is smooth and
/// resolution-independent on both macOS and iOS. All drawing happens inside a
/// single `Canvas`, which SwiftUI renders on the GPU.
public struct VisualizationView: View {

    @ObservedObject private var engine: VisualizationEngine
    private let startDate = Date()

    public init(engine: VisualizationEngine) {
        self.engine = engine
    }

    public var body: some View {
        TimelineView(.animation(paused: !engine.isRunning)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startDate)
            let input = engine.frame(at: elapsed)

            Canvas { context, size in
                guard let plugin = engine.activePlugin else { return }
                var ctx = context
                plugin.render(input, into: &ctx, size: size)
            }
            .background(Color.black)
        }
    }
}
