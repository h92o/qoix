import SwiftUI

/// A post-processing pass applied over the rendered scene, mirroring R4's
/// `OVERLAY` modules (blur, mirror, RGB split, scanlines, spectrum, strobe…).
///
/// `composite` is handed the scene as a closure so the overlay decides how to
/// draw it: pass it through untouched, draw it into a filtered layer, or draw it
/// and then add decoration on top.
public protocol R4Overlay: AnyObject {
    var id: String { get }
    var name: String { get }

    /// Composite `drawScene` into `context` with this overlay's effect.
    func composite(
        _ audio: AudioFrame,
        size: CGSize,
        into context: inout GraphicsContext,
        drawScene: (inout GraphicsContext) -> Void
    )
}

/// Holds the available overlays. Add one by appending it in ``makeDefault()``.
public final class OverlayRegistry {
    public private(set) var overlays: [R4Overlay]

    public init(overlays: [R4Overlay]) { self.overlays = overlays }

    public func overlay(withID id: String) -> R4Overlay? {
        overlays.first { $0.id == id }
    }

    public static func makeDefault() -> OverlayRegistry {
        OverlayRegistry(overlays: [
            NoOverlay(),
            BlurOverlay(),
            ScanlineOverlay(),
            SpectrumOverlay(),
            StrobeOverlay(),
            RGBSplitOverlay()
        ])
    }
}
