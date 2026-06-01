#!/usr/bin/env python3
"""Computer Keyboard Sample Player.

Turns your computer keyboard into a sample player / playable instrument:
each key is bound to an audio sample, and pressing the key triggers it.
A window shows the live keyboard so you can see what each key plays and
which keys are currently sounding.

Three ways a key gets its sample, in priority order:

  1. ``mapping.json`` in the samples directory -- explicit
     ``{"a": "kick.wav", "s": "snare.wav"}`` mappings (best for drum kits).
  2. Loose audio files in the samples directory -- auto-assigned to keys.
  3. A built-in synth note bank (generated on first run) laid out as a
     classic "typing keyboard piano" so the app is playable immediately.

Usage:
    pip install pygame
    python3 keyboard_sample_player.py                 # synth piano mode
    python3 keyboard_sample_player.py --samples kit/  # your own samples
    python3 keyboard_sample_player.py --list          # print key map and exit

Controls:
    Any mapped key   play its sample
    Z / X            (piano mode) octave down / up
    -  / =           master volume down / up
    Esc or window X  quit
"""

from __future__ import annotations

import argparse
import json
import os
import sys

# The classic tracker / FL-Studio "computer keyboard piano" layout.
# Two rows of the QWERTY keyboard form two octaves of white+black keys.
# Each entry maps a key name (as pygame reports it) to a (note, octave_offset).
_PIANO_LAYOUT = {
    # lower octave (offset 0): white keys on the Z row, sharps on the A row
    "z": ("C", 0),  "s": ("C#", 0), "x": ("D", 0),  "d": ("D#", 0),
    "c": ("E", 0),  "v": ("F", 0),  "g": ("F#", 0), "b": ("G", 0),
    "h": ("G#", 0), "n": ("A", 0),  "j": ("A#", 0), "m": ("B", 0),
    ",": ("C", 1),  "l": ("C#", 1), ".": ("D", 1),  ";": ("D#", 1),
    "/": ("E", 1),
    # upper octave (offset 1): white keys on the Q row, sharps on number row
    "q": ("C", 1),  "2": ("C#", 1), "w": ("D", 1),  "3": ("D#", 1),
    "e": ("E", 1),  "r": ("F", 1),  "5": ("F#", 1), "t": ("G", 1),
    "6": ("G#", 1), "y": ("A", 1),  "7": ("A#", 1), "u": ("B", 1),
    "i": ("C", 2),  "9": ("C#", 2), "o": ("D", 2),  "0": ("D#", 2),
    "p": ("E", 2),
}

# Keys auto-assigned (in this order) to loose sample files in a samples dir.
_AUTO_KEYS = list("asdfghjklqwertyuiopzxcvbnm1234567890")

_AUDIO_EXTS = (".wav", ".ogg", ".mp3", ".flac")

# Visual keyboard rows for the on-screen display.
_DISPLAY_ROWS = [
    list("1234567890"),
    list("qwertyuiop"),
    list("asdfghjkl;"),
    list("zxcvbnm,./"),
]


def _is_audio(name: str) -> bool:
    return name.lower().endswith(_AUDIO_EXTS)


