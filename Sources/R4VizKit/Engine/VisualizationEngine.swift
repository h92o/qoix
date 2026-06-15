import SwiftUI

/// Drives the visualization: owns the scene registry, the active selection, and
/// the signal source, and produces the per-frame ``AudioFrame``.
///
/// This is the single observable object the UI binds to. The view layer stays a
/// thin shell: it picks a scene and renders the current frame.
@MainActor
public final class VisualizationEngine: ObservableObject {

    public let registry: SceneRegistry

    @Published public var selectedSceneID: String
    @Published public var isRunning: Bool = true

    private let source: SignalSource
    private var lastTime: TimeInterval?

    public init(
        registry: SceneRegistry = .makeDefault(),
        source: SignalSource = SyntheticSignalSource()
    ) {
        self.registry = registry
        self.source = source
        self.selectedSceneID = registry.scenes.first?.id ?? ""
        registry.scenes.forEach { $0.reset() }
    }

    /// The scene matching ``selectedSceneID`` (falling back to the first).
    public var activeScene: R4Scene? {
        registry.scene(withID: selectedSceneID) ?? registry.scenes.first
    }

    /// Produce the input frame for `time`, deriving `timepass` from the gap since
    /// the previous frame. When paused, the clock holds still.
    public func frame(at time: TimeInterval) -> AudioFrame {
        let timepass = max(0, min(time - (lastTime ?? time), 0.1))
        lastTime = time
        return source.frame(at: time, timepass: isRunning ? timepass : 0)
    }

    /// Select the next scene in the registry (wraps around) and reset it.
    public func cycleScene() {
        let scenes = registry.scenes
        guard let index = scenes.firstIndex(where: { $0.id == selectedSceneID }) else { return }
        let next = scenes[(index + 1) % scenes.count]
        selectedSceneID = next.id
        next.reset()
    }
}
