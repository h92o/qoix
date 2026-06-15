# qoix — R4Viz

A native **macOS + iOS** port of **R4**, the audio-reactive music visualizer by
Gordon Williams (RabidHamster). R4 originally ran on Windows via OpenGL and a
custom scene-scripting language; R4Viz brings its scene model to Apple platforms
with a single shared **SwiftUI** codebase.

> This repo does not redistribute R4's original binaries, textures, shaders, or
> scene scripts. The Swift here is an original reimplementation of the engine's
> ideas and of a few scenes. See [`docs/R4_ENGINE.md`](docs/R4_ENGINE.md).

## What's here

A working app *scaffold* built around R4's real architecture: audio-reactive
scenes drawn through an immediate-mode GL helper. A synthetic, beat-driven signal
generator drives the scenes out of the box, so the app reacts the moment it
launches — swap in a microphone or audio file later via one protocol.

```
Package.swift              SwiftPM manifest for the shared R4VizKit library + tests
project.yml                XcodeGen spec defining the macOS & iOS app targets
App/                       Shared SwiftUI app (one source set, both platforms)
  R4VizApp.swift             @main App entry point
  ContentView.swift          Full-bleed visualization + scene picker / pause
Sources/R4VizKit/          Reusable, platform-agnostic engine
  Audio/                     AudioFrame + SignalSource (synthetic beat generator)
  Scene/                     R4Scene protocol + SceneRegistry
  Scenes/                    Ported scenes: Spinner, Thumper, Cube Field, Spectrum, Medusa
  Module/                    R4Module + ModuleGraph + GraphScene (R4 Construct model)
  Overlay/                   R4Overlay post-FX: Blur, Scanlines, Spectrum, Strobe, RGB Split
  Fade/                      R4Fade transitions: Cross, Cut, Slide, Zoom
  Engine/                    GL immediate-mode helper + VisualizationEngine
  Math/                      Matrix4 (perspective/transform) + HSB color
  Views/                     VisualizationView (TimelineView + Canvas loop)
Tests/R4VizKitTests/       Unit tests for the engine, audio, math, scenes, graph
docs/R4_ENGINE.md          Notes on the original R4 engine being ported
```

## Architecture

```
SignalSource ─▶ AudioFrame ─▶ [Scene | ModuleGraph] ─▶ Fade ─▶ Overlay ─▶ Canvas
   (audio)      (time, sounda,   (one scene, or a       (scene   (post-FX)   (GPU)
                spectrum, beat)   graph of modules)     transition)
```

The per-frame pipeline: the engine renders the active scene (or, during a scene
change, a **fade** between the outgoing and incoming scenes) and wraps the result
in the active **overlay** post-processing pass.

- **`AudioFrame`** mirrors R4's reactive variables (`time`, `timepass`,
  `sounda`, spectrum, `beat`) so ported scenes read like the originals.
- **`GL`** is a tiny immediate-mode helper (matrix stack, perspective,
  `quad`/`cube`/`line`, color + additive blend) standing in for R4's `gl`
  module. It projects on the CPU and draws into a SwiftUI `Canvas`, so scenes are
  100% shared between macOS and iOS with no platform-specific drawing.
- **`R4Scene`** — each scene keeps a little state and draws one frame, exactly
  like an R4 `SCENE` script's `render()`.
- **`VisualizationEngine`** — the single `ObservableObject` the UI binds to:
  owns the registry, active selection, and play/pause.

### Add a scene

1. Create `Sources/R4VizKit/Scenes/MyScene.swift` conforming to `R4Scene`.
2. Add it to `SceneRegistry.makeDefault()`.

It appears in the picker automatically.

## Building

> **Note:** This is an Apple-platform (SwiftUI) project and must be built on
> macOS with Xcode. It does not compile on Linux.

```bash
# 1. Generate the Xcode project (defines the macOS + iOS app targets)
brew install xcodegen        # one-time
xcodegen generate

# 2. Open and run
open R4Viz.xcodeproj
#    pick the "R4Viz-macOS" or "R4Viz-iOS" scheme and Run (⌘R)
```

Run the engine unit tests from the command line via SwiftPM:

```bash
swift test
```

## Requirements

- macOS 12+ / iOS 15+
- Xcode 15+ (Swift 5.9)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the app project

## Credits

Original R4 visualizer © Gordon Williams (RabidHamster). This is an independent
reimplementation for educational/porting purposes.
