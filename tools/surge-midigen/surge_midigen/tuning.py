"""Scala (.scl) tuning support.

Surge XT loads .scl/.kbm files natively, which is the *right* way to play
microtonal material through it.  This module supports that path and one other:

``scala`` mode
    Emit ordinary MIDI notes and let Surge do the retuning.  Scale degrees land
    on consecutive MIDI keys, exactly as Surge maps them with a default keyboard
    mapping, so key 61 is the first degree above the root whatever the scale.

``bend`` mode
    Leave Surge in 12-TET and carry the tuning in the file as per-note pitch
    bend.  Polyphony needs MPE (one channel per note); a monophonic line is
    fine on a single channel.  Useful when the file has to play on an instance
    you do not control, or alongside 12-TET parts.

Loading a .scl in Surge *and* generating bends applies the tuning twice, which
sounds broken in an interesting way and is almost never what you want.

The parser matches `js/microtonal.js` in the QOIX synth token for token: a
token with a '.' is cents, `n/d` is a ratio, a bare integer is `n/1`, and the
implicit 1/1 root is prepended so `pitches[0]` is always 0.0 cents.
"""

from __future__ import annotations

import math
import re
from dataclasses import dataclass
from typing import Dict, List, Optional

__all__ = ["Tuning", "parse_scl", "edo_scl", "BUILTIN_SCALES", "load_tuning"]


def _parse_pitch_token(token: str, index: int) -> float:
    """One .scl pitch value in cents."""
    if "." in token:
        try:
            return float(token)
        except ValueError:
            raise ValueError(f"invalid cents value {token!r} at pitch {index}") from None
    if "/" in token:
        parts = token.split("/")
        if len(parts) != 2:
            raise ValueError(f"invalid ratio {token!r} at pitch {index}")
        try:
            numerator, denominator = float(parts[0]), float(parts[1])
        except ValueError:
            raise ValueError(f"invalid ratio {token!r} at pitch {index}") from None
        if denominator == 0 or numerator <= 0:
            raise ValueError(f"invalid ratio {token!r} at pitch {index}")
        return 1200.0 * math.log2(numerator / denominator)
    try:
        value = float(token)
    except ValueError:
        raise ValueError(f"invalid integer ratio {token!r} at pitch {index}") from None
    if value <= 0:
        raise ValueError(f"invalid integer ratio {token!r} at pitch {index}")
    return 1200.0 * math.log2(value)


def parse_scl(text: str) -> "Tuning":
    """Parse Scala .scl text into a :class:`Tuning`."""
    if not isinstance(text, str) or not text.strip():
        raise ValueError("empty .scl input")

    lines = [line.strip() for line in text.splitlines()]
    lines = [line for line in lines if line and not line.startswith("!")]
    if len(lines) < 2:
        raise ValueError("malformed .scl: need a description line and a note count")

    description = lines[0]
    count_token = lines[1].split()[0]
    try:
        count = int(count_token)
    except ValueError:
        raise ValueError(f"invalid note count {count_token!r}") from None
    if count < 1:
        raise ValueError(f"invalid note count {count}")

    pitch_lines = lines[2:]
    if len(pitch_lines) < count:
        raise ValueError(f"expected {count} pitch values, found {len(pitch_lines)}")

    pitches = [0.0]
    for index in range(count):
        pitches.append(_parse_pitch_token(pitch_lines[index].split()[0], index + 1))

    return Tuning(description=description, pitches=pitches)


def edo_scl(divisions: int, period_cents: float = 1200.0,
            description: Optional[str] = None) -> str:
    """Build .scl text for an equal division of the octave (or any period)."""
    if divisions < 1:
        raise ValueError("EDO needs at least one division")
    step = period_cents / divisions
    header = description or f"{divisions} equal divisions of {period_cents:g} cents"
    lines = [f"! {divisions}-edo.scl", f"{header}", f" {divisions}", "!"]
    lines += [f" {step * (i + 1):.6f}" for i in range(divisions)]
    return "\n".join(lines) + "\n"


