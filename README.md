# qoix

A repository of idea stuff.

## Keyboard Sample Player

Turn your computer keyboard into a sample player: every key is bound to an
audio sample, and pressing the key triggers it. A window shows the live
keyboard so you can see what each key plays and which keys are sounding.

It works out of the box — with **no sample files of your own** it generates a
built-in synth note bank and lays the keyboard out as a playable piano. Drop in
your own sounds when you want a drum kit or custom set.

### Install & run

```bash
pip install -r requirements.txt      # just pygame
python3 keyboard_sample_player.py     # synth piano mode
```

### Use your own samples

```bash
# Auto-assign every audio file in a folder to keys (a, s, d, f, ...):
python3 keyboard_sample_player.py --samples my_kit/

# ...or curate the layout with a mapping.json in that folder:
#   { "a": "kick.wav", "s": "snare.wav", "d": "hat.wav" }
```

See [`samples/README.md`](samples/README.md) for the three mapping modes
(explicit `mapping.json`, auto-assigned loose files, synth fallback).

### Controls

| Key | Action |
| --- | --- |
| any mapped key | play its sample |
| `Shift+Z` / `Shift+X` | (piano mode) octave down / up |
| `-` / `=` | master volume down / up |
| `Esc` / close window | quit |

### Command-line options

```
--samples DIR    folder with audio files / mapping.json (default: samples)
--octave N       base octave for synth piano mode (default: 4)
--channels N     max simultaneous voices / polyphony (default: 32)
--list           print the key mapping and exit (no window or audio needed)
```

Preview a mapping without launching the window or needing pygame:

```bash
python3 keyboard_sample_player.py --list
```

### Files

| File | Purpose |
| --- | --- |
| `keyboard_sample_player.py` | main application (pygame: audio + window + keys) |
| `tone_generator.py` | pure-stdlib WAV synth that bootstraps the note bank |
| `samples/` | your audio files / `mapping.json` go here |
| `requirements.txt` | Python dependencies (`pygame`) |

### How it works

- **Audio** is handled by `pygame.mixer` with a pool of channels, so notes and
  hits overlap polyphonically instead of cutting each other off.
- **Keys** are read from the pygame event loop using `pygame.key.name(...)`,
  which is what `mapping.json` keys are matched against.
- **The synth fallback** renders each note with light additive synthesis and an
  ADSR envelope via Python's standard `wave` module — no numpy required.
