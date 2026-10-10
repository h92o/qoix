# QOIX Draw

A tiny iPhone drawing app.

- **Touch the screen to draw.**
- **Press Volume Down to save** the picture to your Photos.
- Pictures are PNGs, never larger than **2000 × 2000 px**. The canvas takes the shape of your screen at the
  largest size allowed (about 923 × 2000 on a current iPhone).
- After a save the canvas clears for the next picture. **Shake the phone** for a small menu: undo, redo, or
  **Clear Canvas** (to throw a drawing away without saving it). Undo also brings a just-saved drawing back, and a
  three-finger swipe left/right is undo/redo too.

## Run it on your iPhone

You need a Mac with **Xcode 16 or newer** and an iPhone on **iOS 16 or newer**.

1. Get the code on your Mac: `git clone -b claude/iphone-drawing-app-cx7e9a https://github.com/h92o/qoix.git`
   (or download that branch as a ZIP from GitHub), then open `QoixDraw/QoixDraw.xcodeproj` in Xcode.
2. Select the **QoixDraw** target, then **Signing & Capabilities**, and choose your **Team** (a free Apple ID
   works). If Xcode says the bundle identifier is already taken, change `app.qoix.draw` to something unique.
3. Plug in the iPhone, pick it as the run destination, press ▶.
   First time only: turn on **Settings ▸ Privacy & Security ▸ Developer Mode**, and trust your developer
   profile under **Settings ▸ General ▸ VPN & Device Management**.
4. Draw, then press Volume Down. Allow **Add Photos Only** when asked.

The Simulator has no volume buttons, so there **⌘S saves**, ⌘N starts a new canvas, and ⌘Z undoes
(Device ▸ Shake opens the shake menu).

## Volume Down: how it works, and its limits

iOS has no supported "volume button pressed" callback for ordinary apps. Apple's `AVCaptureEventInteraction`
exists, but it only delivers events to apps that are actively using the camera. So the app uses the long-standing
workaround: it watches the system volume, notices the step down, saves, and puts the volume back where it was.
A hidden volume view keeps iOS from drawing its own volume overlay.

What that means in practice:

- **If the volume is at zero, Volume Down can't be detected** (the system has nowhere lower to go). The app tells
  you once and asks you to raise it one notch. It never changes your volume on its own.
- The volume is restored after each press, so repeated saves never drift it down.
- The Simulator can't change volume at all, hence ⌘S there.
- It is a workaround, so it could be affected by a future iOS release. Apple may also not accept it in an App Store
  review. It is fine for your own phone and TestFlight-style testing.

**If Volume Down seems to do nothing**, set `showVolumePressMessages = true` in `AppConfig.swift` and run from
Xcode. The app then shows "Volume Down detected" on every press, and the console (filter for `app.qoix.draw`)
logs each volume reading it sees, which pinpoints whether the press was seen, ignored, or not reported at all.

Where drawings go: **Photos** (add-only access, the app can't read your pictures). If Photos access is denied, the
drawing is kept in the **Files** app instead (On My iPhone ▸ QOIX Draw) so nothing is ever lost.

## Settings you may want to change

Everything tunable is in [`QoixDraw/AppConfig.swift`](QoixDraw/AppConfig.swift): pen color and thickness, canvas
background, whether the canvas clears after a save, and the canvas shape (screen-shaped by default; return
`CanvasSpec(width: 2000, height: 2000)` for a fixed square). The 2000 px ceiling itself lives in
[`Canvas/CanvasSpec.swift`](QoixDraw/Canvas/CanvasSpec.swift), the one place that enforces it.

## How it is built

```
QoixDraw/
  QoixDraw.xcodeproj      Xcode project (folders are synchronized: new .swift files join the app automatically)
  Config/Info.plist       the few Info.plist keys that can't be set as build settings
  QoixDraw/               the app
    Canvas/               canvas size rules, strokes, the document, the pixel painter
    Input/                volume-button detection (pure logic + the iOS glue)
    Saving/               PNG encoding, Photos, Files fallback
    UI/                   canvas view (touches, undo), screen controller, toast
    AppConfig.swift       tunables
  QoixDrawTests/          unit tests
```

The drawing is stored as **strokes** (the points your finger passed through), and the pixels on screen are only a
cache of them. That is what makes undo/redo exact, and it keeps the door open for saving drawings to edit later,
exporting at other sizes, or replaying a drawing as a time-lapse.

## Ideas for what's next

Nothing below is built yet; each one fits the current structure without a rewrite.

- **Colors and brush size without any buttons**: Volume Up cycles the color, a long-press opens a small palette.
- **Zoom and pan** (two fingers) so fine detail can be drawn on the 2000 px canvas; one finger keeps drawing.
- **Canvas size choice** up to 2000 × 2000 (square, screen-shaped, custom). The cap is already enforced centrally.
- **Eraser**, and other undo gestures (the model already has full undo/redo).
- **Gallery and re-editing**: save the strokes next to each PNG (they are already `Codable`), then reopen and keep
  drawing, or export again at a different size.
- **Symmetry/kaleidoscope drawing**, **time-lapse export** (replay the strokes), **JPEG/HEIC/share sheet**,
  **a "QOIX Draw" album** in Photos, a **sound or haptic** on save.

## Tests and CI

`xcodebuild test -project QoixDraw/QoixDraw.xcodeproj -scheme QoixDraw -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO`
runs the unit tests (canvas size cap, painting, undo/redo, volume-press detection, the whole save flow with a fake
photo library). A UI test (`QoixDrawUITests`) launches the real app, draws a picture with touches, saves it with ⌘S
and takes screenshots. GitHub Actions runs all of it on every push that touches `QoixDraw/` (Xcode 26 and Xcode 16.4,
see `.github/workflows/ios.yml`), plus an unsigned Release build for a real device, and keeps the screenshots as a
downloadable build artifact.
