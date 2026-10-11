import Foundation

/// Works out, from successive readings of the system output volume, whether a hardware volume button was
/// pressed and which one.
///
/// A press moves the volume by one step (1/16 = 0.0625). After each press the observer puts the volume back
/// to its resting level, so `baseline` normally never changes. Small differences are treated as drift (for
/// example the echo of that restore) and simply adopted.
///
/// This type is pure logic with no UIKit or audio dependencies, so it is fully unit-tested.
struct VolumeButtonDetector {
    enum Press: Equatable {
        case up
        case down
    }

    /// The size of one hardware volume step on iPhone.
    static let hardwareStep: Float = 1.0 / 16.0

    /// A change at least this large counts as a button press. It is a little under half a step, so a press
    /// that is clipped at the very top or bottom of the range is still recognised.
    static let pressThreshold: Float = 0.03

    /// Whether pressing Volume Down at `volume` would change the volume enough to be noticed. At zero it
    /// cannot: the system has nowhere lower to go, so no change is reported at all.
    static func canDetectDownPress(atVolume volume: Float) -> Bool {
        volume >= pressThreshold
    }

    /// Whether pressing Volume Up at `volume` would change the volume enough to be noticed. At full volume it
    /// cannot: the system has nowhere higher to go.
    static func canDetectUpPress(atVolume volume: Float) -> Bool {
        volume <= 1 - pressThreshold
    }

    /// The level the volume is expected to rest at between presses.
    private(set) var baseline: Float

    init(baseline: Float) {
        self.baseline = baseline
    }

    /// Feeds in a new volume reading. Returns the press it represents, or nil if it is just drift.
    mutating func ingest(_ volume: Float) -> Press? {
        let delta = volume - baseline
        guard abs(delta) >= Self.pressThreshold else {
            baseline = volume
            return nil
        }
        return delta < 0 ? .down : .up
    }

    /// Adopts `volume` as the new resting level (used when the volume could not be put back).
    mutating func rebase(to volume: Float) {
        baseline = volume
    }
}
