import UIKit

/// The app's one screen: a full-screen canvas. Volume Down saves the drawing.
final class CanvasViewController: UIViewController {
    private var canvasView: CanvasView?
    private let toast = ToastView()
    private let volumeObserver = VolumeButtonObserver()
    private let saver: DrawingSaver
    private let haptics = UINotificationFeedbackGenerator()

    private var isSaving = false
    private var lastSaveRequest = Date.distantPast
    private var hasShownLowVolumeHint = false
    private var hasShownPhotosDeniedAlert = false

    init(saver: DrawingSaver = DrawingSaver()) {
        self.saver = saver
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.1, alpha: 1)
        view.isMultipleTouchEnabled = true

        volumeObserver.onEvent = { [weak self] event in
            self?.handleVolumeEvent(event)
        }

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(appDidBecomeActive),
                           name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(appWillResignActive),
                           name: UIApplication.willResignActiveNotification, object: nil)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        installCanvasIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
        startListeningForVolumeButtons()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        volumeObserver.stop()
    }

    /// The canvas is created once, the first time the screen has a size, so it can take the screen's shape.
    private func installCanvasIfNeeded() {
        guard canvasView == nil, view.bounds.width > 0, view.bounds.height > 0 else { return }
        let spec = AppConfig.canvasSpec(forViewSize: view.bounds.size)
        guard let canvas = CanvasView(canvas: spec) else {
            NSLog("QOIX Draw: could not allocate a \(spec.width) x \(spec.height) canvas")
            return
        }
        canvas.frame = view.bounds
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(canvas, at: 0)
        canvasView = canvas
    }

    // MARK: Responder chain (shake-to-undo, key commands)

    override var canBecomeFirstResponder: Bool {
        true
    }

    /// Hooking the canvas's history in here is what makes shake-to-undo and the three-finger undo/redo
    /// gestures work with no extra UI.
    override var undoManager: UndoManager? {
        canvasView?.history
    }

    /// Handy in the Simulator (which has no volume buttons): ⌘S saves, ⌘N starts a new canvas.
    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(title: "Save to Photos", action: #selector(saveCommand), input: "s", modifierFlags: .command),
            UIKeyCommand(title: "New Canvas", action: #selector(newCanvasCommand), input: "n", modifierFlags: .command),
        ]
    }

    @objc private func saveCommand() {
        saveDrawing()
    }

    @objc private func newCanvasCommand() {
        canvasView?.startNewCanvas()
    }

    // MARK: Volume buttons

    @objc private func appDidBecomeActive() {
        if view.window != nil {
            startListeningForVolumeButtons()
        }
    }

    @objc private func appWillResignActive() {
        volumeObserver.stop()
    }

    private func startListeningForVolumeButtons() {
        volumeObserver.start(attachedTo: view)
        showLowVolumeHintIfNeeded()
    }

    /// At zero volume, pressing Volume Down changes nothing, so the press can't be seen. Say so, once.
    private func showLowVolumeHintIfNeeded() {
        guard !hasShownLowVolumeHint,
              !VolumeButtonDetector.canDetectDownPress(atVolume: volumeObserver.currentVolume) else { return }
        hasShownLowVolumeHint = true
        toast.show("Volume is at minimum. Raise it one notch so Volume Down can save.", in: view, duration: 4.5)
    }

    private func handleVolumeEvent(_ event: VolumeButtonObserver.Event) {
        switch event {
        case .volumeDown:
            saveDrawing()
        case .volumeUp:
            break // Not assigned yet.
        }
    }

    // MARK: Saving

    /// Saves the current drawing. Called for Volume Down (and ⌘S in the Simulator).
    func saveDrawing() {
        guard let canvasView else { return }
        let now = Date()
        guard !isSaving, now.timeIntervalSince(lastSaveRequest) > AppConfig.saveCooldown else { return }
        guard !canvasView.drawing.isEmpty else {
            toast.show("Draw something first", in: view)
            return
        }
        guard let image = canvasView.makeSnapshot() else {
            toast.show("Couldn't save the drawing", in: view, duration: 3)
            return
        }

        isSaving = true
        lastSaveRequest = now
        saver.save(image: image, date: now) { [weak self] result in
            self?.finishSaving(result)
        }
    }

    private func finishSaving(_ result: Result<SaveOutcome, SaveError>) {
        isSaving = false
        switch result {
        case .success(let outcome):
            haptics.notificationOccurred(.success)
            flash()
            switch outcome {
            case .savedToPhotos:
                toast.show("Saved to Photos", in: view)
            case .savedToFiles(_, let photosAccessDenied):
                toast.show("Saved to Files (Photos access is off)", in: view, duration: 3)
                if photosAccessDenied {
                    offerPhotosSettings()
                }
            }
            if AppConfig.startNewCanvasAfterSave {
                canvasView?.startNewCanvas()
            }
        case .failure:
            haptics.notificationOccurred(.error)
            toast.show("Couldn't save the drawing", in: view, duration: 3)
        }
    }

    /// A brief wash over the screen, like a camera shutter, so a save is unmistakable.
    private func flash() {
        let overlay = UIView(frame: view.bounds)
        overlay.isUserInteractionEnabled = false
        overlay.backgroundColor = UIColor(white: 0.5, alpha: 0.45)
        view.addSubview(overlay)
        UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseOut], animations: {
            overlay.alpha = 0
        }, completion: { _ in
            overlay.removeFromSuperview()
        })
    }

    private func offerPhotosSettings() {
        guard !hasShownPhotosDeniedAlert else { return }
        hasShownPhotosDeniedAlert = true
        let alert = UIAlertController(
            title: "Photos access is off",
            message: "Your drawing was saved in the Files app (On My iPhone, QOIX Draw). To save to Photos instead, "
                + "allow \"Add Photos Only\" for QOIX Draw in Settings.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        alert.addAction(UIAlertAction(title: "Not Now", style: .cancel))
        present(alert, animated: true)
    }
}
