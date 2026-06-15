import SwiftUI

/// Renders the active scene every display frame.
///
/// `TimelineView(.animation)` ticks at the display's refresh rate and feeds a
/// monotonic timestamp into the engine; the scene then draws through the
/// immediate-mode ``GL`` helper into a single GPU-backed `Canvas`. Smooth and
/// resolution-independent on both macOS and iOS.
public struct VisualizationView: View {

    @ObservedObject private var engine: VisualizationEngine
    private let startDate = Date()

    public init(engine: VisualizationEngine) {
        self.engine = engine
    }

    public var body: some View {
        TimelineView(.animation(paused: !engine.isRunning)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startDate)
            let audio = engine.frame(at: elapsed)

            Canvas { context, size in
                guard let scene = engine.activeScene else { return }
                let gl = GL(context: context, size: size)
                scene.render(audio, gl: gl)
            }
            .background(Color.black)
        }
    }
}
