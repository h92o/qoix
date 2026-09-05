"""surge-midigen -- MIDI generation for the Surge XT synthesizer.

A dependency-free generator that writes Standard MIDI Files aimed at Surge XT
specifically: macros on their factory CCs, MPE with per-note bend, pressure and
timbre, Scala microtuning, and Channel Split scene routing.

    from surge_midigen import build_song
    build_song("berlin-school", seed=7).save("seq.mid")
"""

from __future__ import annotations

__version__ = "1.0.0"

from .smf import MidiFile, Track, parse_midi_file          # noqa: E402
from .theory import Scale, Chord, SCALES, CHORDS, PROGRESSIONS  # noqa: E402
from .tuning import Tuning, load_tuning, parse_scl          # noqa: E402
from .surge import SurgeConfig, MACRO_CC, CC                # noqa: E402
from .mpe import Expression, MPEAllocator                   # noqa: E402
from .automation import Lane                                # noqa: E402
from .generators import Context, Note, Part, build_chord_plan, GENERATORS  # noqa: E402
from .presets import PRESETS, get_preset                    # noqa: E402
from .song import build_song, BuildResult                   # noqa: E402

__all__ = [
    "__version__",
    "MidiFile", "Track", "parse_midi_file",
    "Scale", "Chord", "SCALES", "CHORDS", "PROGRESSIONS",
    "Tuning", "load_tuning", "parse_scl",
    "SurgeConfig", "MACRO_CC", "CC",
    "Expression", "MPEAllocator", "Lane",
    "Context", "Note", "Part", "build_chord_plan", "GENERATORS",
    "PRESETS", "get_preset", "build_song", "BuildResult",
]
