import Foundation

/// One frame of audio analysis handed to a scene's `render`.
///
/// These map directly onto the reactive variables R4 scene scripts read:
/// `time`, `timepass`, `sounda` (overall amplitude), the spectrum (R4 exposes
/// `specleft[]` / `specright[]`), and a simple beat flag.
public struct AudioFrame: Sendable {
    /// Continuous time in seconds (R4 `time`).
    public var time: TimeInterval
    /// Seconds elapsed since the previous frame (R4 `timepass`).
    public var timepass: TimeInterval
    /// Overall signal amplitude, roughly `-1...1` (R4 `sounda`).
    public var sounda: Float
    /// Frequency-domain magnitudes, low → high, each `0...1` (R4 spectrum).
    public var spectrum: [Float]
    /// `true` on the frame a beat is detected.
    public var beat: Bool

    public init(
        time: TimeInterval = 0,
        timepass: TimeInterval = 0,
        sounda: Float = 0,
        spectrum: [Float] = [],
        beat: Bool = false
    ) {
        self.time = time
        self.timepass = timepass
        self.sounda = sounda
        self.spectrum = spectrum
        self.beat = beat
    }

    /// Average magnitude over a normalized band `0...1` of the spectrum.
    public func band(_ lo: Float, _ hi: Float) -> Float {
        guard !spectrum.isEmpty else { return 0 }
        let a = Int(lo * Float(spectrum.count)), b = max(Int(hi * Float(spectrum.count)), a + 1)
        let slice = spectrum[min(a, spectrum.count - 1)..<min(b, spectrum.count)]
        return slice.isEmpty ? 0 : slice.reduce(0, +) / Float(slice.count)
    }
}
