"""Ready-made song templates.

Each preset is a complete brief -- tempo, key, harmony, which parts to build,
which macros to move -- so `--preset berlin-school -o seq.mid` produces
something you can drop straight onto a Surge XT track.  `surge_hint` says what
the macros are assumed to be doing, because a filter sweep on macro 1 only
sweeps if macro 1 is routed to a filter.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

__all__ = ["Preset", "PRESETS", "get_preset"]


@dataclass
class PartSpec:
    generator: str
    name: Optional[str] = None
    channel: int = 1
    expression: Optional[str] = None
    options: Dict[str, Any] = field(default_factory=dict)


@dataclass
class Preset:
    name: str
    description: str
    bpm: float = 120.0
    bars: int = 16
    key: str = "C"
    scale: str = "Natural Minor"
    progression: Any = "minor-loop"
    bars_per_chord: float = 1.0
    parts: List[PartSpec] = field(default_factory=list)
    lanes: List[str] = field(default_factory=list)
    mpe: bool = False
    swing: float = 0.0
    groove: Optional[str] = None
    humanize_ticks: int = 0
    humanize_velocity: int = 0
    tuning: Optional[str] = None
    tuning_mode: str = "scala"
    scene_split_channel: Optional[int] = None
    expression: Optional[str] = None
    surge_hint: str = ""


PRESETS: Dict[str, Preset] = {
    "ambient-drift": Preset(
        name="ambient-drift",
        description="Slow evolving pad and drone with wandering macros. MPE.",
        bpm=68, bars=16, key="D", scale="Lydian",
        progression="ambient", bars_per_chord=2.0, mpe=True,
        parts=[
            PartSpec("pad", expression="breath",
                     options=dict(velocity=58, spread=1, overlap=0.4)),
            PartSpec("drone", options=dict(velocity=48, intervals=(0, 7, 12))),
        ],
        lanes=["macro1:drift:8:0.7:0.45", "macro2:sine:12:0.5:0.5",
               "mod:arch:16:0.8:0.3"],
        surge_hint="Macro 1 -> filter cutoff, macro 2 -> reverb mix or unison "
                   "detune, mod wheel -> scene B level. Try a Pads patch.",
    ),
    "berlin-school": Preset(
        name="berlin-school",
        description="Driving 16th sequence over a root bass, filter opening across 8 bars.",
        bpm=128, bars=16, key="A", scale="Natural Minor",
        progression="minor-loop", bars_per_chord=2.0,
        parts=[
            PartSpec("arp", options=dict(mode="up", rate="1/16", octaves=2, gate=0.45)),
            PartSpec("bass", options=dict(style="root", rate="1/8", gate=0.7)),
        ],
        lanes=["macro1:ramp:8:0.85:0.5", "macro2:sine:3:0.35:0.55"],
        humanize_ticks=3, humanize_velocity=8,
        surge_hint="Macro 1 -> filter cutoff, macro 2 -> resonance or FM depth. "
                   "A plucky saw with a fast envelope suits the 16ths.",
    ),
    "techno-stab": Preset(
        name="techno-stab",
        description="Euclidean stabs and a four-on-the-floor bass.",
        bpm=132, bars=16, key="F", scale="Phrygian",
        progression=["i", "i", "bII", "i"], bars_per_chord=1.0,
        parts=[
            PartSpec("euclid", options=dict(pulses=5, steps=16, rate="1/16",
                                            gate=0.35, pitch_mode="chord")),
            PartSpec("bass", options=dict(style="driving", rate="1/4", gate=0.6)),
            PartSpec("chords", options=dict(rate="1/8", gate=0.2, velocity=88,
                                            spread=1, octave_shift=1)),
        ],
        lanes=["macro1:sh:1:0.6:0.5", "macro3:ramp-down:16:0.9:0.6"],
        humanize_velocity=12,
        surge_hint="Macro 1 -> a short filter or FM burst, macro 3 -> distortion drive.",
    ),
    "cinematic-swell": Preset(
        name="cinematic-swell",
        description="Wide pads with a slow melody and per-bar swells.",
        bpm=76, bars=16, key="C", scale="Harmonic Minor",
        progression="cinematic", bars_per_chord=2.0, mpe=True,
        parts=[
            PartSpec("pad", options=dict(velocity=62, spread=1, overlap=0.3)),
            PartSpec("melody", expression="vocal",
                     options=dict(rate="1/4", density=0.55,
                                  low="C5", high="C6", velocity=88)),
            PartSpec("bass", options=dict(style="pedal", rate="1/1", gate=0.98)),
        ],
        lanes=["macro1:arch:4:0.9:0.35", "expr:arch:2:0.7:0.4"],
        humanize_ticks=6, humanize_velocity=6,
        surge_hint="Macro 1 -> filter or a string ensemble's bow pressure; "
                   "expression is a live Surge modulation source, no MIDI learn needed.",
    ),
    "mpe-expressive": Preset(
        name="mpe-expressive",
        description="Solo line using per-note glide, vibrato, pressure and CC 74.",
        bpm=92, bars=12, key="E", scale="Dorian",
        progression="modal-dorian", bars_per_chord=2.0, mpe=True,
        parts=[
            PartSpec("melody", expression="lead",
                     options=dict(rate="1/8", density=0.6, gate=1.4,
                                  low="E3", high="E5", velocity=94)),
            PartSpec("pad", expression="swell", options=dict(velocity=48, spread=1)),
        ],
        lanes=[],
        humanize_ticks=5, humanize_velocity=8,
        surge_hint="Turn MPE on in Surge. Route Timbre to a filter or wavetable "
                   "position and Channel AT to level or FM depth to hear CC 74 "
                   "and pressure do their work.",
    ),
    "microtonal-19": Preset(
        name="microtonal-19",
        description="19-EDO sequence. Scale degrees land on consecutive MIDI keys.",
        bpm=104, bars=12, key="C", scale="Chromatic",
        progression=["i", "i", "i", "i"], bars_per_chord=1.0, mpe=True,
        tuning="19-edo", tuning_mode="bend",
        parts=[
            PartSpec("melody", options=dict(rate="1/8", density=0.75,
                                            low="C4", high="C5", leap=0.1)),
            PartSpec("drone", options=dict(velocity=52, intervals=(0, 11))),
        ],
        lanes=["macro1:drift:6:0.6:0.5"],
        surge_hint="Written as pitch bend, so leave Surge in 12-TET. To let "
                   "Surge do the tuning instead, use --tuning-mode scala and load "
                   "19-edo.scl from the Tuning menu.",
    ),
    "lofi-keys": Preset(
        name="lofi-keys",
        description="Swung seventh chords with a sparse right hand.",
        bpm=82, bars=16, key="F", scale="Dorian",
        progression="jazz", bars_per_chord=1.0,
        parts=[
            PartSpec("chords", options=dict(rate="1/8", gate=0.55, velocity=72, spread=0)),
            PartSpec("melody", options=dict(rate="1/8", density=0.45,
                                            low="F4", high="F5", velocity=84)),
            PartSpec("bass", options=dict(style="fifth", rate="1/4", gate=0.8)),
        ],
        lanes=["macro1:sine:8:0.3:0.45"],
        swing=0.4, groove="laidback", humanize_ticks=10, humanize_velocity=14,
        surge_hint="Macro 1 -> a gentle lowpass wobble. An electric piano or "
                   "wavetable key patch takes the swing well.",
    ),
    "arp-hypnotic": Preset(
        name="arp-hypnotic",
        description="Up-down arp, pad and drone locked to one chord loop.",
        bpm=118, bars=16, key="G", scale="Natural Minor",
        progression="house", bars_per_chord=2.0,
        parts=[
            PartSpec("arp", options=dict(mode="updown", rate="1/16", octaves=2,
                                         gate=0.5, octave_shift=1)),
            PartSpec("pad", options=dict(velocity=52, spread=0, overlap=0.25,
                                         octave_shift=-1)),
            PartSpec("drone", options=dict(velocity=44, intervals=(0,))),
        ],
        lanes=["macro1:triangle:8:0.7:0.5", "macro4:drift:5:0.4:0.5"],
        humanize_velocity=6,
        surge_hint="Macro 1 -> cutoff, macro 4 -> wavetable position or unison spread.",
    ),
    "dual-scene": Preset(
        name="dual-scene",
        description="Bass on channel 1 and lead on channel 2 for Surge's Channel Split.",
        bpm=124, bars=16, key="D", scale="Phrygian",
        progression="andalusian", bars_per_chord=1.0,
        scene_split_channel=1,
        parts=[
            PartSpec("bass", channel=1, name="Bass (scene A)",
                     options=dict(style="octave", rate="1/8", gate=0.75)),
            PartSpec("arp", channel=2, name="Lead (scene B)",
                     options=dict(mode="thumb", rate="1/16", octaves=2, gate=0.45)),
        ],
        lanes=["macro1:ramp:8:0.8:0.5"],
        humanize_velocity=8,
        surge_hint="Macros are global across scenes, so macro 1 moves both the "
                   "bass and the lead patch.",
    ),
    "euclid-pulse": Preset(
        name="euclid-pulse",
        description="Interlocking euclidean rhythms at three pulse densities.",
        bpm=140, bars=16, key="A", scale="Pentatonic Min",
        progression=["i", "bVII", "i", "bVI"], bars_per_chord=2.0,
        parts=[
            PartSpec("euclid", name="Pulse 5", options=dict(pulses=5, steps=16, gate=0.3)),
            PartSpec("euclid", name="Pulse 7", options=dict(pulses=7, steps=16, rotation=2,
                                                            gate=0.25, pitch_mode="chord")),
            PartSpec("bass", options=dict(style="offbeat", rate="1/8", gate=0.4)),
        ],
        lanes=["macro1:sh:2:0.7:0.5", "macro2:sine:6:0.5:0.5"],
        surge_hint="Short percussive patch. Macro 1 -> pitch or filter jump, "
                   "macro 2 -> delay feedback.",
    ),
}


def get_preset(name: str) -> Preset:
    if name not in PRESETS:
        raise ValueError(f"unknown preset {name!r}. Available: {', '.join(sorted(PRESETS))}")
    return PRESETS[name]