class SamplePlayer:
    """Loads samples, maps them to keys, and plays them via pygame.mixer."""

    def __init__(self, samples_dir: str, base_octave: int = 4,
                 channels: int = 32):
        self.samples_dir = samples_dir
        self.base_octave = base_octave
        self.num_channels = channels
        self.volume = 0.8
        self.mode = "files"  # or "piano"
        # key name -> dict(sound=Sound, label=str)
        self.bindings: dict[str, dict] = {}
        self._mixer_ready = False

    # -- audio backend -----------------------------------------------------

    def init_mixer(self):
        import pygame
        pygame.mixer.pre_init(frequency=44_100, size=-16, channels=2,
                              buffer=512)
        pygame.mixer.init()
        pygame.mixer.set_num_channels(self.num_channels)
        self._mixer_ready = True

    def _load_sound(self, path: str):
        import pygame
        return pygame.mixer.Sound(path)

    # -- mapping construction ---------------------------------------------

    def build_bindings(self):
        """Pick a binding strategy based on what's in the samples directory."""
        mapping_file = os.path.join(self.samples_dir, "mapping.json")
        if os.path.isfile(mapping_file):
            self._bind_from_mapping(mapping_file)
            self.mode = "files"
            return
        loose = self._loose_sample_files()
        if loose:
            self._bind_auto(loose)
            self.mode = "files"
            return
        # Nothing supplied: fall back to the generated synth piano.
        self._bind_piano()
        self.mode = "piano"

    def _loose_sample_files(self) -> list[str]:
        if not os.path.isdir(self.samples_dir):
            return []
        names = sorted(
            f for f in os.listdir(self.samples_dir)
            if _is_audio(f) and os.path.isfile(
                os.path.join(self.samples_dir, f))
        )
        return [os.path.join(self.samples_dir, f) for f in names]

    def _bind_from_mapping(self, mapping_file: str):
        with open(mapping_file, "r", encoding="utf-8") as fh:
            mapping = json.load(fh)
        for key, rel in mapping.items():
            path = rel if os.path.isabs(rel) else os.path.join(
                self.samples_dir, rel)
            if not os.path.isfile(path):
                print(f"  ! mapping skips missing file: {rel}",
                      file=sys.stderr)
                continue
            label = os.path.splitext(os.path.basename(path))[0]
            self._bind(key.lower(), path, label)

    def _bind_auto(self, files: list[str]):
        for key, path in zip(_AUTO_KEYS, files):
            label = os.path.splitext(os.path.basename(path))[0]
            self._bind(key, path, label)
        if len(files) > len(_AUTO_KEYS):
            print(f"  ! {len(files) - len(_AUTO_KEYS)} sample(s) had no free "
                  "key and were skipped.", file=sys.stderr)

    def _bind_piano(self):
        from tone_generator import generate_note_bank
        notes_dir = os.path.join(self.samples_dir, "notes")
        print("No samples found -- generating a synth note bank "
              f"in {notes_dir} (first run only)...")
        bank = generate_note_bank(notes_dir)
        self._note_bank = bank
        self._apply_piano_octave()

    def _apply_piano_octave(self):
        """(Re)bind piano keys for the current base octave."""
        if self._mixer_ready:
            self.stop_all()
        self.bindings.clear()
        for key, (note, octave_off) in _PIANO_LAYOUT.items():
            octave = self.base_octave + octave_off
            label = f"{note}{octave}"
            path = self._note_bank.get(label)
            if path:
                self._bind(key, path, label)

    def _bind(self, key: str, path: str, label: str):
        entry = {"path": path, "label": label, "sound": None}
        if self._mixer_ready:
            entry["sound"] = self._load_sound(path)
            entry["sound"].set_volume(self.volume)
        self.bindings[key] = entry

    def realize_sounds(self):
        """Load Sound objects after the mixer is up (decode + cache)."""
        for entry in self.bindings.values():
            if entry["sound"] is None:
                entry["sound"] = self._load_sound(entry["path"])
            entry["sound"].set_volume(self.volume)

    # -- playback ----------------------------------------------------------

    def play(self, key: str) -> bool:
        entry = self.bindings.get(key)
        if not entry or entry["sound"] is None:
            return False
        import pygame
        channel = pygame.mixer.find_channel(force=True)
        if channel:
            channel.play(entry["sound"])
        return True

    def stop_all(self):
        import pygame
        pygame.mixer.stop()

    def change_octave(self, delta: int):
        if self.mode != "piano":
            return
        self.base_octave = max(1, min(7, self.base_octave + delta))
        self._apply_piano_octave()
        self.realize_sounds()

    def change_volume(self, delta: float):
        self.volume = max(0.0, min(1.0, round(self.volume + delta, 2)))
        for entry in self.bindings.values():
            if entry["sound"] is not None:
                entry["sound"].set_volume(self.volume)

    # -- introspection -----------------------------------------------------

    def describe(self) -> list[tuple[str, str]]:
        return sorted((k, v["label"]) for k, v in self.bindings.items())


# --------------------------------------------------------------------------
# GUI / event loop
# --------------------------------------------------------------------------

_BG = (18, 18, 24)
_KEY_BG = (44, 46, 58)
_KEY_MAPPED = (60, 88, 120)
_KEY_ACTIVE = (240, 196, 80)
_TEXT = (235, 235, 240)
_SUBTEXT = (150, 152, 165)


