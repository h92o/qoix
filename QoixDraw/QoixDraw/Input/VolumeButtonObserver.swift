import AVFoundation
import MediaPlayer
import os
import UIKit

/// Turns the hardware volume buttons into events.
///
/// iOS has no supported "volume button pressed" callback for apps that are not capturing from the camera
/// (`AVCaptureEventInteraction` only delivers events to apps that are actively using the camera). So this uses
/// the long-standing workaround: watch `AVAudioSession.outputVolume`, compare it with the level we last saw,
/// and put the system volume back afterwards so repeated presses never run into 0 or 1.
///
/// A hidden `MPVolumeView` does two jobs: while one is on screen iOS does not draw its own volume overlay,
/// and its slider is the only way an app can set the system volume.
@MainActor
final class VolumeButtonObserver {
    enum Event: Equatable {
        case volumeDown
        case volumeUp
    }

    /// Called on the main thread for every press.
    var onEvent: ((Event) -> Void)?

    private static let log = Logger(subsystem: "app.qoix.draw", category: "volume")

    private let session: AVAudioSession
    private var detector: VolumeButtonDetector
    private var observation: NSKeyValueObservation?
    private var volumeView: MPVolumeView?
    private var settleUntil = Date.distantPast
    private(set) var isRunning = false

    init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
        self.detector = VolumeButtonDetector(baseline: session.outputVolume)
    }

    /// The current system output volume, 0...1.
    var currentVolume: Float {
        session.outputVolume
    }

    /// Starts listening. `host` must be on screen: the hidden volume view is added to it.
    func start(attachedTo host: UIView) {
        guard !isRunning else { return }
        isRunning = true

        do {
            // Ambient + mixWithOthers: we never play anything, and must not interrupt the user's music.
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            NSLog("QOIX Draw: could not activate the audio session: \(error)")
        }

        let view = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 120, height: 40))
        host.addSubview(view)
        view.layoutIfNeeded()
        volumeView = view

        // Activating the session can make the reported volume jump to its real value, so for a moment
        // readings are adopted rather than interpreted.
        detector = VolumeButtonDetector(baseline: session.outputVolume)
        settleUntil = Date().addingTimeInterval(0.6)
        Self.log.debug("listening; volume is \(self.detector.baseline, privacy: .public)")
        observation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let volume = change.newValue else { return }
            Task { @MainActor [weak self] in
                self?.handle(volume: volume)
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        observation?.invalidate()
        observation = nil
        volumeView?.removeFromSuperview()
        volumeView = nil
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Not fatal: iOS releases the session when the app is suspended anyway.
        }
    }

    private func handle(volume: Float) {
        guard isRunning else { return }
        if Date() < settleUntil {
            Self.log.debug("settling; adopted volume \(volume, privacy: .public)")
            detector.rebase(to: volume)
            return
        }
        let baseline = detector.baseline
        guard let press = detector.ingest(volume) else {
            Self.log.debug("volume \(volume, privacy: .public): drift or echo, no press")
            return
        }

        // Undo the press so the user's volume is untouched; if that is impossible, follow the new level.
        let restored = restoreVolume(to: detector.baseline)
        if !restored {
            detector.rebase(to: volume)
        }
        Self.log.debug("press \(String(describing: press), privacy: .public): \(baseline, privacy: .public) -> \(volume, privacy: .public), restored: \(restored, privacy: .public)")
        onEvent?(press == .down ? .volumeDown : .volumeUp)
    }

    private func restoreVolume(to level: Float) -> Bool {
        guard let view = volumeView, let slider = Self.findSlider(in: view) else { return false }
        slider.setValue(level, animated: false)
        return true
    }

    private static func findSlider(in view: UIView) -> UISlider? {
        if let slider = view as? UISlider {
            return slider
        }
        for subview in view.subviews {
            if let slider = findSlider(in: subview) {
                return slider
            }
        }
        return nil
    }
}
