# qoix — R4Viz

A native **macOS + iOS** scaffold for **R4**, originally a Win32 visualization
project. R4Viz brings the "pluggable visualizer" idea to Apple platforms with a
single shared codebase written in **SwiftUI**.

## What's here

This is a working app *scaffold* with a real plugin architecture, not just an
empty project. A synthetic signal generator drives the visualizers out of the
box, so the app animates the moment it launches — swap in a microphone or audio
file later by conforming to one protocol.

```
Package.swift              SwiftPM manifest for the shared R4VizKit library + tests
project.yml                XcodeGen spec defining the macOS & iOS app targets
App/                       Shared SwiftUI app (one source set, both platforms)
  R4VizApp.swift             @main App entry point
  ContentView.swift          Full-bleed visualization + control bar
Sources/R4VizKit/          Reusable, platform-agnostic engine
  Plugin/                    VisualizationPlugin protocol + PluginRegistry
  Data/                      VisualizationInput + SignalSource (synthetic generator)
  Plugins/                   Bundled visualizers (waveform, spectrum bars, particles)
  Engine/                    VisualizationEngine (observable, drives the UI)
  Views/                     VisualizationView (TimelineView + Canvas render loop)
Tests/R4VizKitTests/       Unit tests for the engine and signal source
```

## Architecture

```
SignalSource ──frame(at:)──▶ VisualizationInput ──▶ VisualizationPlugin.render ──▶ Canvas
     (data)                      (one frame)              (one visualizer)         (GPU)
```

- **`VisualizationPlugin`** — each visualizer is one small object that draws a
  frame into a SwiftUI `GraphicsContext`. Because everything renders through
  `Canvas`, plugins are GPU-accelerated and 100% shared between macOS and iOS
  with zero platform-specific drawing code.
- **`SignalSource`** — abstracts where data comes from. `SyntheticSignalSource`
  ships by default; conform a mic tap or file decoder to feed real audio.
- **`VisualizationEngine`** — the single `ObservableObject` the UI binds to:
  owns the registry, the active selection, and play/pause state.

### Add a new visualizer

1. Create `Sources/R4VizKit/Plugins/MyPlugin.swift` conforming to
   `VisualizationPlugin`.
2. Add it to `PluginRegistry.makeDefault()`.

That's it — it appears in the picker automatically.

## Building

> **Note:** This is an Apple-platform (SwiftUI) project and must be built on
> macOS with Xcode. It does not compile on Linux.

```bash
# 1. Generate the Xcode project (defines the macOS + iOS app targets)
brew install xcodegen        # one-time
xcodegen generate

# 2. Open and run
open R4Viz.xcodeproj
#    then pick the "R4Viz-macOS" or "R4Viz-iOS" scheme and Run (⌘R)
```

Run the engine unit tests from the command line via SwiftPM:

```bash
swift test
```

## Requirements

- macOS 12+ / iOS 15+
- Xcode 15+ (Swift 5.9)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the app project
