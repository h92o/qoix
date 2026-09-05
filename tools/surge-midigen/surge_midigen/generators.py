"""Pattern generators.

Parts are generated as plain note lists and rendered afterwards, so the musical
decisions stay independent of MPE channel juggling and microtonal bends.  Every
part reads the same :class:`ChordPlan`, which is what keeps the bass, the arp
and the melody in agreement about what bar 9 is doing.
"""

from __future__ import annotations

import random
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Sequence

from .automation import Lane
from .mpe import Expression, MPEAllocator, play_note
from .rhythm import (accent, euclidean, humanize_tick, humanize_velocity,
                     parse_division, swing_offset)
from .smf import Track, cents_to_bend
from .surge import SurgeConfig
from .theory import (Chord, PROGRESSIONS, Scale, parse_progression, parse_pitch_class,
                     spread_voicing, voice_lead)
from .tuning import Tuning

__all__ = [
    "Context", "Note", "Part", "ChordSlot", "ChordPlan", "build_chord_plan",
    "assign_mpe_channels", "resolve_overlaps",
    "chords_part", "arp_part", "bass_part", "melody_part", "pad_part",
    "euclid_part", "drone_part", "render_part", "GENERATORS",
]


@dataclass
class Context:
    """Everything a generator needs to know about the piece."""

    bpm: float = 120.0
    bars: int = 8
    ticks_per_beat: int = 480
    beats_per_bar: int = 4
    key: str = "C"
    scale_name: str = "Natural Minor"
    seed: int = 0
    config: SurgeConfig = field(default_factory=SurgeConfig)
    humanize_ticks: int = 0
    humanize_velocity: int = 0
    swing: float = 0.0
    groove: Optional[str] = None

    def __post_init__(self) -> None:
        self.rng = random.Random(self.seed)
        self.scale = Scale(parse_pitch_class(self.key), self.scale_name)

    @property
    def ticks_per_bar(self) -> int:
        return self.ticks_per_beat * self.beats_per_bar

    @property
    def total_ticks(self) -> int:
        return self.ticks_per_bar * self.bars

    def division(self, value) -> int:
        return parse_division(value, self.ticks_per_beat)

    def child_rng(self, salt: str) -> random.Random:
        """A stream per part, so adding a pad does not reshuffle the bassline."""
        return random.Random(f"{self.seed}:{salt}")


@dataclass
class Note:
    tick: int
    duration: int
    pitch: int
    velocity: int = 100
    release: int = 64
    expression: Optional[Expression] = None
    channel: Optional[int] = None    # set by assign_mpe_channels()


@dataclass
class Part:
    name: str
    notes: List[Note] = field(default_factory=list)
    channel: int = 1
    lanes: List[Lane] = field(default_factory=list)
    mpe: bool = False

    def sort(self) -> "Part":
        self.notes.sort(key=lambda n: (n.tick, n.pitch))
        return self

    @property
    def polyphonic(self) -> bool:
        """True if any two notes overlap -- decides whether bend-mode tuning
        can work on a single channel."""
        events = sorted((n.tick, n.tick + n.duration) for n in self.notes)
        latest_end = -1
        for start, end in events:
            if start < latest_end:
                return True
            latest_end = max(latest_end, end)
        return False


@dataclass
class ChordSlot:
    start: int
    end: int
    chord: Chord
    voicing: List[int]
    bass: int

    @property
    def duration(self) -> int:
        return self.end - self.start


class ChordPlan:
    """The harmonic grid every part reads from."""

    def __init__(self, slots: Sequence[ChordSlot]) -> None:
        self.slots = list(slots)

    def __iter__(self):
        return iter(self.slots)

    def __len__(self) -> int:
        return len(self.slots)

    def at(self, tick: int) -> ChordSlot:
        for slot in self.slots:
            if slot.start <= tick < slot.end:
                return slot
        return self.slots[-1]

    def tones_at(self, tick: int) -> List[int]:
        return self.at(tick).voicing


