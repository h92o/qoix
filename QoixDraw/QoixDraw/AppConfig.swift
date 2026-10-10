import CoreGraphics
import Foundation

/// Every tunable in one place. Change a value here and rebuild.
enum AppConfig {
    // MARK: Canvas

    /// The drawing surface takes the shape of the screen, at the largest size allowed (2000 px on the long
    /// side). For a fixed square instead, return `CanvasSpec(width: 2000, height: 2000)`.
    static func canvasSpec(forViewSize size: CGSize) -> CanvasSpec {
        CanvasSpec.fitting(aspectOf: size)
    }

    static let canvasBackground = RGBAColor.white

    // MARK: Pen

    /// Line thickness as it appears on screen, in points. Converted to canvas pixels when drawing.
    static let penWidthPoints: Double = 4
    static let penColor = RGBAColor.black

    // MARK: Saving

    /// After a successful save, start a fresh canvas for the next picture. Shake, then Undo, brings the saved
    /// drawing back on screen.
    static let startNewCanvasAfterSave = true

    /// Volume presses closer together than this are treated as one (holding the button repeats it).
    static let saveCooldown: TimeInterval = 0.8

    // MARK: Diagnostics

    /// Show a small message whenever a Volume Up/Down press is detected (even on a blank canvas). Handy for
    /// checking the buttons work on your phone. Readings are also written to the Xcode console either way
    /// (filter for "app.qoix.draw").
    static let showVolumePressMessages = false
}
