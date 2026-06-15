import Foundation

/// A single frame of data handed to a ``VisualizationPlugin`` to render.
///
/// In the original Win32 "R4" project the visualizers consumed an audio/data
/// stream. Here we abstract that into a normalized snapshot so plugins never
/// need to know where the data came from (synthetic generator, microphone,
/// file playback, etc.).
public struct VisualizationInput: Sendable {

    /// Continuous playback time, in seconds, since the engine started.
    public var time: TimeInterval

    /// Raw time-domain waveform, each sample normalized to `-1...1`.
    public var samples: [Float]

    /// Frequency-domain magnitudes (e.g. an FFT result), each bin `0...1`,
    /// ordered low frequency → high frequency.
    public var spectrum: [Float]

    /// Overall signal level / loudness for this frame, `0...1`.
    public var level: Float

    public init(
        time: TimeInterval = 0,
        samples: [Float] = [],
        spectrum: [Float] = [],
        level: Float = 0
    ) {
        self.time = time
        self.samples = samples
        self.spectrum = spectrum
        self.level = level
    }

    /// An empty frame, useful as a default before any data arrives.
    public static let silence = VisualizationInput()
}
