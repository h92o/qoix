import SwiftUI

/// Reinterpretation of R4's **Spinner** scene by Gordon Williams.
///
/// The original draws eight nested quads, each one rotated and scaled relative
/// to the last, with the spin rate driven by the sound amplitude. We reproduce
/// that structure; lacking the original textures, the two interleaved layers are
/// drawn as additive tinted quads so the spiral still reads.
public final class SpinnerScene: R4Scene {
    public let id = "spinner"
    public let name = "Spinner"
    public let author = "Gordon Williams (RabidHamster)"

    private var bt: Float = 0

    public func reset() { bt = 0 }

    public func render(_ audio: AudioFrame, gl: GL) {
        // bt advances faster when the music is loud (original: timepass*(1+sounda)).
        bt += Float(audio.timepass) * (1.0 + max(audio.sounda, 0))

        gl.additiveBlend()
        gl.pushMatrix()
        gl.translate(0, 0, -3.5)

        // Per-step scale and rotation, exactly as the original derives them.
        var s = 1.0 + sinf(bt) + cosf(bt * 1.245)
        s = (s * 0.05) + 0.95
        let r = (audio.sounda + sinf(bt)) * 10

        let hue = Double(bt) * 0.05

        for i in 0..<8 {
            // Layer A (the "logo") and layer B (the "edge"), interleaved.
            let a = hsb(hue, 0.7, 1)
            gl.glColor(a.r, a.g, a.b, 0.18)
            gl.quad()

            let b = hsb(hue + 0.5, 0.8, 1)
            gl.glColor(b.r, b.g, b.b, 0.10 + 0.15 * Double(i) / 8)
            gl.quad()

            gl.rotate(r, 0, 0, 1)
            gl.scale(s, s, 1)
        }

        gl.popMatrix()
        gl.normalBlend()
    }
}
