"""Assembling parts into a finished MIDI file.

Track layout is deliberately boring so any DAW imports it predictably:

    0  Conductor   tempo, time signature, chord markers, MPE setup
    1  Automation  macro / CC lanes (only if there are any)
    2+ one track per part

In MPE mode every part shares one channel allocator, because the member
channels are a single pool -- two parts each starting at channel 2 would tread
on each other's pitch bend.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Sequence, Tuple

from .automation import Lane, parse_lane_spec, render_lane
from .generators import (Context, GENERATORS, ChordPlan, Part, assign_mpe_channels,
                         build_chord_plan, render_part, resolve_overlaps)
from .mpe import MPEAllocator, get_expression
from .presets import PartSpec, Preset, get_preset
from .smf import MidiFile
from .surge import SurgeConfig
from .theory import note_name
from .tuning import Tuning, load_tuning

__all__ = ["BuildResult", "build_song", "parse_part_spec"]


def _coerce(text: str) -> Any:
    text = text.strip()
    if "," in text:
        return tuple(_coerce(part) for part in text.split(","))
    lowered = text.lower()
    if lowered in ("true", "yes", "on"):
        return True
    if lowered in ("false", "no", "off"):
        return False
    if re.fullmatch(r"-?\d+", text):
        return int(text)
    if re.fullmatch(r"-?\d*\.\d+", text):
        return float(text)
    return text


def parse_part_spec(spec: str) -> PartSpec:
    """`'arp:mode=updown:rate=1/16:channel=2'` -> a :class:`PartSpec`.

    Bare `name=value` pairs go straight to the generator, so anything a
    generator accepts is reachable from the command line without a dedicated
    flag for each one.
    """
    parts = [p.strip() for p in str(spec).split(":") if p.strip()]
    if not parts:
        raise ValueError(f"empty part spec: {spec!r}")
    generator = parts[0]
    if generator not in GENERATORS:
        raise ValueError(f"unknown generator {generator!r}. Available: "
                         f"{', '.join(sorted(GENERATORS))}")

    options: Dict[str, Any] = {}
    channel = 1
    name: Optional[str] = None
    expression: Optional[str] = None

    for item in parts[1:]:
        if "=" not in item:
            raise ValueError(f"expected key=value in part spec, got {item!r}")
        key, value = item.split("=", 1)
        key = key.strip()
        if key == "channel":
            channel = int(value)
        elif key == "name":
            name = value
        elif key == "expression":
            expression = value
        else:
            options[key] = _coerce(value)

    return PartSpec(generator, name=name, channel=channel,
                    expression=expression, options=options)


@dataclass
class BuildResult:
    midi: MidiFile
    context: Context
    plan: ChordPlan
    parts: List[Part] = field(default_factory=list)
    lanes: List[Tuple[Lane, int]] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)
    setup_notes: List[str] = field(default_factory=list)
    surge_hint: str = ""
    tuning: Optional[Tuning] = None
    tuning_mode: str = "scala"
    overlaps_resolved: Dict[str, int] = field(default_factory=dict)

    def save(self, path: str) -> str:
        return self.midi.save(path)

    def summary(self, path: Optional[str] = None) -> str:
        ctx = self.context
        lines: List[str] = []
        if path:
            lines.append(f"Wrote {path}")
        lines.append(
            f"  {ctx.bars} bars at {ctx.bpm:g} BPM, {ctx.beats_per_bar}/4, "
            f"{ctx.ticks_per_beat} PPQ, key {ctx.key} {ctx.scale_name}, seed {ctx.seed}")
        lines.append("  Harmony: " + " | ".join(
            dict.fromkeys(str(slot.chord) for slot in self.plan)))

        for part in self.parts:
            if not part.notes:
                lines.append(f"  {part.name:<18} (empty)")
                continue
            low = min(n.pitch for n in part.notes)
            high = max(n.pitch for n in part.notes)
            where = "MPE ch 2+" if ctx.config.mpe else f"ch {part.channel}"
            lines.append(f"  {part.name:<18} {len(part.notes):4d} notes  "
                         f"{note_name(low)}-{note_name(high):<4}  {where}")

        for lane, count in self.lanes:
            lines.append(f"  {'automation':<18} {count:4d} events  {lane.describe()}")

        if self.tuning is not None:
            lines.append(f"  Tuning: {self.tuning.summary()} [{self.tuning_mode} mode]")
        trimmed = self.overlaps_resolved.get("trimmed", 0)
        dropped = self.overlaps_resolved.get("dropped", 0)
        if trimmed or dropped:
            lines.append(
                f"  Same-pitch overlaps on one channel: {trimmed} note(s) shortened, "
                f"{dropped} dropped as inaudible under a held note")

        if self.setup_notes:
            lines.append("\nSurge XT setup:")
            lines += [f"  - {note}" for note in self.setup_notes]
        if self.surge_hint:
            lines.append(f"  - {self.surge_hint}")
        if self.warnings:
            lines.append("\nWarnings:")
            lines += [f"  ! {warning}" for warning in self.warnings]
        return "\n".join(lines)


def build_song(preset: Optional[str] = None, *,
               bpm: Optional[float] = None,
               bars: Optional[int] = None,
               key: Optional[str] = None,
               scale: Optional[str] = None,
               progression: Any = None,
               bars_per_chord: Optional[float] = None,
               parts: Optional[Sequence[Any]] = None,
               lanes: Optional[Sequence[Any]] = None,
               mpe: Optional[bool] = None,
               bend_range: Optional[int] = None,
               member_channels: Optional[int] = None,
               scene_split: Optional[int] = None,
               tuning: Optional[str] = None,
               tuning_mode: Optional[str] = None,
               tuning_root: int = 60,
               expression: Optional[str] = None,
               seed: int = 0,
               swing: Optional[float] = None,
               groove: Optional[str] = None,
               humanize: Optional[int] = None,
               humanize_velocity: Optional[int] = None,
               ticks_per_beat: int = 480,
               time_signature: Tuple[int, int] = (4, 4),
               title: Optional[str] = None,
               strict_cc: bool = True) -> BuildResult:
    """Build a complete song.  Explicit arguments win over the preset's values."""

    template: Optional[Preset] = get_preset(preset) if preset else None

    def pick(value, attribute, fallback):
        if value is not None:
            return value
        if template is not None:
            return getattr(template, attribute)
        return fallback

    config = SurgeConfig(
        mpe=bool(pick(mpe, "mpe", False)),
        member_channels=member_channels or 15,
        bend_range=bend_range or 48,
        scene_split_channel=pick(scene_split, "scene_split_channel", None),
    )

    ctx = Context(
        bpm=float(pick(bpm, "bpm", 120.0)),
        bars=int(pick(bars, "bars", 8)),
        ticks_per_beat=ticks_per_beat,
        beats_per_bar=time_signature[0],
        key=str(pick(key, "key", "C")),
        scale_name=str(pick(scale, "scale", "Natural Minor")),
        seed=seed,
        config=config,
        humanize_ticks=int(pick(humanize, "humanize_ticks", 0)),
        humanize_velocity=int(pick(humanize_velocity, "humanize_velocity", 0)),
        swing=float(pick(swing, "swing", 0.0)),
        groove=pick(groove, "groove", None),
    )

    plan = build_chord_plan(
        ctx,
        pick(progression, "progression", "minor-loop"),
        float(pick(bars_per_chord, "bars_per_chord", 1.0)),
    )

    tuning_name = pick(tuning, "tuning", None)
    tuning_obj = load_tuning(tuning_name, tuning_root) if tuning_name else None
    mode = str(pick(tuning_mode, "tuning_mode", "scala"))
    if mode not in ("scala", "bend"):
        raise ValueError(f"tuning mode must be 'scala' or 'bend', got {mode!r}")

    # -- part specs -------------------------------------------------------
    specs: List[PartSpec] = []
    if parts:
        for item in parts:
            specs.append(item if isinstance(item, PartSpec) else parse_part_spec(str(item)))
    elif template is not None:
        specs = list(template.parts)
    else:
        specs = [PartSpec("chords"), PartSpec("bass")]

    lane_specs = list(lanes) if lanes is not None else (
        list(template.lanes) if template is not None else [])

    midi = MidiFile(ticks_per_beat=ticks_per_beat, fmt=1)
    conductor = midi.add_track(title or (template.name if template else "surge-midigen"))
    conductor.tempo(0, ctx.bpm)
    conductor.time_signature(0, time_signature[0], time_signature[1])
    for slot in plan:
        conductor.marker(slot.start, str(slot.chord))
    config.apply(conductor, 0)

    result = BuildResult(midi=midi, context=ctx, plan=plan,
                         tuning=tuning_obj, tuning_mode=mode)

    # -- automation -------------------------------------------------------
    if lane_specs:
        automation = midi.add_track("Automation")
        lane_rng = ctx.child_rng("lanes")
        for spec in lane_specs:
            lane = spec if isinstance(spec, Lane) else parse_lane_spec(str(spec))
            count = render_lane(automation, lane, 0, ctx.total_ticks,
                                ctx.ticks_per_beat, ctx.beats_per_bar,
                                lane_rng, strict=strict_cc)
            result.lanes.append((lane, count))

    # -- parts ------------------------------------------------------------
    default_expression = pick(expression, "expression", None)
    generated: List[Tuple[PartSpec, Part]] = []

    for spec in specs:
        generator = GENERATORS[spec.generator]
        name = spec.name or spec.generator.title()
        try:
            part = generator(ctx, plan, channel=spec.channel, name=name, **spec.options)
        except TypeError as error:
            raise ValueError(
                f"part '{spec.generator}' rejected its options {spec.options}: {error}"
            ) from None
        generated.append((spec, part))

    allocator = None
    if config.mpe:
        allocator = MPEAllocator(config.channels())
        assign_mpe_channels([part for _, part in generated], allocator)

    result.overlaps_resolved = resolve_overlaps([part for _, part in generated])

    for spec, part in generated:
        track = midi.add_track(part.name)
        articulation = get_expression(spec.expression or default_expression)
        stats = render_part(track, part, ctx, tuning_obj, mode, allocator, articulation)
        result.warnings += stats.get("warnings", [])
        result.parts.append(part)

    total_notes = sum(len(part.notes) for part in result.parts)
    dropped = result.overlaps_resolved.get("dropped", 0)
    if total_notes and dropped > total_notes * 0.1 and not config.mpe:
        result.warnings.append(
            f"{dropped} note(s) were dropped because parts share pitches on the same "
            f"MIDI channel. Move a part to its own channel (part spec 'channel=2'), "
            f"shift its register ('octave_shift=1'), or use --mpe.")

    if allocator is not None and allocator.steals:
        result.warnings.append(
            f"{allocator.steals} note(s) reused a member channel that was still "
            f"sounding. Raise --member-channels or thin the arrangement.")

    result.setup_notes = config.setup_notes()
    if tuning_obj is not None:
        if mode == "bend":
            result.setup_notes.append(
                "Tuning is baked in as pitch bend - leave Surge XT in 12-TET, "
                "or the tuning gets applied twice.")
        else:
            result.setup_notes.append(
                f"Load the matching .scl ({tuning_name}) from Surge XT's Tuning "
                f"menu; the notes here address scale degrees, not 12-TET pitches.")
    result.surge_hint = template.surge_hint if template else ""
    return result
