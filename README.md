# QOIX Synthesizer

A polyphonic software synthesizer built on the Web Audio API, shipped as a
desktop app via Electron and as a single self-contained HTML file.

Five sound engines feeding one shared effects chain:

| Engine | What it is |
|---|---|
| **Subtractive** | Three oscillators with per-oscillator unison, filters, osc-to-osc FM and ring/sub/XOR mix modes, plus noise |
| **FM** | DX7-style four-operator FM across eight algorithms |
| **Wavetable / Oxford** | Morphing wavetable bank, plus an OSCar-style 16-harmonic additive oscillator |
| **Spectral / FrFT** | Chirp oscillators on Hermite–Gaussian waves with an eigenspace mixer |
| **Mod matrix** | 8 sources × 12 destinations, bipolar amounts |

Also: a MIDI-file offline renderer that exports 16/24-bit or 32-bit float WAV,
a session recorder, a scale-aware random note generator, and Scala `.scl`
microtonal tuning.

## Running it

```bash
npm install
npm start          # desktop app
npm run dev        # …with DevTools
```

No install needed for a quick look — open `qoix-standalone.html` in any
Chromium-based browser.

```bash
npm run standalone   # regenerate that file from index.html + styles.css + js/
```

## Playing

| Input | Action |
|---|---|
| `A W S E D F T G Y H U J` | One octave of the keyboard |
| `K O L P ; '` | Continues into the next octave |
| `Z` / `X` | Octave down / up |
| `Space` | Panic — all notes off |
| Click and drag the piano | Glissando; vertical position sets velocity |
| Double-click any slider | Reset it to its default |

A connected MIDI controller is picked up automatically, including note
velocity, pitch bend (±2 semitones), the mod wheel (CC1), channel volume
(CC7), the sustain pedal (CC64) and all-notes-off (CC120/123).

## Tests

```bash
npm test           # engine + parser unit tests against a Web Audio mock
npm run test:browser   # renders real audio in Chromium (skips if unavailable)
npm run test:all
```

`test/run.js` runs the audio engines against `test/audio-mock.js`, which
records every node connection and every AudioParam automation call — so the
tests can assert on the graph that gets built, not just on return values.
`test/browser.js` goes further and checks the audio itself: that each effect
measurably changes the signal, and that the master bus stays inside full
scale.

## Building installers

See [BUILD.md](BUILD.md).

## Layout

```
index.html            markup for the whole UI
styles.css
js/synth.js           core engine: voices, effect chain, mod buses
js/fm.js              4-operator FM
js/wavetable.js       wavetable + Oxford additive
js/spectralfft.js     chirp / FrFT engine
js/modmatrix.js       modulation routing
js/microtonal.js      Scala .scl parsing and tuning
js/randomgen.js       scale-aware note generator
js/renderer.js        MIDI parsing, offline render, WAV encoding
js/recorder.js        session record and playback
js/presets.js         factory patches
js/ui.js              all UI wiring
main.js / preload.js  Electron shell
tools/                standalone bundler
test/                 unit and browser tests
```

## Licence

See [LICENSE](LICENSE).