#: A few tunings worth having without hunting down a file, matching the
#: built-ins in the QOIX synth's microtonal engine.
BUILTIN_SCALES: Dict[str, str] = {
    "12-edo": edo_scl(12, description="12-tone equal temperament"),
    "5-edo": edo_scl(5, description="5-tone equal temperament"),
    "7-edo": edo_scl(7, description="7-tone equal temperament"),
    "19-edo": edo_scl(19, description="19-tone equal temperament"),
    "24-edo": edo_scl(24, description="24-tone equal temperament (quarter tones)"),
    "31-edo": edo_scl(31, description="31-tone equal temperament"),
    "53-edo": edo_scl(53, description="53-tone equal temperament"),
    "bohlen-pierce": edo_scl(13, 1901.955, "Bohlen-Pierce, 13 equal divisions of 3/1"),
    "just": """! just_5limit.scl
5-limit just intonation
 12
 16/15
 9/8
 6/5
 5/4
 4/3
 45/32
 3/2
 8/5
 5/3
 9/5
 15/8
 2/1
""",
    "pythagorean": """! pythagorean.scl
Pythagorean tuning, 3-limit
 12
 256/243
 9/8
 32/27
 81/64
 4/3
 729/512
 3/2
 128/81
 27/16
 16/9
 243/128
 2/1
""",
    "meantone": """! meantone_1_4comma.scl
Quarter-comma meantone
 12
 76.049
 193.157
 310.265
 386.314
 503.422
 579.471
 696.579
 772.627
 889.735
 1006.843
 1082.892
 1200.000
""",
    "werckmeister3": """! werckmeister3.scl
Werckmeister III (1691)
 12
 90.225
 192.180
 294.135
 390.225
 498.045
 588.270
 696.090
 792.180
 888.270
 996.090
 1092.180
 1200.000
""",
    "harmonics": """! pure_harmonics.scl
Harmonics 8-16 over the fundamental
 8
 9/8
 5/4
 11/8
 3/2
 13/8
 7/4
 15/8
 2/1
""",
}


@dataclass
class Tuning:
    """A parsed .scl scale plus the mapping from MIDI keys onto its degrees."""

    description: str
    pitches: List[float]              # cents, index 0 is the implicit 1/1
    root_note: int = 60               # MIDI key that sounds the 1/1
    root_frequency: Optional[float] = None   # Hz; defaults to 12-TET for root_note

    def __post_init__(self) -> None:
        if len(self.pitches) < 2:
            raise ValueError("a tuning needs at least one degree above the root")
        if self.root_frequency is None:
            self.root_frequency = 440.0 * 2 ** ((self.root_note - 69) / 12.0)

    @property
    def count(self) -> int:
        """Degrees per period -- also how many MIDI keys one period spans."""
        return len(self.pitches) - 1

    @property
    def period(self) -> float:
        """Period in cents (1200 for an octave scale, 1901.955 for Bohlen-Pierce)."""
        return self.pitches[-1]

    def cents_from_root(self, note: int) -> float:
        offset = note - self.root_note
        degree = offset % self.count
        periods = offset // self.count
        return self.pitches[degree] + periods * self.period

    def frequency(self, note: int) -> float:
        return self.root_frequency * 2 ** (self.cents_from_root(note) / 1200.0)

    def deviation_cents(self, note: int) -> float:
        """How far this key sits from where 12-TET would put it.

        This is the number that goes into a pitch bend in ``bend`` mode.
        """
        equal = 440.0 * 2 ** ((note - 69) / 12.0)
        return 1200.0 * math.log2(self.frequency(note) / equal)

    def playable_range(self, low: int = 0, high: int = 127,
                       max_deviation: float = 4800.0) -> List[int]:
        """Keys whose bend stays inside a plausible bend range.

        A 5-EDO scale stretches keys far away from 12-TET the further you get
        from the root, so `bend` mode has a usable window rather than all 128
        keys.  Defaults to Surge's 48-semitone MPE range.
        """
        return [n for n in range(low, high + 1)
                if abs(self.deviation_cents(n)) <= max_deviation]

    def degree_table(self) -> List[Dict[str, float]]:
        return [{"degree": i, "cents": self.pitches[i]} for i in range(len(self.pitches))]

    def summary(self) -> str:
        return (f"{self.description} -- {self.count} degrees per "
                f"{self.period:.3f} cent period, 1/1 on MIDI key {self.root_note} "
                f"({self.root_frequency:.3f} Hz)")


def load_tuning(source: str, root_note: int = 60) -> Tuning:
    """Load by built-in name, by `edo:N`, or from a .scl file path."""
    key = str(source).strip().lower()
    if key in BUILTIN_SCALES:
        tuning = parse_scl(BUILTIN_SCALES[key])
    else:
        match = re.fullmatch(r"edo:(\d+)", key)
        if match:
            tuning = parse_scl(edo_scl(int(match.group(1))))
        else:
            with open(source, "r", encoding="utf-8", errors="replace") as handle:
                tuning = parse_scl(handle.read())
    tuning.root_note = root_note
    tuning.root_frequency = None
    tuning.__post_init__()
    return tuning
