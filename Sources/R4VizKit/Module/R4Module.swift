import Foundation

/// A composable building block of a scene, mirroring R4 Construct's modules.
///
/// In R4 Construct a scene is a *graph* of modules wired together: each module
/// has typed inputs (buffers flowing in from other modules) and emits drawing
/// into the shared output, with the chain running background → effect → output.
/// We model the same idea: a module declares its `inputs` (which render first)
/// and draws one frame in `render`.
public protocol R4Module: AnyObject {
    /// Display name (R4 Construct module `NAME`).
    var name: String { get }
    /// Upstream modules feeding this one; they render before this module does.
    var inputs: [R4Module] { get }
    /// Reset per-run state.
    func reset()
    /// Draw this module's contribution for the current frame.
    func render(_ audio: AudioFrame, gl: GL)
}

public extension R4Module {
    var inputs: [R4Module] { [] }
    func reset() {}
}
