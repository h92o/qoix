import SwiftUI
import Combine

/// Drives the visualization: owns the plugin registry, the active selection, and
/// the signal source, and exposes the per-frame input the view renders.
///
/// This is the single observable object the UI binds to. The view layer stays a
/// thin shell: it picks a plugin and asks the engine for the current frame.
@MainActor
public final class VisualizationEngine: ObservableObject {

    public let registry: PluginRegistry

    /// Identifier of the currently selected plugin.
    @Published public var selectedPluginID: String

    /// Whether the visualization is advancing.
    @Published public var isRunning: Bool = true

    private let source: SignalSource

    public init(
        registry: PluginRegistry = .makeDefault(),
        source: SignalSource = SyntheticSignalSource()
    ) {
        self.registry = registry
        self.source = source
        self.selectedPluginID = registry.plugins.first?.id ?? ""
    }

    /// The plugin matching ``selectedPluginID`` (falling back to the first).
    public var activePlugin: VisualizationPlugin? {
        registry.plugin(withID: selectedPluginID) ?? registry.plugins.first
    }

    /// Produce the input frame for `time`. When paused, returns a frozen frame.
    public func frame(at time: TimeInterval) -> VisualizationInput {
        source.frame(at: isRunning ? time : 0)
    }

    /// Advance to the next plugin in the registry (wraps around).
    public func cyclePlugin() {
        let plugins = registry.plugins
        guard let index = plugins.firstIndex(where: { $0.id == selectedPluginID }) else { return }
        selectedPluginID = plugins[(index + 1) % plugins.count].id
    }
}
