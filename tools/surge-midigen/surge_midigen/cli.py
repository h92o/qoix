"""Command line interface.

    surge-midigen song --preset berlin-school -o seq.mid
    surge-midigen song --part arp:mode=updown --part bass:style=octave -o my.mid
    surge-midigen list presets
    surge-midigen inspect seq.mid
"""

from __future__ import annotations

import argparse
import os
import random
import sys
from typing import Optional, Sequence

from . import __version__
from .automation import RANDOM_SHAPES, SHAPES
from .generators import GENERATORS
from .mpe import EXPRESSION_PRESETS
from .presets import PRESETS
from .rhythm import GROOVES
from .smf import parse_midi_file
from .song import build_song
from .surge import MACRO_CC, describe_cc
from .theory import PROGRESSIONS, SCALES, note_name
from .tuning import BUILTIN_SCALES, load_tuning


def _time_signature(text: str):
    try:
        numerator, denominator = text.split("/")
        return int(numerator), int(denominator)
    except Exception:
        raise argparse.ArgumentTypeError(f"time signature must look like 4/4, got {text!r}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="surge-midigen",
        description="Generate MIDI files for the Surge XT synthesizer.")
    parser.add_argument("--version", action="version", version=f"surge-midigen {__version__}")
    sub = parser.add_subparsers(dest="command", required=True)

    song = sub.add_parser("song", help="generate a MIDI file")
    song.add_argument("-o", "--out", required=True, help="output .mid path")
    song.add_argument("--preset", choices=sorted(PRESETS),
                      help="start from a template; other flags override it")
    song.add_argument("--part", action="append", dest="parts", metavar="SPEC",
                      help="generator[:key=value...], repeatable. "
                           f"Generators: {', '.join(sorted(GENERATORS))}")
    song.add_argument("--cc", "--macro", action="append", dest="lanes", metavar="SPEC",
                      help="automation lane cc:shape[:period[:depth[:center[:phase]]]], "
                           "repeatable. CC may be a number, macro1-macro8, or a name")
    song.add_argument("--bpm", type=float)
    song.add_argument("--bars", type=int)
    song.add_argument("--key", help="C, F#, Bb ...")
    song.add_argument("--scale", choices=sorted(SCALES), metavar="NAME")
    song.add_argument("--progression", help="a named progression or roman numerals "
                                            "like 'i bVI bIII bVII'")
    song.add_argument("--bars-per-chord", type=float)
    song.add_argument("--seed", type=int, default=0,
                      help="0 by default, so the same flags give the same file")
    song.add_argument("--random-seed", action="store_true",
                      help="pick a seed at random and print it")
    song.add_argument("--swing", type=float, help="0..1, applied to odd grid steps")
    song.add_argument("--groove", choices=sorted(GROOVES))
    song.add_argument("--humanize", type=int, metavar="TICKS")
    song.add_argument("--humanize-vel", type=int, metavar="AMOUNT")
    song.add_argument("--time-sig", type=_time_signature, default=(4, 4))
    song.add_argument("--ppq", type=int, default=480, help="ticks per quarter note")
    song.add_argument("--title")

    mpe = song.add_argument_group("MPE")
    mpe.add_argument("--mpe", dest="mpe", action="store_true", default=None,
                     help="one channel per note, with per-note bend, pressure and CC 74")
    mpe.add_argument("--no-mpe", dest="mpe", action="store_false")
    mpe.add_argument("--bend-range", type=int, help="per-note bend range (Surge default 48)")
    mpe.add_argument("--member-channels", type=int, help="1-15, default 15")
    mpe.add_argument("--expression", choices=sorted(EXPRESSION_PRESETS),
                     help="per-note articulation applied to parts that do not set one")

    tune = song.add_argument_group("tuning")
    tune.add_argument("--tuning", help="built-in name, edo:N, or a path to a .scl file")
    tune.add_argument("--tuning-mode", choices=("scala", "bend"),
                      help="'scala' writes plain notes for Surge to retune; "
                           "'bend' bakes the tuning in as pitch bend")
    tune.add_argument("--tuning-root", type=int, default=60,
                      help="MIDI key that sounds the 1/1 (default 60)")

    surge_group = song.add_argument_group("Surge scenes")
    surge_group.add_argument("--scene-split", type=int, metavar="CHANNEL",
                             help="note that the file targets Channel Split mode "
                                  "with the split at this channel")
    song.add_argument("--allow-reserved-cc", action="store_true",
                      help="permit automation on protocol CCs (rarely what you want)")
    song.add_argument("-q", "--quiet", action="store_true")

    listing = sub.add_parser("list", help="show available options")
    listing.add_argument("topic", nargs="?", default="all",
                         choices=("all", "presets", "scales", "progressions", "generators",
                                  "shapes", "grooves", "tunings", "cc", "expressions"))

    inspect = sub.add_parser("inspect", help="summarise a MIDI file")
    inspect.add_argument("path")
    inspect.add_argument("--events", type=int, default=0,
                         help="also print the first N events of each track")

    tuning = sub.add_parser("tuning", help="show a tuning's degrees and 12-TET deviations")
    tuning.add_argument("name", help="built-in name, edo:N, or a .scl path")
    tuning.add_argument("--root", type=int, default=60)
    tuning.add_argument("--from-key", type=int, default=60)
    tuning.add_argument("--keys", type=int, default=13)

    return parser


