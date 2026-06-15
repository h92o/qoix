import SwiftUI

/// Reinterpretation of R4's **Cube Spectrum / Spectrum Cylinder** scenes by
/// Gordon Williams: the frequency spectrum wrapped into a slowly rotating ring
/// of bars, each bar's height driven by its frequency band.
public final class SpectrumScene: R4Scene {
    public let id = "spectrum"
    public let name = "Spectrum Cylinder"
    public let author = "Gordon Williams (RabidHamster)"

    private var rot: Float = 0
    private var smoothed: [Float] = []

    private let bars = 48
    private let radius: Float = 2.6

    public func reset() { rot = 0; smoothed = [] }

    public func render(_ audio: AudioFrame, gl: GL) {
        if smoothed.count != bars { smoothed = [Float](repeating: 0, count: bars) }
        rot += Float(audio.timepass) * (12 + 30 * audio.band(0, 0.15))

        gl.pushMatrix()
        gl.translate(0, -0.2, -6.0)
        gl.rotate(-18, 1, 0, 0)        // tilt to look down on the ring slightly
        gl.rotate(rot, 0, 1, 0)

        for i in 0..<bars {
            // Sample the spectrum for this bar and smooth it over time (decay).
            let f = Float(i) / Float(bars)
            let target = audio.band(f * 0.9, f * 0.9 + 0.05)
            smoothed[i] = max(smoothed[i] - Float(audio.timepass) * 1.5, target)

            let angle = Float(i) / Float(bars) * 360
            let h = 0.1 + 2.4 * smoothed[i]

            gl.pushMatrix()
            gl.rotate(angle, 0, 1, 0)
            gl.translate(0, h - 1, -radius)   // sit bar base on the ring
            gl.scale(0.12, h, 0.12)

            let col = hsb(Double(f) * 0.8, 0.85, 0.4 + 0.6 * Double(smoothed[i]))
            gl.glColor(col.r, col.g, col.b, 1)
            gl.cube()
            gl.popMatrix()
        }

        gl.popMatrix()
    }
}
