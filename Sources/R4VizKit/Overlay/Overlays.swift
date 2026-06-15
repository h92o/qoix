import SwiftUI

/// Pass-through overlay — draws the scene untouched.
public final class NoOverlay: R4Overlay {
    public let id = "none"
    public let name = "None"
    public init() {}
    public func composite(_ audio: AudioFrame, size: CGSize, into context: inout GraphicsContext,
                          drawScene: (inout GraphicsContext) -> Void) {
        drawScene(&context)
    }
}

/// Beat-reactive blur — the scene is drawn into a blurred layer, the blur radius
/// kicking up on each detected beat and decaying between beats.
public final class BlurOverlay: R4Overlay {
    public let id = "blur"
    public let name = "Blur"
    private var env: Float = 0
    public init() {}
    public func composite(_ audio: AudioFrame, size: CGSize, into context: inout GraphicsContext,
                          drawScene: (inout GraphicsContext) -> Void) {
        if audio.beat { env = 1 }
        env = max(0, env - Float(audio.timepass) * 3)
        let radius = 1 + 9 * Double(env)
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: radius))
            drawScene(&layer)
        }
    }
}

/// CRT-style scanlines drawn over the scene.
public final class ScanlineOverlay: R4Overlay {
    public let id = "scanlines"
    public let name = "Scanlines"
    public init() {}
    public func composite(_ audio: AudioFrame, size: CGSize, into context: inout GraphicsContext,
                          drawScene: (inout GraphicsContext) -> Void) {
        drawScene(&context)
        var lines = Path()
        var y: CGFloat = 0
        while y < size.height {
            lines.addRect(CGRect(x: 0, y: y, width: size.width, height: 1.5))
            y += 3
        }
        context.fill(lines, with: .color(.black.opacity(0.35)))
    }
}

/// Classic spectrum-analyzer bars across the bottom, over the scene.
public final class SpectrumOverlay: R4Overlay {
    public let id = "spectrum-overlay"
    public let name = "Spectrum"
    public init() {}
    public func composite(_ audio: AudioFrame, size: CGSize, into context: inout GraphicsContext,
                          drawScene: (inout GraphicsContext) -> Void) {
        drawScene(&context)
        let bins = audio.spectrum
        guard !bins.isEmpty else { return }
        let bw = size.width / CGFloat(bins.count)
        for (i, mag) in bins.enumerated() {
            let h = max(1, CGFloat(mag) * size.height * 0.3)
            let rect = CGRect(x: CGFloat(i) * bw, y: size.height - h, width: bw * 0.85, height: h)
            let c = hsb(Double(i) / Double(bins.count) * 0.8, 0.85, 0.95)
            context.fill(Path(rect), with: .color(Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 0.75)))
        }
    }
}

/// A white flash on every beat that decays quickly — R4's `Overlay Strobe`.
public final class StrobeOverlay: R4Overlay {
    public let id = "strobe"
    public let name = "Strobe"
    private var env: Float = 0
    public init() {}
    public func composite(_ audio: AudioFrame, size: CGSize, into context: inout GraphicsContext,
                          drawScene: (inout GraphicsContext) -> Void) {
        drawScene(&context)
        if audio.beat { env = 1 }
        env = max(0, env - Float(audio.timepass) * 4)
        if env > 0.001 {
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(.white.opacity(Double(env) * 0.5)))
        }
    }
}

/// Chromatic aberration — the scene is drawn three times, tinted red/green/blue
/// and offset, the split widening with the bass. R4's `Overlay RGB Split`.
public final class RGBSplitOverlay: R4Overlay {
    public let id = "rgb-split"
    public let name = "RGB Split"
    public init() {}
    public func composite(_ audio: AudioFrame, size: CGSize, into context: inout GraphicsContext,
                          drawScene: (inout GraphicsContext) -> Void) {
        let off = CGFloat(2 + 12 * audio.band(0, 0.15))
        let channels: [(color: Color, dx: CGFloat)] = [
            (.red, -off), (.green, 0), (.blue, off)
        ]
        for ch in channels {
            var c = context
            c.blendMode = .plusLighter
            c.translateBy(x: ch.dx, y: 0)
            c.addFilter(.colorMultiply(ch.color))
            c.drawLayer { layer in drawScene(&layer) }
        }
    }
}
