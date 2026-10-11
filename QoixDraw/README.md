# QOIX Draw

An iPhone app for **calligraphy with your finger**.

- **Touch the screen to draw.** The pen has a real *nib shape*, so lines get thick and thin the way they do with a
  broad-edge pen or a brush.
- **Press Volume Down to save** the picture to your Photos.
- **Press Volume Up to change the ink** (ink black, vermilion, indigo, sepia, forest, gold, white). A small swatch
  shows which one you are on.
- **Shake the phone** for a menu: **Save to Photos** (a second way to save, in case a volume button isn't an option),
  undo, redo, **Clear Canvas** (to throw a drawing away without saving it), and **Brush & Color…**, the sheet where
  you choose and tune the pen. A three-finger swipe left/right is undo/redo too.
- Pictures are PNGs, never larger than **2000 × 2000 px**. The canvas takes the shape of your screen at the
  largest size allowed (about 923 × 2000 on a current iPhone). After a save the canvas clears for the next picture;
  undo brings a just-saved drawing back.

## The pen

A pen tip is a *shape* dragged along your finger's path. What ends up on the paper is everything the shape swept
over, so the line's width depends on the **direction** you move relative to the tip. That is the whole secret of
calligraphy:

- **Flat (chisel) nib**, held at an angle, say 45°: move across its edge and the line is as wide as the edge;
  move along the edge and it is a hairline. Verticals are thick, one diagonal is thin: the italic and gothic look.
- **Oval nib**: the same rhythm with softer transitions.
- **Round brush**: no direction, but it responds to **speed** (slow strokes swell, fast ones thin out), starts in
  a point, and **trails off in a tail** when you lift your finger.
- **Pointed pen**: a fine line that swells when you slow down, with a flick at the end.

The built-in pens, in the order the sheet lists them:

| Pen | Tip | Feel |
| --- | --- | --- |
| Chisel 45° *(default)* | flat, 12 pt, hairline 1.2 pt, 45° | classic italic/gothic thick-thin |
| Chisel 30° | flat, 12 pt, 30° | flatter, more horizontal thick strokes |
| Oval 35° | oval 13 × 4 pt, 35° | softer thick-thin |
| Brush | round, 9 pt | speed-sensitive, pointed start, short flick at the end |
| Pointed pen | round, 5.5 pt | fine, swells when slow, flick at the end |
| Marker | round, 4 pt | constant width |

**Brush & Color** (shake, then the last menu entry) shows a live specimen drawn by the real engine and lets you tune:
tip shape (flat/oval), **size**, **edge thickness**, **angle**, **smoothing** (how far the pen trails behind your
finger: more smoothing turns finger wobble into fluid curves), **speed sensitivity** and **finger pressure** (how much
a harder, wider touch fattens the line), plus the ink. Your choice is remembered between launches.

Under the hood the swept area is filled as **one anti-aliased shape**, so the edges stay clean however slowly or
quickly you draw. Because a drawing is stored as its strokes (points, timing, pen), undo repaints the exact same
pixels.

**One finger writes at a time.** While a stroke is in progress, other fingers touching the screen (the knuckle of
the writing hand, a thumb holding the phone) are ignored, so they can't leave stray marks. A finger resting on the
screen without moving never draws either. Both are settings in `AppConfig.swift`.

What a finger can't do: an iPhone has no pressure sensor, so "finger pressure" uses the size of the contact patch,
which is only a rough stand-in and varies between phones. And your finger covers the spot where the nib touches. If
that bothers you, an **offset nib** (the ink appears slightly above your fingertip) is an obvious next step.

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

The Simulator has no volume buttons: use **Device ▸ Shake** and pick **Save to Photos** (or **Brush & Color…**).
With a hardware keyboard attached, ⌘S saves, ⌘N starts a new canvas, ⌘B opens Brush & Color and ⌘Z undoes.

**No Mac?** Every successful run of the GitHub Actions workflow also produces an *unsigned* `QoixDraw-unsigned.ipa`
(Actions ▸ the latest green run ▸ Artifacts ▸ `QoixDraw-unsigned-ipa`). It can't be installed as it is: a sideloading
tool such as Sideloadly or AltStore signs it with your own Apple ID and installs it on your iPhone (with a free
Apple ID the app has to be re-installed every 7 days). That route has not been tried from here, so treat it as a
starting point.

## The volume buttons: how they work, and their limits

iOS has no supported "volume button pressed" callback for ordinary apps. Apple's `AVCaptureEventInteraction`
exists, but it only delivers events to apps that are actively using the camera. So the app uses the long-standing
workaround: it watches the system volume, notices the step up or down, acts (saves, or changes the ink), and puts
the volume back where it was. A hidden volume view keeps iOS from drawing its own volume overlay.

What that means in practice:

- **If the volume is at zero, Volume Down can't be detected, and at full volume Volume Up can't** (the system has
  nowhere further to go). The app tells you once and asks you to move the volume one notch. It never changes your
  volume on its own.
- The volume is restored after each press, so repeated presses never drift it.
- The Simulator can't change volume at all, hence the shake menu's Save to Photos there.
- It is a workaround, so it could be affected by a future iOS release. Apple may also not accept it in an App Store
  review. It is fine for your own phone and TestFlight-style testing.

**If a button seems to do nothing**, set `showVolumePressMessages = true` in `AppConfig.swift` and run from
Xcode. The app then shows "Volume Down detected" / "Volume Up detected" on every press, and the console (filter for
`app.qoix.draw`) logs each volume reading it sees, which pinpoints whether the press was seen, ignored, or not
reported at all. Either way, **Save to Photos** in the shake menu always works.

Where drawings go: **Photos** (add-only access, the app can't read your pictures). If Photos access is denied, the
drawing is kept in the **Files** app instead (On My iPhone ▸ QOIX Draw) so nothing is ever lost.

## Settings you may want to change

- [`AppConfig.swift`](QoixDraw/AppConfig.swift): the pen a fresh install starts with, how far a finger must move
  before it starts drawing (so a resting thumb never marks the canvas), how many fingers may write at once, canvas
  background, whether the canvas clears after a save, and the canvas shape (screen-shaped by default; return
  `CanvasSpec(width: 2000, height: 2000)` for a fixed square). The 2000 px ceiling itself lives in
  [`Canvas/CanvasSpec.swift`](QoixDraw/Canvas/CanvasSpec.swift), the one place that enforces it.
- [`Brush/BrushPreset.swift`](QoixDraw/Brush/BrushPreset.swift): the built-in pens. Add your own by copying one and
  changing the numbers, then list it in `BrushPreset.all`.
- [`Brush/Palette.swift`](QoixDraw/Brush/Palette.swift): the inks Volume Up steps through.
- [`Canvas/StrokeBuilder.swift`](QoixDraw/Canvas/StrokeBuilder.swift): how the pen follows the finger and how the
  tip reacts to speed and pressure (the constants at the top; the amount of smoothing itself is per pen).

## How it is built

```
QoixDraw/
  QoixDraw.xcodeproj      Xcode project (folders are synchronized: new .swift files join the app automatically)
  Config/Info.plist       the few Info.plist keys that can't be set as build settings
  QoixDraw/               the app
    Brush/                pens (presets), inks (palette), the remembered choice
    Canvas/               canvas size rules, strokes, nib geometry, stroke smoothing, the pixel painter
    Input/                volume-button detection (pure logic + the iOS glue)
    Saving/               PNG encoding, Photos, Files fallback
    UI/                   canvas view (touches, undo), screen controller, toast, brush sheet
    AppConfig.swift       tunables
  QoixDrawTests/          unit tests
```

The drawing is stored as **strokes** (the points your finger passed through, with timing, and the pen used), and the
pixels on screen are only a cache of them. That is what makes undo/redo exact, and it keeps the door open for saving
drawings to edit later, exporting at other sizes, or replaying a drawing as a time-lapse.

Painting a stroke: `StrokeBuilder` turns finger samples into pen positions (smoothing, speed and pressure sizing,
tapers), then `StrokeSession` fills the union of the convex hulls of the tip at neighboring positions, which is
exact for any convex tip. Finished stretches are baked into the picture while the rest is redrawn each frame into a
small transparent patch that floats over just that part of the canvas, so drawing stays fast even on a 2000 px
canvas.

## Ideas for what's next

Nothing below is built yet; each one fits the current structure without a rewrite.

- **Nib offset**: draw slightly above the fingertip so the nib is visible while you write.
- **Zoom and pan** (two fingers) so fine detail can be drawn on the 2000 px canvas; one finger keeps drawing.
- **Canvas size choice** up to 2000 × 2000 (square, screen-shaped, custom). The cap is already enforced centrally.
- **Guide lines** for lettering (baseline, x-height, slant) that show on screen but not in the saved picture.
- **Your own pens**: save tuned pens by name, import/export them.
- **Paper and ink character**: paper tints, ink that pools where you pause, dry-brush edges.
- **Gallery and re-editing**: save the strokes next to each PNG (they are already `Codable`), then reopen and keep
  drawing, or export again at a different size.
- **Time-lapse export** (replay the strokes), **transparent-background PNG**, **share sheet**, **a "QOIX Draw" album**
  in Photos.

## Tests and CI

`xcodebuild test -project QoixDraw/QoixDraw.xcodeproj -scheme QoixDraw -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO`
runs the unit tests: the canvas size cap, the calligraphy engine (a flat nib really is hairline-thin along its edge
and full width across it, speed and tapers behave, a live stroke and its replay are pixel-identical), pens and inks,
touch handling, undo/redo, volume-press detection, and the whole save flow with a fake photo library. The UI
tests (`QoixDrawUITests`) launch the real app, draw with touches (a house, and a "nib rose": lines in twelve
directions, which shows the thick/thin effect), open the Brush & Color sheet, save with ⌘S and take screenshots.
GitHub Actions runs all of it on every push that touches `QoixDraw/` (Xcode 26 and Xcode 16.4, see
`.github/workflows/ios.yml`), plus an unsigned Release build for a real device, and keeps the screenshots as a
downloadable build artifact.

Not yet checked on a real iPhone: how the pen *feels* under a finger (smoothing, latency, the finger-pressure
estimate), and the Volume Up/Down detection. Both are best judged by trying them, then adjusting the numbers above.
