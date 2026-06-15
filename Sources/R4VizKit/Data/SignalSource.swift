import Foundation

/// Produces a ``VisualizationInput`` for a given point in time.
///
/// Conform a microphone tap, audio-file decoder, or network feed to this
/// protocol to drive the visualizers with real data. The scaffold ships with
/// ``SyntheticSignalSource`` so the app animates out of the box.
public protocol SignalSource: AnyObject {
    /// The number of waveform samples produced per frame.
    var sampleCount: Int { get }

    /// The number of spectrum bins produced per frame.
    var binCount: Int { get }

    /// Sample the source for the frame at `time` (seconds).
    func frame(at time: TimeInterval) -> VisualizationInput
}

/// A self-contained signal generator that fabricates a plausible, animated
/// waveform + spectrum. It lets the scaffold run with no audio permissions or
/// external input, and serves as a reference for what a real source must emit.
public final class SyntheticSignalSource: SignalSource {

    public let sampleCount: Int
    public let binCount: Int

    /// A few detuned partials mixed together to make the output look "musical".
    private let partials: [(frequency: Float, amplitude: Float)] = [
        (1.0, 0.55),
        (2.0, 0.28),
        (3.5, 0.18),
        (6.0, 0.10)
    ]

    public init(sampleCount: Int = 256, binCount: Int = 48) {
        self.sampleCount = max(2, sampleCount)
        self.binCount = max(1, binCount)
    }

    public func frame(at time: TimeInterval) -> VisualizationInput {
        let t = Float(time)

        // Slow tremolo so the overall level breathes over time.
        let envelope = 0.55 + 0.45 * sinf(t * 0.8)

        var samples = [Float](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            let phase = Float(i) / Float(sampleCount) * 2 * .pi
            var value: Float = 0
            for partial in partials {
                value += partial.amplitude * sinf(partial.frequency * (phase + t * 2.3))
            }
            samples[i] = max(-1, min(1, value * envelope))
        }

        var spectrum = [Float](repeating: 0, count: binCount)
        for bin in 0..<binCount {
            let f = Float(bin) / Float(binCount)
            // Bass-heavy tilt with a roaming resonance peak.
            let tilt = powf(1 - f, 1.8)
            let sweep = 0.5 + 0.5 * sinf(t * 1.3 + f * 6)
            spectrum[bin] = max(0, min(1, tilt * sweep * envelope))
        }

        let level = max(0, min(1, envelope * 0.9))
        return VisualizationInput(time: time, samples: samples, spectrum: spectrum, level: level)
    }
}
