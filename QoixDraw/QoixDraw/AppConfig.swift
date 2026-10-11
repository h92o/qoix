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

    /// The brush a fresh install starts with. After that the app remembers whatever you last chose (shake the
    /// phone, then Brush & Color). Pick any of `BrushPreset.all`, or build your own `BrushPreset`.
    static let defaultPreset = BrushPreset.chisel45

    /// A touch has to move this far (in points) before it starts drawing. A quick tap makes a dot instead, and a
    /// finger that just rests on the screen, like a thumb holding the phone, never marks it.
    static let strokeStartDistancePoints: CGFloat = 3
    static let tapMaxDuration: TimeInterval = 0.35

    /// How many fingers can write at the same time. Calligraphy is one pen, so a second finger touching down while
    /// a stroke is in progress (the knuckle of your writing hand, say) is ignored. Raise it to draw with several
    /// fingers at once.
    static let maximumSimultaneousStrokes = 1

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
