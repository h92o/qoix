"""Notes, scales, chords and progressions.

The scale table deliberately matches `js/randomgen.js` in the QOIX synth so a
pattern sounds the same whether it was generated here or played live in the
app; the extra entries past 'Japanese' are additions, not replacements.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Dict, List, Optional, Sequence, Tuple

__all__ = [
    "SCALES", "CHORDS", "PROGRESSIONS", "NOTE_NAMES",
    "note_name", "parse_note", "Scale", "Chord",
    "parse_progression", "diatonic_chord", "voice_lead", "spread_voicing",
]

NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

_PITCH_CLASS = {
    "C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11,
}

# Intervals in semitones from the root.  The first fifteen mirror QOIX's
# RandomGen so the two generators agree on what "Phrygian" means.
SCALES: Dict[str, List[int]] = {
    "Chromatic":       [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
    "Major":           [0, 2, 4, 5, 7, 9, 11],
    "Natural Minor":   [0, 2, 3, 5, 7, 8, 10],
    "Harmonic Minor":  [0, 2, 3, 5, 7, 8, 11],
    "Dorian":          [0, 2, 3, 5, 7, 9, 10],
    "Phrygian":        [0, 1, 3, 5, 7, 8, 10],
    "Lydian":          [0, 2, 4, 6, 7, 9, 11],
    "Mixolydian":      [0, 2, 4, 5, 7, 9, 10],
    "Pentatonic Maj":  [0, 2, 4, 7, 9],
    "Pentatonic Min":  [0, 3, 5, 7, 10],
    "Blues":           [0, 3, 5, 6, 7, 10],
    "Whole Tone":      [0, 2, 4, 6, 8, 10],
    "Diminished":      [0, 2, 3, 5, 6, 8, 9, 11],
    "Augmented":       [0, 3, 4, 7, 8, 11],
    "Japanese":        [0, 1, 5, 7, 8],
    # Additions
    "Melodic Minor":   [0, 2, 3, 5, 7, 9, 11],
    "Locrian":         [0, 1, 3, 5, 6, 8, 10],
    "Phrygian Dom":    [0, 1, 4, 5, 7, 8, 10],
    "Hungarian Minor": [0, 2, 3, 6, 7, 8, 11],
    "Lydian Dom":      [0, 2, 4, 6, 7, 9, 10],
    "Super Locrian":   [0, 1, 3, 4, 6, 8, 10],
    "Hirajoshi":       [0, 2, 3, 7, 8],
    "In Sen":          [0, 1, 5, 7, 10],
    "Iwato":           [0, 1, 5, 6, 10],
    "Prometheus":      [0, 2, 4, 6, 9, 10],
    "Enigmatic":       [0, 1, 4, 6, 8, 10, 11],
    "Bebop Dominant":  [0, 2, 4, 5, 7, 9, 10, 11],
}

CHORDS: Dict[str, List[int]] = {
    "":        [0, 4, 7],
    "maj":     [0, 4, 7],
    "m":       [0, 3, 7],
    "min":     [0, 3, 7],
    "dim":     [0, 3, 6],
    "aug":     [0, 4, 8],
    "sus2":    [0, 2, 7],
    "sus4":    [0, 5, 7],
    "5":       [0, 7],
    "6":       [0, 4, 7, 9],
    "m6":      [0, 3, 7, 9],
    "7":       [0, 4, 7, 10],
    "maj7":    [0, 4, 7, 11],
    "m7":      [0, 3, 7, 10],
    "mmaj7":   [0, 3, 7, 11],
    "dim7":    [0, 3, 6, 9],
    "m7b5":    [0, 3, 6, 10],
    "7sus4":   [0, 5, 7, 10],
    "add9":    [0, 4, 7, 14],
    "madd9":   [0, 3, 7, 14],
    "9":       [0, 4, 7, 10, 14],
    "maj9":    [0, 4, 7, 11, 14],
    "m9":      [0, 3, 7, 10, 14],
    "11":      [0, 4, 7, 10, 14, 17],
    "m11":     [0, 3, 7, 10, 14, 17],
    "13":      [0, 4, 7, 10, 14, 21],
    "quartal": [0, 5, 10, 15],
}

#: Named progressions, written as roman numerals relative to the key root.
PROGRESSIONS: Dict[str, List[str]] = {
    "pop":         ["I", "V", "vi", "IV"],
    "sad":         ["vi", "IV", "I", "V"],
    "andalusian":  ["i", "bVII", "bVI", "V"],
    "minor-loop":  ["i", "bVI", "bIII", "bVII"],
    "epic":        ["i", "bVI", "bIII", "iv"],
    "jazz":        ["iim7", "V7", "Imaj7", "Imaj7"],
    "jazz-minor":  ["iim7b5", "V7", "im7", "im7"],
    "modal-dorian": ["im7", "IV7", "im7", "IV7"],
    "house":       ["im9", "bVImaj9", "bIIImaj9", "bVIIsus4"],
    "ambient":     ["Imaj9", "IVmaj9", "vim9", "IVmaj9"],
    "cinematic":   ["i", "bVII", "bVI", "bVII"],
    "canon":       ["I", "V", "vi", "iii", "IV", "I", "IV", "V"],
    "blues":       ["I7", "I7", "I7", "I7", "IV7", "IV7", "I7", "I7",
                    "V7", "IV7", "I7", "V7"],
    "drone":       ["i", "i", "i", "i"],
    "static":      ["Imaj7"],
}

_MAJOR_STEPS = [0, 2, 4, 5, 7, 9, 11]
_ROMAN_VALUES = {"i": 0, "ii": 1, "iii": 2, "iv": 3, "v": 4, "vi": 5, "vii": 6}
_NOTE_RE = re.compile(r"^([A-Ga-g])([#b]*)(-?\d+)?$")
_ROMAN_RE = re.compile(r"^([#b]*)([iIvV]+)(.*)$")


def note_name(midi: int, middle_c_octave: int = 4) -> str:
    """`60 -> 'C4'` by default.

    Surge XT has a 'Middle C' preference (C3/C4/C5); pass `middle_c_octave` to
    match whatever the instance is displaying so note names line up.
    """
    return f"{NOTE_NAMES[midi % 12]}{midi // 12 - (5 - middle_c_octave)}"


def parse_note(value, middle_c_octave: int = 4) -> int:
    """Accept 60, '60', 'C4', 'F#2' or 'Bb-1' and return a MIDI note number."""
    if isinstance(value, int):
        return value
    text = str(value).strip()
    if re.fullmatch(r"-?\d+", text):
        return int(text)
    match = _NOTE_RE.match(text)
    if not match:
        raise ValueError(f"cannot parse note {value!r} (try 'C4', 'F#2' or '60')")
    letter, accidentals, octave = match.groups()
    pitch = _PITCH_CLASS[letter.upper()]
    pitch += accidentals.count("#") - accidentals.count("b")
    octave = 4 if octave is None else int(octave)
    return pitch + (octave + (5 - middle_c_octave)) * 12


def parse_pitch_class(value) -> int:
    """Root of a key: 'C', 'F#', 'Bb' or 0-11."""
    if isinstance(value, int):
        return value % 12
    text = str(value).strip()
    if re.fullmatch(r"\d+", text):
        return int(text) % 12
    match = re.fullmatch(r"([A-Ga-g])([#b]*)", text)
    if not match:
        raise ValueError(f"cannot parse key root {value!r}")
    letter, accidentals = match.groups()
    return (_PITCH_CLASS[letter.upper()]
            + accidentals.count("#") - accidentals.count("b")) % 12


@dataclass
class Scale:
    """A key: a root pitch class plus a set of intervals."""

    root: int
    name: str = "Major"

    def __post_init__(self) -> None:
        self.root = parse_pitch_class(self.root)
        if self.name not in SCALES:
            close = ", ".join(sorted(SCALES))
            raise ValueError(f"unknown scale {self.name!r}. Available: {close}")
        self.intervals = SCALES[self.name]

    @property
    def size(self) -> int:
        return len(self.intervals)

    def pitch_classes(self) -> List[int]:
        return sorted({(self.root + i) % 12 for i in self.intervals})

    def degree(self, index: int, base_octave: int = 4) -> int:
        """Scale degree by index, wrapping into higher/lower octaves."""
        octave, position = divmod(index, self.size)
        return (self.root + self.intervals[position]
                + (base_octave + 1) * 12 + octave * 12)

    def notes_in_range(self, low: int, high: int) -> List[int]:
        pcs = set(self.pitch_classes())
        return [n for n in range(low, high + 1) if n % 12 in pcs]

    def contains(self, note: int) -> bool:
        return note % 12 in set(self.pitch_classes())

    def quantize(self, note: int, prefer_up: bool = False) -> int:
        """Snap a note onto the scale, moving as little as possible."""
        if self.contains(note):
            return note
        for distance in range(1, 12):
            order = ((distance, -distance) if prefer_up else (-distance, distance))
            for offset in order:
                if 0 <= note + offset <= 127 and self.contains(note + offset):
                    return note + offset
        return note

    def index_of(self, note: int, base_octave: int = 4) -> Optional[int]:
        """Inverse of :meth:`degree`: which scale step is this note?

        Returns None for notes outside the scale, so callers can decide whether
        to quantize or skip.
        """
        relative = note - (self.root + (base_octave + 1) * 12)
        octave, pitch = divmod(relative, 12)
        if pitch not in self.intervals:
            return None
        return octave * self.size + self.intervals.index(pitch)


@dataclass
class Chord:
    """A rooted stack of intervals, plus the label it came from."""

    root: int
    intervals: List[int]
    label: str = ""

    def notes(self, inversion: int = 0, octaves: int = 1) -> List[int]:
        notes = [self.root + i for i in self.intervals]
        for _ in range(inversion):
            notes = notes[1:] + [notes[0] + 12]
        for extra in range(1, octaves):
            notes += [n + 12 * extra for n in notes[:len(self.intervals)]]
        return sorted(notes)

    def bass(self) -> int:
        return self.root

    def __str__(self) -> str:
        return self.label or note_name(self.root)


def parse_progression(symbols: Sequence[str], key_root, scale_name: str = "Major",
                      octave: int = 3) -> List[Chord]:
    """Turn roman numerals into chords in a key.

    Case sets the default triad quality (`IV` major, `iv` minor) and a suffix
    overrides it (`iim7b5`, `V7`, `bVImaj9`).  Degrees are read against the
    major scale so `bVII` means ten semitones above the root in every mode,
    which is how roman numerals are conventionally written.
    """
    root_pc = parse_pitch_class(key_root)
    base = root_pc + (octave + 1) * 12
    chords: List[Chord] = []

    for symbol in symbols:
        text = symbol.strip()
        if not text:
            continue
        match = _ROMAN_RE.match(text)
        if not match:
            raise ValueError(f"cannot parse chord symbol {symbol!r}")
        accidentals, numeral, suffix = match.groups()
        if numeral.lower() not in _ROMAN_VALUES:
            raise ValueError(f"{numeral!r} is not a roman numeral I-VII in {symbol!r}")
        degree = _ROMAN_VALUES[numeral.lower()]
        semitones = _MAJOR_STEPS[degree]
        semitones += accidentals.count("#") - accidentals.count("b")

        suffix = suffix.strip()
        if suffix == "":
            # Case carries the quality: IV is major, iv is minor.
            intervals = CHORDS["maj"] if numeral.isupper() else CHORDS["m"]
        elif suffix in CHORDS:
            intervals = CHORDS[suffix]
        elif numeral.islower() and ("m" + suffix) in CHORDS:
            intervals = CHORDS["m" + suffix]
        elif numeral.isupper() and ("maj" + suffix) in CHORDS:
            intervals = CHORDS["maj" + suffix]
        else:
            raise ValueError(
                f"unknown chord quality {suffix!r} in {symbol!r}. "
                f"Known qualities: {', '.join(sorted(k for k in CHORDS if k))}")

        chords.append(Chord(base + semitones, list(intervals), text))

    if not chords:
        raise ValueError("progression is empty")
    return chords


def diatonic_chord(scale: Scale, degree: int, size: int = 3,
                   base_octave: int = 3) -> Chord:
    """Stack thirds *within the scale* -- modal harmony without accidentals."""
    notes = [scale.degree(degree + 2 * step, base_octave) for step in range(size)]
    root = notes[0]
    return Chord(root, [n - root for n in notes],
                 f"{scale.name} degree {degree % scale.size + 1}")


def voice_lead(chord: Chord, previous: Optional[Sequence[int]],
               low: int = 48, high: int = 76) -> List[int]:
    """Pick the inversion and octave whose voices move least from `previous`.

    Without a previous chord this just centres the voicing in the register,
    which keeps a progression from lurching an octave on the first change.
    """
    candidates: List[Tuple[float, List[int]]] = []
    span = len(chord.intervals)
    for inversion in range(span):
        for octave_shift in (-12, 0, 12):
            notes = [n + octave_shift for n in chord.notes(inversion)]
            if min(notes) < low or max(notes) > high:
                continue
            if previous:
                cost = sum(min(abs(n - p) for p in previous) for n in notes)
            else:
                centre = (low + high) / 2
                cost = abs(sum(notes) / len(notes) - centre)
            candidates.append((cost, notes))
    if not candidates:
        return chord.notes()
    return min(candidates, key=lambda item: item[0])[1]


def spread_voicing(notes: Sequence[int], spread: int = 1) -> List[int]:
    """Open a close voicing up by pushing alternate voices an octave apart."""
    if spread <= 0 or len(notes) < 3:
        return list(notes)
    voiced = list(notes)
    for index in range(1, len(voiced), 2):
        voiced[index] += 12 * spread
    return sorted(voiced)