def build_chord_plan(ctx: Context, progression=None, bars_per_chord: float = 1.0,
                     low: int = 48, high: int = 76) -> ChordPlan:
    """Lay a progression across the bars, voice-leading between changes."""
    if progression is None:
        progression = PROGRESSIONS["minor-loop"]
    if isinstance(progression, str):
        if progression in PROGRESSIONS:
            symbols = PROGRESSIONS[progression]
        else:
            symbols = [s for s in progression.replace("|", " ").replace(",", " ").split() if s]
    else:
        symbols = list(progression)

    chords = parse_progression(symbols, ctx.key, ctx.scale_name)
    slot_ticks = max(1, int(round(bars_per_chord * ctx.ticks_per_bar)))
    slots: List[ChordSlot] = []
    previous: Optional[List[int]] = None
    tick = 0
    index = 0

    while tick < ctx.total_ticks:
        chord = chords[index % len(chords)]
        voicing = voice_lead(chord, previous, low, high)
        end = min(tick + slot_ticks, ctx.total_ticks)
        bass = chord.root
        while bass >= 48:
            bass -= 12          # land the root in C2..B2, where a bass lives
        slots.append(ChordSlot(tick, end, chord, voicing, bass))
        previous = voicing
        tick = end
        index += 1

    return ChordPlan(slots)


def _place(ctx: Context, rng: random.Random, tick: int, step_ticks: int,
           step_index: int) -> int:
    """Apply swing/groove then human timing to a grid position."""
    tick += swing_offset(step_index, step_ticks, ctx.swing, ctx.groove)
    return humanize_tick(rng, max(0, tick), ctx.humanize_ticks)


# ---------------------------------------------------------------------------
# Parts
# ---------------------------------------------------------------------------

