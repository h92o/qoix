# R4 engine notes

Background notes on the original **R4** visualizer by Gordon Williams
(RabidHamster), reconstructed by inspecting the v1.25 Windows build. These notes
explain *what we're porting* and why the Swift scaffold is shaped the way it is.

> The original R4 is a separately distributed Windows application. This repo does
> **not** redistribute R4's binaries, textures, shaders, or scene scripts — the
> Swift code here is an original reimplementation of the engine's ideas and of a
> handful of scenes.

## What R4 is

R4 is a real-time, audio-reactive music visualizer for Windows. It renders
through OpenGL and ships hundreds of **scenes** authored in a small C-like
scripting language, plus **overlays** (post-processing passes) and **fades**
(scene-to-scene transitions). Scenes react to the playing audio.

## Scene scripts

Each scene is a `SCENE ( ... )` declaration listing module instances, followed by
`init()`, `reset()`, and `render()` functions. A representative scene wires up a
solid background, one or more textures, and a `GL` module, then draws with
immediate-mode calls:

- `gl.gltranslate / glrotate / glscale` — model-view transforms
- `gl.glcolor`, `gl.glbindtexture`
- `gl.glbegin(gl_quads) ... gl.glvertex / gl.gltexcoord ... gl.glend()`

Other modules provide higher-level effects: cubes, tunnels, particle systems,
point/water morphs, metaballs, MD2 model playback, video capture/playback, flash,
and more.

### Reactive variables

Scenes read a handful of engine-provided values each frame:

| R4 variable            | Meaning                                  | Scaffold equivalent          |
| ---------------------- | ---------------------------------------- | ---------------------------- |
| `time`                 | continuous seconds                       | `AudioFrame.time`            |
| `timepass`             | seconds since last frame (delta)         | `AudioFrame.timepass`        |
| `sounda`               | overall amplitude (~`-1..1`)             | `AudioFrame.sounda`          |
| `specleft[]` / `specright[]` | per-bin spectrum magnitudes        | `AudioFrame.spectrum` + `band(_:_:)` |
| beat / kick            | bass impulse used to "thump" objects     | `AudioFrame.beat`            |

### Shaders

R4 shaders are short strings of single-character commands separated by `;`,
configuring fixed-function GL state — e.g. depth test, wireframe, blend func,
texture binding/coordinate generation, level-of-detail, color, and face culling.
Common blends: `B10` (replace), `BAa` (alpha blend), `B11` (additive),
`Bcc` (invert). The scaffold reproduces the blend modes it needs
(`GL.additiveBlend()` / `normalBlend()`); full shader-string parsing is left as a
follow-up.

### Overlays and fades

R4 also has **overlays** (post-processing passes drawn over the scene — blur,
mirror, RGB split, scanlines, spectrum, strobe…) and **fades** (transitions
between scenes — cross-fade, slide, zoom, cube…). The scaffold implements both as
small protocols:

- `R4Overlay.composite` receives the scene as a closure and decides how to draw
  it — pass-through, into a filtered layer (`Blur`, `RGB Split`), or with
  decoration on top (`Scanlines`, `Spectrum`, `Strobe`).
- `R4Fade.render` blends an outgoing and incoming scene by a progress `t`
  (`Cross`, `Cut`, `Slide`, `Zoom`). The engine starts a fade whenever the
  selected scene changes.

## Scenes as module graphs (R4 Construct)

R4 also shipped **R4 Construct**, a Java GUI scene designer. It reveals that a
scene is really a **graph of modules** wired together, which the tool compiles to
an `.r4` scene script.

- Each module has typed **inputs** (buffer handles), user-editable **functions**
  (parameters), and one or more **output** module names — the last module in the
  chain is the displayed output.
- A module contributes lines to four code **sections**: the top-level `MODULE`
  declaration, plus `init` / `reset` / `render`. For example a *Solid* module
  declares `SOLID m();` and emits `m.col = rgb(r, g, b);` into `init`; a *Medusa*
  module declares `MEDUSA m(in1, in2);` and emits `m.kick = sounda;` into
  `render`; a *Point Morph* module drives `m.speed` from the sound each frame.
- Modules chain background → effect → … → output (a buffer flows from one
  module's output into the next module's input).

The scaffold implements this directly: `R4Module` (with `inputs`) + `ModuleGraph`
flatten a graph into back-to-front render order, and `GraphScene` adapts a graph
to the `R4Scene` interface. Bundled modules: `Solid`, `Medusa`, `CubeField`; two
registry scenes (`graph-medusa`, `graph-cubefield`) are built this way. A full
text-`.properties`-driven compiler (as R4 Construct uses) is a natural follow-up.

### Preset packs

R4's scene library was extended by community preset packs (e.g. the **Rovastar**
pack of scenes, fades, and overlays) dropped into `data/predefine` as `.r4`
scripts. The scaffold does not redistribute those scripts; they are noted here
only to describe how R4's library grew.

## What the scaffold reimplements

The Swift port keeps the parts that define R4's feel:

- The **reactive variable model** above (`AudioFrame`).
- An **immediate-mode `GL` helper** (matrix stack, perspective projection,
  `quad` / `cube` / `line`, color + additive blend) that mirrors how scene
  scripts draw.
- A few scenes reinterpreted from the originals: **Spinner**, **Thumper /
  Bass Cube**, **Cube Field**, **Spectrum Cylinder**, and **Medusa**.

Not yet ported (candidates for follow-up): textured assets, the scene-script
interpreter, the module-graph compiler (à la R4 Construct), overlays/fades, and
the tunnel / point-morph / water-morph module families.
