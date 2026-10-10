# QOIX Draw

A tiny iPhone drawing app.

- **Touch the screen to draw.**
- **Press Volume Down to save** the picture to your Photos.
- Pictures are PNGs, never larger than **2000 × 2000 px**. The canvas takes the shape of your screen at the
  largest size allowed (about 923 × 2000 on a current iPhone).
- After a save the canvas clears for the next picture. **Shake the phone to undo**, which also brings the
  saved drawing back. A three-finger swipe left/right is undo/redo too.

## Run it on your iPhone

You need a Mac with **Xcode 16 or newer** and an iPhone on **iOS 16 or newer**.

1. Open `QoixDraw/QoixDraw.xcodeproj` in Xcode.
2. Select the **QoixDraw** target, then **Signing & Capabilities**, and choose your **Team** (a free Apple ID
   works). If Xcode says the bundle identifier is already taken, change `app.qoix.draw` to something unique.
3. Plug in the iPhone, pick it as the run destination, press ▶.
   First time only: turn on **Settings ▸ Privacy & Security ▸ Developer Mode**, and trust your developer
   profile under **Settings ▸ General ▸ VPN & Device Management**.
4. Draw, then press Volume Down. Allow **Add Photos Only** when asked.

The Simulator has no volume buttons, so there **⌘S saves**, ⌘N starts a new canvas, and ⌘Z undoes
(Device menu ▸ Shake also works).

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

## Tests and CI

`xcodebuild test -project QoixDraw/QoixDraw.xcodeproj -scheme QoixDraw -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO`
runs the unit tests (canvas size cap, painting, undo/redo, volume-press detection, the whole save flow with a fake
photo library). GitHub Actions does the same on every push that touches `QoixDraw/`
(see `.github/workflows/ios.yml`), plus an unsigned Release build for a real device.
