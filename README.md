# qoix — Keyboard Sample Player

A repository of idea stuff.

## Web App (GitHub Pages)

**Live page:** `https://h92o.github.io/qoix/`

Open the page, press keys on your computer keyboard to play. No install needed —
everything runs in the browser using the Web Audio API.

**Three modes, chosen automatically:**

| Mode | How it activates |
|---|---|
| **Synth piano** | Default — no samples needed. Classic two-octave tracker layout with additive-synth ADSR tones |
| **Repo samples** | Add audio files + a `samples/mapping.json` to this repo; the page fetches and loads them |
| **Drag & drop** | Drop audio files onto any key tile (or anywhere on the page) to load your own samples live |

### Web controls

| Key / action | Effect |
|---|---|
| any highlighted key | play its sample / note |
| `Shift+Z` / `Shift+X` | (piano mode) octave down / up |
| `-` / `=` | volume down / up |
| click a key tile | play it (works on touch too) |
| drag audio onto a key | bind that file to that key |
| **Load Samples** button | file picker to load audio files |

### Adding samples to the repo

1. Put your `.wav` / `.ogg` / `.mp3` / `.flac` files in `samples/`
2. Copy `samples/mapping.example.json` → `samples/mapping.json` and edit it:
   ```json
   { "a": "kick.wav", "s": "snare.wav", "d": "hat.wav" }
   ```
3. Commit and push — the live page will load the samples automatically

See [`samples/README.md`](samples/README.md) for full details.

---

## Desktop App (Python)

Needs `pygame` but gives a native window with lower latency.

```bash
pip install -r requirements.txt
python3 keyboard_sample_player.py            # synth piano
python3 keyboard_sample_player.py --samples my_kit/   # your own samples
python3 keyboard_sample_player.py --list     # print mapping, no window needed
```

Options: `--samples DIR`, `--octave N`, `--channels N`, `--list`

### Files

| File | Purpose |
|---|---|
| `index.html` | **web app** — single page, no build step, works on GitHub Pages |
| `keyboard_sample_player.py` | desktop app (pygame) |
| `tone_generator.py` | pure-stdlib WAV synth (bootstraps the desktop note bank) |
| `samples/` | audio files + `mapping.json` go here (shared by both apps) |
| `requirements.txt` | Python dependency (`pygame`) |

### Enabling GitHub Pages

In the repo → **Settings → Pages → Source**, set branch `main` (or this branch),
folder `/root`. The app will be live at `https://h92o.github.io/qoix/`.
