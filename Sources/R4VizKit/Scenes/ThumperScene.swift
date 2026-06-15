import SwiftUI

/// Reinterpretation of R4's **Thumper / Bass Cube** scenes by Gordon Williams.
///
/// In the originals a textured cube is "kicked" every frame by `sounda` so it
/// thumps in time with the bass. Here a cube pulses its scale with the bass band
/// and snaps on detected beats, while slowly tumbling.
public final class ThumperScene: R4Scene {
    public let id = "thumper"
    public let name = "Thumper"
    public let author = "Gordon Williams (RabidHamster)"

    private var spin: Float = 0
    private var thump: Float = 0

    public func reset() { spin = 0; thump = 0 }

    public func render(_ audio: AudioFrame, gl: GL) {
        let bass = audio.band(0, 0.12)

        // The thump value rises sharply on a beat and decays smoothly.
        if audio.beat { thump = 1 }
        thump = max(thump - Float(audio.timepass) * 3.5, bass)

        spin += Float(audio.timepass) * (20 + 40 * bass)

        gl.pushMatrix()
        gl.translate(0, 0, -4.5)
        gl.rotate(spin, 0.3, 1, 0.15)

        let scale = 1.0 + 0.6 * thump
        gl.scale(scale, scale, scale)

        let hue = Double(audio.time) * 0.04
        let c = hsb(hue, 0.55, 0.55 + 0.45 * Double(thump))
        gl.glColor(c.r, c.g, c.b, 1)
        gl.cube()

        gl.popMatrix()
    }
}
