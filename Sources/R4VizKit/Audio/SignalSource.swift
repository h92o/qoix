import Foundation

/// Produces an ``AudioFrame`` for a given point in time.
///
/// Conform a microphone tap or audio-file decoder to feed real audio into the
/// scenes. The scaffold ships with ``SyntheticSignalSource`` so the visualizer
/// reacts out of the box with no audio permissions.
public protocol SignalSource: AnyObject {
    var binCount: Int { get }
    func frame(at time: TimeInterval, timepass: TimeInterval) -> AudioFrame
}

/// A self-contained generator that fabricates a plausible, beat-driven audio
/// analysis. Serves as the reference for what a real source must emit.
public final class SyntheticSignalSource: SignalSource {

    public let binCount: Int
    private let bpm: Double
    private var lastBeatIndex: Int = -1

    private let partials: [(frequency: Float, amplitude: Float)] = [
        (1.0, 0.55), (2.0, 0.28), (3.5, 0.18), (6.0, 0.10)
    ]

    public init(binCount: Int = 64, bpm: Double = 120) {
        self.binCount = max(1, binCount)
        self.bpm = bpm
    }

    public func frame(at time: TimeInterval, timepass: TimeInterval) -> AudioFrame {
        let t = Float(time)

        // Beat envelope: a sharp attack on each beat that decays before the next.
        let beatPeriod = 60.0 / bpm
        let beatPhase = (time.truncatingRemainder(dividingBy: beatPeriod)) / beatPeriod
        let kick = Float(pow(max(0, 1 - beatPhase), 3))

        // A beat "fires" on the frame we cross into a new beat interval.
        let beatIndex = Int(time / beatPeriod)
        let beat = beatIndex != lastBeatIndex
        lastBeatIndex = beatIndex

        let envelope = 0.45 + 0.55 * kick
        let sounda = max(-1, min(1, (sinf(t * 2.3) * 0.4 + kick * 0.9) - 0.15))

        var spectrum = [Float](repeating: 0, count: binCount)
        for bin in 0..<binCount {
            let f = Float(bin) / Float(binCount)
            let tilt = powf(1 - f, 1.8)                       // bass-heavy
            let sweep = 0.5 + 0.5 * sinf(t * 1.3 + f * 6)     // roaming resonance
            spectrum[bin] = max(0, min(1, tilt * sweep * envelope + kick * tilt * 0.6))
        }

        return AudioFrame(time: time, timepass: timepass, sounda: sounda, spectrum: spectrum, beat: beat)
    }
}
