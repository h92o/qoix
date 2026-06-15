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

## What the scaffold reimplements

The Swift port keeps the parts that define R4's feel:

- The **reactive variable model** above (`AudioFrame`).
- An **immediate-mode `GL` helper** (matrix stack, perspective projection,
  `quad` / `cube` / `line`, color + additive blend) that mirrors how scene
  scripts draw.
- A few scenes reinterpreted from the originals: **Spinner**, **Thumper /
  Bass Cube**, **Cube Field**, and **Spectrum Cylinder**.

Not yet ported (candidates for follow-up): textured assets, the scene-script
interpreter, overlays/fades, and the tunnel / particle / morph module families.
