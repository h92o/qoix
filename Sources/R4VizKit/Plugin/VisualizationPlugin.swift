import SwiftUI

/// A single visualization "preset", equivalent to one of the visualizers in the
/// original Win32 R4 project.
///
/// Plugins are intentionally tiny: they take a frame of ``VisualizationInput``
/// and draw into a SwiftUI `GraphicsContext`. Rendering through `GraphicsContext`
/// keeps every plugin GPU-accelerated and identical across macOS and iOS without
/// any platform-specific drawing code. A plugin that needs lower-level access can
/// later be backed by Metal behind this same protocol.
public protocol VisualizationPlugin: AnyObject {

    /// Stable identifier used for selection/persistence.
    var id: String { get }

    /// Human-readable name shown in the picker.
    var displayName: String { get }

    /// Draw `input` into `context` for a view of the given `size`.
    ///
    /// Implementations must be pure with respect to `input` — all animation
    /// state should derive from `input.time` so rendering is deterministic and
    /// resolution-independent.
    func render(_ input: VisualizationInput, into context: inout GraphicsContext, size: CGSize)
}

public extension VisualizationPlugin {
    var displayName: String { id }
}
