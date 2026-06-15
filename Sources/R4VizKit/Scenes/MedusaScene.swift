import SwiftUI
import simd

/// Reinterpretation of R4's iconic **Medusa** module by Gordon Williams — a
/// writhing cloud of points "kicked" by the music. In R4 a Medusa module is fed
/// `kick = sounda` every frame; here a point cloud distributed over a sphere
/// pulses and tangles outward with the bass, drawn as additive soft points.
public final class MedusaScene: R4Scene {
    public let id = "medusa"
    public let name = "Medusa"
    public let author = "Gordon Williams (RabidHamster)"

    private let count = 420
    private var dirs: [SIMD3<Float>] = []
    private var spin: Float = 0
    private var kick: Float = 0

    public func reset() {
        spin = 0
        kick = 0
        dirs = MedusaScene.fibonacciSphere(count)
    }

    public func render(_ audio: AudioFrame, gl: GL) {
        if dirs.isEmpty { reset() }
        let bass = audio.band(0, 0.15)

        // Kick rises with sound and decays (mirrors R4 feeding `kick = sounda`).
        kick = max(kick - Float(audio.timepass) * 2.2, max(audio.sounda, bass))
        spin += Float(audio.timepass) * (18 + 40 * bass)

        let t = Float(audio.time)

        gl.additiveBlend()
        gl.pushMatrix()
        gl.translate(0, 0, -4.5)
        gl.rotate(spin, 0, 1, 0)
        gl.rotate(spin * 0.4, 1, 0, 0)

        for (i, d) in dirs.enumerated() {
            // Per-point radial wobble plus an outward kick that forms tentacles.
            let n = sinf(d.x * 4 + t * 2) + cosf(d.y * 5 + t * 1.7) + sinf(d.z * 3 + t * 2.3)
            let tentacle = 0.5 + 0.5 * sinf(Float(i) * 0.7 + t * 3)
            let r = 1.3 + 0.22 * n + 1.4 * kick * tentacle
            let p = d * r

            let hue = Double(i) / Double(count) + Double(t) * 0.03
            let c = hsb(hue, 0.7, 0.5 + 0.5 * Double(kick))
            gl.glColor(c.r, c.g, c.b, 0.5)
            gl.point(p, size: 0.16 + 0.20 * kick)
        }

        gl.popMatrix()
        gl.normalBlend()
    }

    /// Evenly distribute `n` points over a unit sphere (Fibonacci spiral).
    private static func fibonacciSphere(_ n: Int) -> [SIMD3<Float>] {
        guard n > 0 else { return [] }
        let golden = Float.pi * (3 - (5 as Float).squareRoot())
        return (0..<n).map { i in
            let y = 1 - (Float(i) / Float(n - 1)) * 2      // y from 1 to -1
            let radius = (max(0, 1 - y * y)).squareRoot()
            let theta = golden * Float(i)
            return SIMD3<Float>(cosf(theta) * radius, y, sinf(theta) * radius)
        }
    }
}
