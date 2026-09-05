#!/usr/bin/env python3
"""Building a song from the Python API instead of the CLI.

Shows the three things the CLI cannot express as neatly: a hand-written chord
plan, a part built note by note, and per-note expression chosen per note.

    python3 tools/surge-midigen/examples/custom_song.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from surge_midigen import MidiFile, SurgeConfig
from surge_midigen.automation import Lane, render_lane
from surge_midigen.generators import (Context, Note, Part, assign_mpe_channels,
                                      bass_part, build_chord_plan, render_part,
                                      resolve_overlaps)
from surge_midigen.mpe import Expression, MPEAllocator
from surge_midigen.surge import write_mpe_setup
from surge_midigen.theory import parse_note

OUTPUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "output")


def main() -> int:
    os.makedirs(OUTPUT, exist_ok=True)

    context = Context(bpm=88, bars=8, key="A", scale_name="Dorian", seed=17,
                      config=SurgeConfig(mpe=True), humanize_ticks=6,
                      humanize_velocity=10)
    plan = build_chord_plan(context, "im7 IV7 im7 bVImaj7", bars_per_chord=2.0)

    # A hand-written riff, with a different articulation on the long notes.
    riff = Part("Riff")
    beat = context.ticks_per_beat
    figure = [("A4", 0, 1), ("C5", 1, 1), ("E5", 2, 2), ("D5", 4, 1),
              ("C5", 5, 1), ("A4", 6, 2)]
    for bar in range(context.bars):
        for name, offset, length in figure:
            duration = int(beat * length * 0.9)
            riff.notes.append(Note(
                tick=bar * context.ticks_per_bar + int(offset * beat),
                duration=duration,
                pitch=parse_note(name),
                velocity=98 if offset == 0 else 86,
                expression=Expression(pressure="swell", pressure_peak=112,
                                      vibrato_cents=24, vibrato_hz=5.2)
                if length > 1 else
                Expression(pressure="decay", timbre_from=104, timbre_to=44),
            ))

    bass = bass_part(context, plan, style="walk", rate="1/8", gate=0.7)
    parts = [riff.sort(), bass]

    allocator = MPEAllocator(context.config.channels())
    assign_mpe_channels(parts, allocator)
    resolve_overlaps(parts)

    midi = MidiFile()
    conductor = midi.add_track("custom")
    conductor.tempo(0, context.bpm)
    conductor.time_signature(0, 4, 4)
    write_mpe_setup(conductor)

    automation = midi.add_track("Automation")
    render_lane(automation, Lane("macro1", "arch", period_bars=4, depth=0.8),
                0, context.total_ticks, context.ticks_per_beat)

    for part in parts:
        render_part(midi.add_track(part.name), part, context, allocator=allocator)

    path = os.path.join(OUTPUT, "custom.mid")
    midi.save(path)
    print(f"wrote {path}: {midi.event_count()} events across {len(midi.tracks)} tracks")
    return 0


if __name__ == "__main__":
    sys.exit(main())
