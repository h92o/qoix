# Samples directory

This is where the keyboard sample player looks for sounds. It supports three
modes, chosen automatically (highest priority first):

### 1. Explicit mapping — `mapping.json`
Drop your audio files here and add a `mapping.json` that binds keys to files:

```json
{ "a": "kick.wav", "s": "snare.wav", "d": "hat.wav" }
```

Copy `mapping.example.json` to `mapping.json` to get started. This is the best
mode for drum kits and curated layouts.

### 2. Auto-assign loose files
If there's no `mapping.json`, every audio file (`.wav`, `.ogg`, `.mp3`,
`.flac`) directly in this folder is auto-assigned to keys in the order
`a s d f g h j k l q w e r ...`.

### 3. Synth piano (fallback)
If this folder has no audio files at all, the player generates a built-in note
bank in `samples/notes/` and lays it out as a classic typing-keyboard piano so
the app is playable immediately. That `notes/` folder is git-ignored because it
is regenerated on first run.

Tip: `.wav` and `.ogg` are the most reliable formats with pygame; `.mp3`
support depends on your local SDL build.
