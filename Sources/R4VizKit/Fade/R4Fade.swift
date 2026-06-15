import SwiftUI

/// A transition between two scenes, mirroring R4's `FADE` modules (cross-fade,
/// slide, zoom, cube, …). Given the outgoing and incoming scenes as closures and
/// a progress `t` in `0...1`, it composites the blend.
public protocol R4Fade: AnyObject {
    var id: String { get }
    var name: String { get }

    func render(
        _ t: Double,
        audio: AudioFrame,
        size: CGSize,
        into context: inout GraphicsContext,
        from: (inout GraphicsContext) -> Void,
        to: (inout GraphicsContext) -> Void
    )
}

/// Holds the available fades. Add one by appending it in ``makeDefault()``.
public final class FadeRegistry {
    public private(set) var fades: [R4Fade]

    public init(fades: [R4Fade]) { self.fades = fades }

    public func fade(withID id: String) -> R4Fade? {
        fades.first { $0.id == id }
    }

    public static func makeDefault() -> FadeRegistry {
        FadeRegistry(fades: [
            CrossFade(),
            CutFade(),
            SlideFade(),
            ZoomFade()
        ])
    }
}
