import SwiftUI

/// Drives the visualization: owns the scene / overlay / fade registries, the
/// active selections, scene-to-scene transitions, and the signal source, and
/// renders a full frame (scene → fade → overlay) into a `GraphicsContext`.
///
/// This is the single observable object the UI binds to.
@MainActor
public final class VisualizationEngine: ObservableObject {

    public let registry: SceneRegistry
    public let overlays: OverlayRegistry
    public let fades: FadeRegistry

    /// Active scene. Changing it starts a transition using the selected fade.
    @Published public var selectedSceneID: String {
        didSet { beginTransition(from: oldValue) }
    }
    @Published public var selectedOverlayID: String
    @Published public var selectedFadeID: String
    @Published public var isRunning: Bool = true

    private let source: SignalSource
    private var lastTime: TimeInterval?

    // Transition state.
    private let transitionDuration: TimeInterval = 0.8
    private var fromScene: R4Scene?
    private var transitionT: Double = 1   // 1 = no transition in progress

    public init(
        registry: SceneRegistry = .makeDefault(),
        overlays: OverlayRegistry = .makeDefault(),
        fades: FadeRegistry = .makeDefault(),
        source: SignalSource = SyntheticSignalSource()
    ) {
        self.registry = registry
        self.overlays = overlays
        self.fades = fades
        self.source = source
        self.selectedSceneID = registry.scenes.first?.id ?? ""
        self.selectedOverlayID = overlays.overlays.first?.id ?? "none"
        self.selectedFadeID = fades.fades.first?.id ?? "cross"
        registry.scenes.forEach { $0.reset() }
    }

    public var activeScene: R4Scene? {
        registry.scene(withID: selectedSceneID) ?? registry.scenes.first
    }
    public var activeOverlay: R4Overlay {
        overlays.overlay(withID: selectedOverlayID) ?? NoOverlay()
    }
    public var activeFade: R4Fade {
        fades.fade(withID: selectedFadeID) ?? CutFade()
    }

    /// Render the whole frame for `time` into `context`: the active scene (or a
    /// fade between the previous and active scene), wrapped by the active overlay.
    public func renderFrame(into context: inout GraphicsContext, size: CGSize, at time: TimeInterval) {
        let audio = frame(at: time)

        // Advance any in-progress transition.
        if transitionT < 1 {
            transitionT = min(1, transitionT + audio.timepass / transitionDuration)
            if transitionT >= 1 { fromScene = nil }
        }

        let fade = activeFade
        let t = transitionT
        let outgoing = fromScene
        let incoming = activeScene

        let drawComposited: (inout GraphicsContext) -> Void = { ctx in
            if let outgoing, t < 1 {
                fade.render(t, audio: audio, size: size, into: &ctx,
                            from: { c in self.draw(outgoing, audio, into: &c, size: size) },
                            to: { c in self.draw(incoming, audio, into: &c, size: size) })
            } else {
                self.draw(incoming, audio, into: &ctx, size: size)
            }
        }

        activeOverlay.composite(audio, size: size, into: &context, drawScene: drawComposited)
    }

    /// Select the next scene in the registry (wraps around).
    public func cycleScene() {
        let scenes = registry.scenes
        guard let index = scenes.firstIndex(where: { $0.id == selectedSceneID }) else { return }
        selectedSceneID = scenes[(index + 1) % scenes.count].id   // didSet starts the transition
    }

    // MARK: - Private

    private func draw(_ scene: R4Scene?, _ audio: AudioFrame, into ctx: inout GraphicsContext, size: CGSize) {
        guard let scene else { return }
        let gl = GL(context: ctx, size: size)
        scene.render(audio, gl: gl)
    }

    private func beginTransition(from oldID: String) {
        guard oldID != selectedSceneID else { return }
        activeScene?.reset()
        if let old = registry.scene(withID: oldID), activeFade.id != "cut" {
            fromScene = old
            transitionT = 0
        } else {
            fromScene = nil
            transitionT = 1
        }
    }

    /// Produce the input frame for `time`, deriving `timepass` from the gap since
    /// the previous frame. When paused, the clock holds still.
    private func frame(at time: TimeInterval) -> AudioFrame {
        let timepass = max(0, min(time - (lastTime ?? time), 0.1))
        lastTime = time
        return source.frame(at: time, timepass: isRunning ? timepass : 0)
    }
}
