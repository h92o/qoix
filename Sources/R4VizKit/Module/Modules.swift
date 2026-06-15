import Foundation

/// A solid color background — R4 Construct's `Solid` module (`SOLID m(); m.col = rgb(...)`).
/// Has no inputs, so it renders first and clears the frame to its color.
public final class SolidModule: R4Module {
    public let name = "Solid"
    private let r, g, b: Double

    public init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    public func render(_ audio: AudioFrame, gl: GL) {
        gl.fillBackground(r, g, b)
    }
}

/// A Medusa effect over an upstream module — R4 Construct's `Medusa` module
/// (`MEDUSA m(in1, in2); m.kick = sounda;`). Delegates to ``MedusaScene`` so the
/// look matches the standalone scene.
public final class MedusaModule: R4Module {
    public let name = "Medusa"
    public let inputs: [R4Module]
    private let effect = MedusaScene()

    public init(_ input: R4Module) { self.inputs = [input] }

    public func reset() { effect.reset() }
    public func render(_ audio: AudioFrame, gl: GL) { effect.render(audio, gl: gl) }
}

/// A Cube Field effect over an upstream module — R4 Construct's `CubeField`
/// module (`CUBEFIELD m(in1, in2);`).
public final class CubeFieldModule: R4Module {
    public let name = "CubeField"
    public let inputs: [R4Module]
    private let effect = CubeFieldScene()

    public init(_ input: R4Module) { self.inputs = [input] }

    public func reset() { effect.reset() }
    public func render(_ audio: AudioFrame, gl: GL) { effect.render(audio, gl: gl) }
}