def _run_song(args) -> int:
    seed = random.randrange(1, 1_000_000) if args.random_seed else args.seed
    result = build_song(
        preset=args.preset,
        bpm=args.bpm, bars=args.bars, key=args.key, scale=args.scale,
        progression=args.progression, bars_per_chord=args.bars_per_chord,
        parts=args.parts, lanes=args.lanes,
        mpe=args.mpe, bend_range=args.bend_range,
        member_channels=args.member_channels, scene_split=args.scene_split,
        tuning=args.tuning, tuning_mode=args.tuning_mode, tuning_root=args.tuning_root,
        expression=args.expression, seed=seed,
        swing=args.swing, groove=args.groove,
        humanize=args.humanize, humanize_velocity=args.humanize_vel,
        ticks_per_beat=args.ppq, time_signature=args.time_sig,
        title=args.title, strict_cc=not args.allow_reserved_cc,
    )

    directory = os.path.dirname(os.path.abspath(args.out))
    if directory:
        os.makedirs(directory, exist_ok=True)
    result.save(args.out)

    if not args.quiet:
        print(result.summary(args.out))
        if args.random_seed:
            print(f"  Seed: {seed} (pass --seed {seed} to reproduce)")
    return 0


def _run_list(topic: str) -> int:
    show_all = topic == "all"

    if show_all or topic == "presets":
        print("Presets:")
        for name, preset in sorted(PRESETS.items()):
            print(f"  {name:<16} {preset.description}")
            print(f"  {'':<16} {preset.bpm:g} BPM, {preset.key} {preset.scale}, "
                  f"{preset.bars} bars"
                  f"{', MPE' if preset.mpe else ''}"
                  f"{', tuning ' + preset.tuning if preset.tuning else ''}")
    if show_all or topic == "generators":
        print("\nGenerators (use with --part):")
        for name, function in sorted(GENERATORS.items()):
            summary = (function.__doc__ or "").strip().splitlines()[0]
            print(f"  {name:<10} {summary}")
    if show_all or topic == "scales":
        print("\nScales:")
        for name, intervals in SCALES.items():
            print(f"  {name:<16} {intervals}")
    if show_all or topic == "progressions":
        print("\nProgressions:")
        for name, chords in PROGRESSIONS.items():
            print(f"  {name:<14} {' '.join(chords)}")
    if show_all or topic == "shapes":
        print("\nAutomation shapes:")
        print("  " + ", ".join(sorted(SHAPES)))
        print("  random: " + ", ".join(RANDOM_SHAPES))
    if show_all or topic == "grooves":
        print("\nGrooves:")
        for name, offsets in sorted(GROOVES.items()):
            print(f"  {name:<12} {offsets}")
    if show_all or topic == "expressions":
        print("\nMPE expressions:")
        for name in sorted(EXPRESSION_PRESETS):
            print(f"  {name}")
    if show_all or topic == "tunings":
        print("\nBuilt-in tunings (also 'edo:N' or any .scl path):")
        for name in sorted(BUILTIN_SCALES):
            print(f"  {name}")
    if show_all or topic == "cc":
        print("\nSurge XT controllers:")
        for macro, controller in sorted(MACRO_CC.items()):
            print(f"  CC {controller:<3} macro {macro}")
        for controller in (1, 2, 11, 64, 66, 74):
            print(f"  CC {controller:<3} {describe_cc(controller)}")
    return 0


