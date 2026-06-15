import SwiftUI

/// Instant cut — the incoming scene simply replaces the outgoing one.
public final class CutFade: R4Fade {
    public let id = "cut"
    public let name = "Cut"
    public init() {}
    public func render(_ t: Double, audio: AudioFrame, size: CGSize, into context: inout GraphicsContext,
                       from: (inout GraphicsContext) -> Void, to: (inout GraphicsContext) -> Void) {
        to(&context)
    }
}

/// Cross-dissolve — the outgoing scene fades out as the incoming fades in.
public final class CrossFade: R4Fade {
    public let id = "cross"
    public let name = "Cross Fade"
    public init() {}
    public func render(_ t: Double, audio: AudioFrame, size: CGSize, into context: inout GraphicsContext,
                       from: (inout GraphicsContext) -> Void, to: (inout GraphicsContext) -> Void) {
        var a = context
        a.opacity = 1 - t
        a.drawLayer { layer in from(&layer) }

        var b = context
        b.opacity = t
        b.drawLayer { layer in to(&layer) }
    }
}

/// Horizontal slide — the outgoing scene exits left as the incoming enters from
/// the right.
public final class SlideFade: R4Fade {
    public let id = "slide"
    public let name = "Slide"
    public init() {}
    public func render(_ t: Double, audio: AudioFrame, size: CGSize, into context: inout GraphicsContext,
                       from: (inout GraphicsContext) -> Void, to: (inout GraphicsContext) -> Void) {
        var a = context
        a.translateBy(x: -CGFloat(t) * size.width, y: 0)
        a.drawLayer { layer in from(&layer) }

        var b = context
        b.translateBy(x: CGFloat(1 - t) * size.width, y: 0)
        b.drawLayer { layer in to(&layer) }
    }
}

/// Zoom blend — the outgoing scene scales up and fades while the incoming scene
/// scales up from small into place.
public final class ZoomFade: R4Fade {
    public let id = "zoom"
    public let name = "Zoom"
    public init() {}
    public func render(_ t: Double, audio: AudioFrame, size: CGSize, into context: inout GraphicsContext,
                       from: (inout GraphicsContext) -> Void, to: (inout GraphicsContext) -> Void) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        var a = context
        a.opacity = 1 - t
        scale(&a, around: center, by: 1 + 0.6 * CGFloat(t))
        a.drawLayer { layer in from(&layer) }

        var b = context
        b.opacity = t
        scale(&b, around: center, by: 0.5 + 0.5 * CGFloat(t))
        b.drawLayer { layer in to(&layer) }
    }

    private func scale(_ ctx: inout GraphicsContext, around center: CGPoint, by factor: CGFloat) {
        ctx.translateBy(x: center.x, y: center.y)
        ctx.scaleBy(x: factor, y: factor)
        ctx.translateBy(x: -center.x, y: -center.y)
    }
}
