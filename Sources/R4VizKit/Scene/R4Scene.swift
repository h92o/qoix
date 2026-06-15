import SwiftUI

/// A single R4-style visualization. Equivalent to one `SCENE (...)` script in
/// the original R4: it keeps a little internal state and draws one frame in
/// response to the current ``AudioFrame`` using the immediate-mode ``GL`` helper.
public protocol R4Scene: AnyObject {
    /// Stable identifier used for selection/persistence.
    var id: String { get }
    /// Display name shown in the picker.
    var name: String { get }
    /// Original scene author / attribution.
    var author: String { get }

    /// Reset per-run state (R4 `reset()`).
    func reset()

    /// Draw one frame (R4 `render()`), reading reactive values from `audio`.
    func render(_ audio: AudioFrame, gl: GL)
}

public extension R4Scene {
    var author: String { "" }
    func reset() {}
}