def chords_part(ctx: Context, plan: ChordPlan, gate: float = 0.95,
                velocity: int = 78, spread: int = 0, rate: Optional[str] = None,
                octave_shift: int = 0, channel: int = 1, name: str = "Chords") -> Part:
    """Block chords, either one hit per slot or a repeating rhythmic stab."""
    rng = ctx.child_rng("chords")
    part = Part(name, channel=channel)

    for slot in plan:
        voicing = spread_voicing(slot.voicing, spread) if spread else slot.voicing
        if octave_shift:
            voicing = [pitch + 12 * octave_shift for pitch in voicing]
        if rate is None:
            hits = [(slot.start, slot.duration)]
            steps_per_bar = 1
        else:
            step = ctx.division(rate)
            hits = [(t, step) for t in range(slot.start, slot.end, step)]
            steps_per_bar = max(1, ctx.ticks_per_bar // step)
        for index, (tick, length) in enumerate(hits):
            when = _place(ctx, rng, tick, hits[0][1], index)
            duration = max(1, int(length * gate))
            level = accent(index, steps_per_bar, velocity)
            for offset, pitch in enumerate(voicing):
                part.notes.append(Note(
                    when, duration, pitch,
                    humanize_velocity(rng, max(1, level - offset * 2), ctx.humanize_velocity)))
    return part.sort()


ARP_MODES = ("up", "down", "updown", "downup", "converge", "diverge",
             "random", "order", "thumb")


def arp_part(ctx: Context, plan: ChordPlan, mode: str = "up", rate: str = "1/16",
             octaves: int = 2, gate: float = 0.6, velocity: int = 92,
             octave_shift: int = 0, channel: int = 1, name: str = "Arp") -> Part:
    """Classic arpeggiator over the chord plan."""
    if mode not in ARP_MODES:
        raise ValueError(f"unknown arp mode {mode!r}. Available: {', '.join(ARP_MODES)}")
    rng = ctx.child_rng("arp")
    part = Part(name, channel=channel)
    step = ctx.division(rate)
    steps_per_bar = max(1, ctx.ticks_per_bar // step)

    step_index = 0
    for slot in plan:
        pool: List[int] = []
        for octave in range(max(1, octaves)):
            pool += [n + 12 * (octave + octave_shift) for n in slot.voicing]
        pool = sorted(set(pool))

        if mode == "up":
            order = pool
        elif mode == "down":
            order = pool[::-1]
        elif mode == "updown":
            order = pool + pool[-2:0:-1]
        elif mode == "downup":
            order = pool[::-1] + pool[1:-1]
        elif mode in ("converge", "diverge"):
            # converge walks outside-in (low, high, low+1, high-1, ...);
            # diverge is the same path travelled backwards, middle-out.
            order = [pool[i // 2] if i % 2 == 0 else pool[-1 - i // 2]
                     for i in range(len(pool))]
            if mode == "diverge":
                order = order[::-1]
        elif mode == "thumb":
            order = [x for pair in ((pool[0], n) for n in pool[1:]) for x in pair]
        elif mode == "order":
            order = pool
        else:  # random
            order = None

        cursor = 0
        for tick in range(slot.start, slot.end, step):
            pitch = rng.choice(pool) if order is None else order[cursor % len(order)]
            cursor += 1
            when = _place(ctx, rng, tick, step, step_index)
            level = accent(step_index, steps_per_bar, velocity)
            part.notes.append(Note(when, max(1, int(step * gate)), pitch,
                                   humanize_velocity(rng, level, ctx.humanize_velocity)))
            step_index += 1
    return part.sort()


BASS_STYLES = ("root", "octave", "fifth", "walk", "offbeat", "driving",
               "pedal", "arp")


def bass_part(ctx: Context, plan: ChordPlan, style: str = "root", rate: str = "1/8",
              octave_shift: int = 0, gate: float = 0.85, velocity: int = 104,
              channel: int = 1, name: str = "Bass") -> Part:
    """Low end that tracks the progression."""
    if style not in BASS_STYLES:
        raise ValueError(f"unknown bass style {style!r}. Available: {', '.join(BASS_STYLES)}")
    rng = ctx.child_rng("bass")
    part = Part(name, channel=channel)
    step = ctx.division(rate)
    steps_per_bar = max(1, ctx.ticks_per_bar // step)
    shift = 12 * octave_shift
    step_index = 0
    pedal_root = plan.slots[0].bass + shift

    for slot in plan:
        root = slot.bass + shift
        fifth = root + 7
        scale_notes = ctx.scale.notes_in_range(root - 5, root + 14)

        for position, tick in enumerate(range(slot.start, slot.end, step)):
            beat = position % steps_per_bar

            if style == "root":
                pitch = root
            elif style == "octave":
                pitch = root + (12 if position % 2 else 0)
            elif style == "fifth":
                pitch = [root, root, fifth, root][position % 4]
            elif style == "pedal":
                pitch = pedal_root
            elif style == "arp":
                pitch = [root, root + 7, root + 12, root + 7][position % 4]
            elif style == "walk":
                target = root if position == 0 else rng.choice(scale_notes or [root])
                pitch = target
            elif style == "offbeat":
                if position % 2 == 0:
                    step_index += 1
                    continue
                pitch = root
            else:  # driving
                pitch = root if beat % 4 != 3 else root + 12

            when = _place(ctx, rng, tick, step, step_index)
            level = accent(position, steps_per_bar, velocity, downbeat=10, backbeat=4)
            part.notes.append(Note(when, max(1, int(step * gate)), pitch,
                                   humanize_velocity(rng, level, ctx.humanize_velocity)))
            step_index += 1
    return part.sort()


def melody_part(ctx: Context, plan: ChordPlan, rate: str = "1/8", density: float = 0.68,
                low: str = "C4", high: str = "C6", velocity: int = 96,
                leap: float = 0.18, gate: float = 0.9, channel: int = 1,
                name: str = "Lead") -> Part:
    """A generative line: a scale-constrained walk pulled toward chord tones.

    Strong beats prefer notes that are in the chord underneath, weak beats
    wander; small steps dominate with occasional leaps, which is what makes a
    random walk read as a melody rather than a sequence of accidents.
    """
    from .theory import parse_note

    rng = ctx.child_rng("melody")
    part = Part(name, channel=channel)
    step = ctx.division(rate)
    steps_per_bar = max(1, ctx.ticks_per_bar // step)
    low_note, high_note = parse_note(low), parse_note(high)
    available = ctx.scale.notes_in_range(low_note, high_note)
    if not available:
        raise ValueError("melody range contains no scale notes")

    current = min(available, key=lambda n: abs(n - (low_note + high_note) // 2))
    step_index = 0

    for tick in range(0, ctx.total_ticks, step):
        slot = plan.at(tick)
        strong = step_index % max(1, steps_per_bar // 2) == 0

        if rng.random() > (density + (0.2 if strong else 0.0)):
            step_index += 1
            continue

        index = available.index(current) if current in available else 0
        if rng.random() < leap:
            index += rng.choice([-5, -4, -3, 3, 4, 5])
        else:
            index += rng.choice([-2, -1, -1, 0, 1, 1, 2])
        index = max(0, min(len(available) - 1, index))
        pitch = available[index]

        if strong:
            tones = [n for n in range(low_note, high_note + 1)
                     if n % 12 in {t % 12 for t in slot.voicing}]
            if tones:
                pitch = min(tones, key=lambda n: abs(n - pitch))

        current = pitch
        when = _place(ctx, rng, tick, step, step_index)
        length = max(1, int(step * gate * rng.choice([1, 1, 1, 2, 2, 3])))
        level = accent(step_index, steps_per_bar, velocity, downbeat=8, backbeat=4)
        part.notes.append(Note(when, length, pitch,
                               humanize_velocity(rng, level, ctx.humanize_velocity)))
        step_index += 1
    return part.sort()


def pad_part(ctx: Context, plan: ChordPlan, velocity: int = 64, spread: int = 1,
             overlap: float = 0.12, octave_shift: int = 0, channel: int = 1,
             name: str = "Pad") -> Part:
    """Sustained chords that overlap slightly, so the patch's release tail never
    gaps between changes."""
    rng = ctx.child_rng("pad")
    part = Part(name, channel=channel)
    tail = int(ctx.ticks_per_bar * overlap)

    for slot in plan:
        voicing = spread_voicing(slot.voicing, spread) if spread else slot.voicing
        if octave_shift:
            voicing = [pitch + 12 * octave_shift for pitch in voicing]
        for offset, pitch in enumerate(voicing):
            part.notes.append(Note(
                slot.start, slot.duration + tail, pitch,
                humanize_velocity(rng, max(1, velocity - offset * 3), ctx.humanize_velocity),
                release=40))
    return part.sort()


def euclid_part(ctx: Context, plan: ChordPlan, pulses: int = 5, steps: int = 16,
                rotation: int = 0, rate: str = "1/16", gate: float = 0.5,
                velocity: int = 100, pitch_mode: str = "root", channel: int = 1,
                name: str = "Euclid") -> Part:
    """Euclidean rhythm, pitched from the chord underneath."""
    rng = ctx.child_rng("euclid")
    part = Part(name, channel=channel)
    step = ctx.division(rate)
    pattern = euclidean(pulses, steps, rotation)
    steps_per_bar = max(1, ctx.ticks_per_bar // step)

    step_index = 0
    for tick in range(0, ctx.total_ticks, step):
        if pattern[step_index % len(pattern)]:
            slot = plan.at(tick)
            if pitch_mode == "root":
                pitch = slot.bass + 24
            elif pitch_mode == "chord":
                pitch = slot.voicing[step_index % len(slot.voicing)]
            elif pitch_mode == "random":
                pitch = rng.choice(slot.voicing)
            else:
                raise ValueError(f"unknown pitch mode {pitch_mode!r}")
            when = _place(ctx, rng, tick, step, step_index)
            level = accent(step_index, steps_per_bar, velocity)
            part.notes.append(Note(when, max(1, int(step * gate)), pitch,
                                   humanize_velocity(rng, level, ctx.humanize_velocity)))
        step_index += 1
    return part.sort()


def drone_part(ctx: Context, plan: ChordPlan, velocity: int = 70,
               intervals: Sequence[int] = (0, 7), octave_shift: int = 0,
               channel: int = 1, name: str = "Drone") -> Part:
    """One long tone (plus optional intervals) under the whole piece."""
    part = Part(name, channel=channel)
    root = plan.slots[0].bass + 12 * octave_shift
    for interval in intervals:
        part.notes.append(Note(0, ctx.total_ticks, root + interval, velocity, release=32))
    return part.sort()


GENERATORS = {
    "chords": chords_part,
    "arp": arp_part,
    "bass": bass_part,
    "melody": melody_part,
    "pad": pad_part,
    "euclid": euclid_part,
    "drone": drone_part,
}


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

def render_part(track: Track, part: Part, ctx: Context,
                tuning: Optional[Tuning] = None, tuning_mode: str = "scala",
                allocator: Optional[MPEAllocator] = None,
                expression: Optional[Expression] = None) -> Dict[str, int]:
    """Write a part onto a track, applying MPE and microtuning as configured.

    Returns a small stats dict so the CLI can report what it did.
    """
    stats: Dict[str, int] = {"notes": 0, "bent": 0, "stolen": 0}
    warnings: List[str] = []
    use_mpe = ctx.config.mpe
    bend_range = ctx.config.bend_range if use_mpe else 2

    if use_mpe and allocator is None:
        allocator = MPEAllocator(ctx.config.channels())

    if (tuning is not None and tuning_mode == "bend" and not use_mpe
            and part.polyphonic):
        warnings.append(
            f"part '{part.name}' is polyphonic but bend-mode tuning is writing to a "
            f"single channel: pitch bend is per channel, so the whole chord bends "
            f"together. Use --mpe, or --tuning-mode scala and load the .scl in Surge.")

    out_of_range = 0
    for note in part.notes:
        detune = 0.0
        if tuning is not None and tuning_mode == "bend":
            detune = tuning.deviation_cents(note.pitch)
            if abs(detune) > bend_range * 100:
                out_of_range += 1

        note_expression = note.expression or expression
        if detune:
            note_expression = _with_detune(note_expression, detune)
            stats["bent"] += 1

        if use_mpe:
            # Channels are normally assigned up front across every part at once
            # (see assign_mpe_channels); falling back to the allocator here keeps
            # render_part usable on its own.
            channel = (note.channel if note.channel is not None
                       else allocator.acquire(note.tick, note.duration))
            play_note(track, note.tick, note.duration, note.pitch, note.velocity,
                      channel, note_expression, bend_range, ctx.ticks_per_beat,
                      ctx.bpm, note.release)
        else:
            channel = part.channel
            if note_expression is not None and not note_expression.is_static:
                play_note(track, note.tick, note.duration, note.pitch, note.velocity,
                          channel, note_expression, bend_range, ctx.ticks_per_beat,
                          ctx.bpm, note.release, reset_after=False)
            else:
                if detune:
                    track.pitch_bend(note.tick, cents_to_bend(detune, bend_range), channel)
                track.note(note.tick, note.duration, note.pitch, note.velocity,
                           channel, note.release)
        stats["notes"] += 1

    if out_of_range:
        warnings.append(
            f"part '{part.name}': {out_of_range} note(s) need more than the "
            f"{bend_range}-semitone bend range and were clamped. Narrow the note "
            f"range, move the tuning root, or raise --bend-range.")
    if use_mpe and allocator is not None:
        stats["stolen"] = allocator.steals
    stats["warnings"] = warnings
    return stats


def resolve_overlaps(parts: Sequence[Part], min_gap: int = 2) -> Dict[str, int]:
    """Stop the same pitch sounding twice at once on one channel.

    A synth given two note-ons for one pitch on one channel before any note-off
    retriggers the voice, and then the first note-off silences the second note.
    Generators produce that honestly -- a melody note held across its own
    repeat, a pad whose release tail reaches a chord that shares the pitch, an
    arp doubling a pad an octave down -- so it is cleaned up once, here, after
    channels are known.

    The sweep keeps whichever note is sounding and, for each note that starts
    inside it, either drops the newcomer (when it would be entirely covered, so
    it could not have been heard) or shortens the sounding note to release just
    before it. Returns counts of what it changed.
    """
    grouped: Dict[tuple, List[Note]] = {}
    for part in parts:
        for note in part.notes:
            channel = note.channel if note.channel is not None else part.channel
            grouped.setdefault((channel, note.pitch), []).append(note)

    dropped: set = set()
    trimmed = 0

    for notes in grouped.values():
        # Longest first at any given tick, so a sustained note becomes the one
        # that survives and the short doubling on top of it is what gets cut.
        notes.sort(key=lambda n: (n.tick, -n.duration))
        sounding: Optional[Note] = None
        for note in notes:
            if sounding is None:
                sounding = note
                continue
            sounding_end = sounding.tick + sounding.duration
            if sounding_end <= note.tick:
                sounding = note
            elif sounding_end >= note.tick + note.duration:
                dropped.add(id(note))          # inaudible under the held note
            else:
                sounding.duration = max(1, note.tick - sounding.tick - min_gap)
                trimmed += 1
                sounding = note

    if dropped:
        for part in parts:
            part.notes = [n for n in part.notes if id(n) not in dropped]

    return {"trimmed": trimmed, "dropped": len(dropped)}


def assign_mpe_channels(parts: Sequence[Part], allocator: MPEAllocator) -> int:
    """Hand out member channels across *all* parts in one time-ordered pass.

    Allocating part by part looks fine and is wrong: every part restarts at
    tick 0, so by the second part the allocator believes every channel is busy
    until the end of the first one and starts stealing.  Notes have to be
    considered in the order they actually sound.
    """
    notes = sorted((note for part in parts for note in part.notes),
                   key=lambda n: (n.tick, n.pitch))
    for note in notes:
        note.channel = allocator.acquire(note.tick, note.duration)
    return allocator.steals


def _with_detune(expression: Optional[Expression], cents: float) -> Expression:
    if expression is None:
        return Expression(detune_cents=cents)
    clone = Expression(**{**expression.__dict__})
    clone.detune_cents = expression.detune_cents + cents
    return clone