def _run_inspect(path: str, event_limit: int) -> int:
    data = parse_midi_file(path)
    ticks_per_beat = data["ticks_per_beat"]
    print(f"{path}: SMF format {data['format']}, {len(data['tracks'])} tracks, "
          f"{ticks_per_beat} PPQ")

    tempo = next((event["bpm"] for track in data["tracks"] for event in track
                  if event["type"] == "meta" and event["meta_type"] == 0x51), None)
    end = max((event["tick"] for track in data["tracks"] for event in track), default=0)
    if tempo:
        seconds = end / ticks_per_beat * 60.0 / tempo
        print(f"  tempo {tempo:g} BPM, length {end} ticks "
              f"({end / (ticks_per_beat * 4):.1f} bars at 4/4, {seconds:.1f}s)")

    for index, track in enumerate(data["tracks"]):
        name = next((event.get("text", "") for event in track
                     if event["type"] == "meta" and event["meta_type"] == 0x03), "")
        notes = [event for event in track if event["type"] == "note_on"]
        controllers = sorted({event["controller"] for event in track
                              if event["type"] == "cc"})
        channels = sorted({event["channel"] for event in track if "channel" in event})
        line = f"  [{index}] {name or '(unnamed)':<20} {len(track):5d} events"
        if notes:
            low = min(event["note"] for event in notes)
            high = max(event["note"] for event in notes)
            line += f", {len(notes)} notes {note_name(low)}-{note_name(high)}"
        if channels:
            line += f", ch {channels[0]}-{channels[-1]}" if len(channels) > 1 \
                else f", ch {channels[0]}"
        print(line)
        if controllers:
            print("       CC: " + ", ".join(
                f"{c} ({describe_cc(c)})" for c in controllers))
        bends = [event for event in track if event["type"] == "pitch_bend"]
        if bends:
            print(f"       pitch bend: {len(bends)} events, "
                  f"{min(b['value'] for b in bends)}..{max(b['value'] for b in bends)}")
        for event in track[:event_limit]:
            print(f"       {event}")
    return 0


def _run_tuning(name: str, root: int, from_key: int, keys: int) -> int:
    tuning = load_tuning(name, root)
    print(tuning.summary())
    print(f"{'key':>5} {'name':>5} {'cents from 1/1':>15} {'Hz':>10} "
          f"{'vs 12-TET':>11}")
    for note in range(from_key, from_key + keys):
        print(f"{note:5d} {note_name(note):>5} {tuning.cents_from_root(note):15.3f} "
              f"{tuning.frequency(note):10.3f} {tuning.deviation_cents(note):+10.2f}c")
    return 0


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if args.command == "song":
            return _run_song(args)
        if args.command == "list":
            return _run_list(args.topic)
        if args.command == "inspect":
            return _run_inspect(args.path, args.events)
        if args.command == "tuning":
            return _run_tuning(args.name, args.root, args.from_key, args.keys)
    except BrokenPipeError:
        return 0            # stdout closed early, e.g. piped into head
    except (ValueError, FileNotFoundError, OSError) as error:
        print(f"surge-midigen: {error}", file=sys.stderr)
        return 2
    parser.error("no command")
    return 2


if __name__ == "__main__":
    sys.exit(main())
