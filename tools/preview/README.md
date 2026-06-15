# Headless preview renderer

A small Python tool that renders R4Viz scenes to images **without Xcode or a
Mac**, so the visuals can be checked from any machine (e.g. CI on Linux).

It is a faithful CPU port of the Swift `R4VizKit` math — `Matrix4` (perspective
+ transform stack), the `GL` primitives (`quad`/`cube`/`point`), the synthetic
beat-driven audio, and each scene's `render()` — kept 1:1 with the Swift so the
preview is representative. It is **not** used by the app; it exists only to
preview/validate the rendering logic.

> Because the logic is duplicated in Python, changes to a scene's render math
> should be mirrored here (and vice-versa) when you want an updated preview.

## Usage

```bash
pip install numpy Pillow
cd tools/preview
python3 render.py        # writes montage.png + medusa.gif + spinner.gif
```

- `r4core.py` — Matrix4 / GL / synthetic audio (mirrors `Math/`, `Engine/GL`, `Audio/`)
- `scenes.py` — the five scenes (mirrors `Scenes/`)
- `render.py` — montage + animated GIF harness
