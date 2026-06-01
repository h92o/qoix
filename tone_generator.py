"""Pure standard-library WAV tone generator.

Used to bootstrap a set of playable samples so the keyboard sample player
works out of the box, with no numpy / scipy / external audio files needed.

Every note is rendered to a 16-bit mono PCM WAV at 44.1 kHz using a small
additive-synthesis voice with an ADSR envelope, which sounds noticeably
nicer than a raw sine wave while staying dependency-free.

You can also run this module directly to (re)generate the note bank:

    python3 tone_generator.py            # writes samples/notes/*.wav
    python3 tone_generator.py --out dir  # custom output directory
"""

from __future__ import annotations

import argparse
import math
import os
import struct
import wave

SAMPLE_RATE = 44_100
AMPLITUDE = 0.32  # headroom so stacked harmonics don't clip

# Note name -> semitone offset from C within an octave.
_SEMITONES = {
    "C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5,
    "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11,
}


def note_frequency(name: str, octave: int) -> float:
    """Equal-tempered frequency for e.g. ('A', 4) -> 440.0 Hz (A4 = 440)."""
    midi = (octave + 1) * 12 + _SEMITONES[name]
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


def _adsr(i: int, total: int, attack: float, decay: float,
          sustain: float, release: float) -> float:
    """ADSR envelope value in [0, 1] for sample index ``i`` of ``total``."""
    t = i / SAMPLE_RATE
    dur = total / SAMPLE_RATE
    rel_start = max(dur - release, 0.0)
    if t < attack:
        return t / attack if attack else 1.0
    if t < attack + decay:
        return 1.0 - (1.0 - sustain) * ((t - attack) / decay if decay else 1.0)
    if t < rel_start:
        return sustain
    # release tail
    return sustain * max(0.0, 1.0 - (t - rel_start) / release if release else 0.0)


def render_note(frequency: float, duration: float = 1.1) -> bytes:
    """Render a single note to raw 16-bit little-endian PCM frames (mono)."""
    total = int(SAMPLE_RATE * duration)
    # Harmonic weights give a soft electric-piano-ish timbre.
    harmonics = ((1, 1.0), (2, 0.45), (3, 0.22), (4, 0.12), (5, 0.06))
    norm = sum(w for _, w in harmonics)

    frames = bytearray()
    two_pi = 2.0 * math.pi
    for i in range(total):
        t = i / SAMPLE_RATE
        sample = 0.0
        for mult, weight in harmonics:
            sample += weight * math.sin(two_pi * frequency * mult * t)
        sample /= norm
        env = _adsr(i, total, attack=0.005, decay=0.18,
                    sustain=0.55, release=0.45)
        value = int(max(-1.0, min(1.0, sample * env * AMPLITUDE)) * 32767)
        frames += struct.pack("<h", value)
    return bytes(frames)


def write_wav(path: str, pcm: bytes) -> None:
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(pcm)


# Notes spanning the range used by the default keyboard layout (C3..E6).
def _default_notes():
    for octave in range(3, 7):
        for name in _SEMITONES:
            yield name, octave


def generate_note_bank(out_dir: str, force: bool = False) -> dict[str, str]:
    """Render every default note to ``out_dir`` and return {note_label: path}.

    ``note_label`` looks like ``C4`` / ``F#5`` (``#`` is kept in the filename).
    Existing files are skipped unless ``force`` is set, so startup stays fast.
    """
    os.makedirs(out_dir, exist_ok=True)
    bank: dict[str, str] = {}
    for name, octave in _default_notes():
        label = f"{name}{octave}"
        path = os.path.join(out_dir, f"{label}.wav")
        if force or not os.path.exists(path):
            write_wav(path, render_note(note_frequency(name, octave)))
        bank[label] = path
    return bank


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate the WAV note bank.")
    parser.add_argument("--out", default=os.path.join("samples", "notes"),
                        help="output directory (default: samples/notes)")
    parser.add_argument("--force", action="store_true",
                        help="overwrite existing files")
    args = parser.parse_args()
    bank = generate_note_bank(args.out, force=args.force)
    print(f"Wrote {len(bank)} notes to {args.out}")


if __name__ == "__main__":
    main()
