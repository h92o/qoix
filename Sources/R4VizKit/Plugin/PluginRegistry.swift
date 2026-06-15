import Foundation

/// Holds the set of available ``VisualizationPlugin``s.
///
/// Keeping registration in one place makes it trivial to add a new visualizer:
/// drop a file in `Plugins/` and append it in ``PluginRegistry/makeDefault()``.
public final class PluginRegistry {

    public private(set) var plugins: [VisualizationPlugin]

    public init(plugins: [VisualizationPlugin]) {
        self.plugins = plugins
    }

    /// Look up a plugin by its identifier.
    public func plugin(withID id: String) -> VisualizationPlugin? {
        plugins.first { $0.id == id }
    }

    /// Register an additional plugin at runtime.
    public func register(_ plugin: VisualizationPlugin) {
        plugins.append(plugin)
    }

    /// The bundled plugins shipped with the scaffold.
    public static func makeDefault() -> PluginRegistry {
        PluginRegistry(plugins: [
            WaveformPlugin(),
            SpectrumBarsPlugin(),
            ParticleFieldPlugin()
        ])
    }
}