def run_gui(player: SamplePlayer):
    import pygame

    pygame.init()
    player.init_mixer()
    player.realize_sounds()

    width, height = 760, 380
    screen = pygame.display.set_mode((width, height))
    pygame.display.set_caption("Keyboard Sample Player")
    font = pygame.font.SysFont("menlo,consolas,monospace", 16)
    small = pygame.font.SysFont("menlo,consolas,monospace", 12)
    big = pygame.font.SysFont("menlo,consolas,monospace", 20, bold=True)
    clock = pygame.time.Clock()

    active: set[str] = set()
    running = True
    while running:
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
            elif event.type == pygame.KEYDOWN:
                if event.key == pygame.K_ESCAPE:
                    running = False
                    continue
                name = pygame.key.name(event.key)
                mods = pygame.key.get_mods()
                # Octave / volume controls (use SHIFT+Z/X so the piano's
                # plain z/x keys still play notes).
                if player.mode == "piano" and (mods & pygame.KMOD_SHIFT):
                    if name == "z":
                        player.change_octave(-1)
                        continue
                    if name == "x":
                        player.change_octave(+1)
                        continue
                if name in ("-", "minus"):
                    player.change_volume(-0.1)
                    continue
                if name in ("=", "equals", "+"):
                    player.change_volume(+0.1)
                    continue
                if player.play(name):
                    active.add(name)
            elif event.type == pygame.KEYUP:
                active.discard(pygame.key.name(event.key))

        _draw(screen, player, active, font, small, big, width)
        pygame.display.flip()
        clock.tick(60)

    player.stop_all()
    pygame.quit()


def _draw(screen, player, active, font, small, big, width):
    import pygame
    screen.fill(_BG)

    title = ("Synth Piano (Shift+Z / Shift+X = octave)"
             if player.mode == "piano" else "Sample Player")
    screen.blit(big.render(title, True, _TEXT), (20, 16))
    info = f"octave {player.base_octave}  |  " if player.mode == "piano" else ""
    info += f"volume {int(player.volume * 100)}%   (-/= to change, Esc quits)"
    screen.blit(small.render(info, True, _SUBTEXT), (20, 46))

    # Draw the on-screen keyboard.
    key_w, key_h, gap = 64, 56, 8
    top = 84
    for r, row in enumerate(_DISPLAY_ROWS):
        x = 20 + r * (key_w // 2)  # stagger rows like a real keyboard
        y = top + r * (key_h + gap)
        for ch in row:
            entry = player.bindings.get(ch)
            if ch in active and entry:
                color = _KEY_ACTIVE
            elif entry:
                color = _KEY_MAPPED
            else:
                color = _KEY_BG
            rect = pygame.Rect(x, y, key_w, key_h)
            pygame.draw.rect(screen, color, rect, border_radius=8)
            cap = ch.upper()
            tcol = _BG if ch in active and entry else _TEXT
            screen.blit(font.render(cap, True, tcol), (x + 8, y + 6))
            if entry:
                lbl = entry["label"]
                if len(lbl) > 7:
                    lbl = lbl[:6] + "…"
                lcol = _BG if ch in active else _SUBTEXT
                screen.blit(small.render(lbl, True, lcol),
                            (x + 6, y + key_h - 18))
            x += key_w + gap


def print_mapping(player: SamplePlayer):
    print(f"\nMode: {player.mode}")
    if player.mode == "piano":
        print(f"Base octave: {player.base_octave}")
    print("Key -> Sample")
    print("-" * 28)
    for key, label in player.describe():
        print(f"  {key:<4} -> {label}")
    print(f"\n{len(player.bindings)} keys bound.\n")


def parse_args(argv=None):
    p = argparse.ArgumentParser(
        description="Turn your computer keyboard into a sample player.")
    p.add_argument("--samples", default="samples",
                   help="directory with audio files / mapping.json "
                        "(default: samples)")
    p.add_argument("--octave", type=int, default=4,
                   help="base octave for synth piano mode (default: 4)")
    p.add_argument("--channels", type=int, default=32,
                   help="max simultaneous voices (default: 32)")
    p.add_argument("--list", action="store_true",
                   help="print the key mapping and exit (no window/audio)")
    return p.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    player = SamplePlayer(args.samples, base_octave=args.octave,
                          channels=args.channels)
    player.build_bindings()

    if args.list:
        print_mapping(player)
        return 0

    if not player.bindings:
        print("No samples could be bound. Add audio files to "
              f"'{args.samples}/' or a mapping.json.", file=sys.stderr)
        return 1

    try:
        import pygame  # noqa: F401
    except ImportError:
        print("pygame is required to play. Install it with:\n"
              "    pip install pygame\n"
              "(Use --list to preview the mapping without pygame.)",
              file=sys.stderr)
        return 1

    print_mapping(player)
    run_gui(player)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
