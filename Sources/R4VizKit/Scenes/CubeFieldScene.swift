import SwiftUI

/// Reinterpretation of R4's **Cubefield** scene by Gordon Williams: a field of
/// cubes streaming toward the camera, reacting to the music.
public final class CubeFieldScene: R4Scene {
    public let id = "cubefield"
    public let name = "Cube Field"
    public let author = "Gordon Williams (RabidHamster)"

    private struct Cube { var x: Float; var y: Float; var phase: Float }
    private var cubes: [Cube] = []
    private var travel: Float = 0

    private let columns = 5
    private let depth = 14
    private let spacing: Float = 2.2
    private let speed: Float = 4.0

    public func reset() {
        travel = 0
        cubes.removeAll()
        for d in 0..<depth {
            for c in 0..<columns {
                let x = (Float(c) - Float(columns - 1) / 2) * spacing
                let y = sinf(Float(d) * 0.7 + Float(c)) * 0.6
                cubes.append(Cube(x: x, y: y, phase: Float(d) / Float(depth)))
            }
        }
    }

    public func render(_ audio: AudioFrame, gl: GL) {
        if cubes.isEmpty { reset() }
        let bass = audio.band(0, 0.15)
        travel += Float(audio.timepass) * speed * (1 + bass)

        let totalDepth = Float(depth) * spacing

        for cube in cubes {
            // March each cube toward the camera, recycling it to the back before
            // it reaches the lens (nearest stays at `-nearLimit` so cubes never
            // balloon into a screen-filling face / clip the near plane).
            let nearLimit: Float = 2.0
            let range = totalDepth - nearLimit
            let z = -totalDepth + (cube.phase * range + travel)
                .truncatingRemainder(dividingBy: range)

            gl.pushMatrix()
            gl.translate(cube.x, cube.y, z)

            let size: Float = 0.5 + 0.5 * bass
            gl.scale(size, size, size)

            // Closer cubes are brighter; hue keyed to column position over time.
            let near = max(0, min(1, (z + totalDepth) / range))
            let hue = Double(cube.x) * 0.08 + Double(audio.time) * 0.03
            let col = hsb(hue, 0.6, 0.25 + 0.75 * Double(near))
            gl.glColor(col.r, col.g, col.b, 1)
            gl.cube()

            gl.popMatrix()
        }
    }
}
