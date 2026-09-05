"""Per-note expression: MPE channel allocation, pitch glides, vibrato,
pressure and timbre.

MPE is where Surge XT gets interesting from a generator's point of view.  Each
note lands on its own member channel, so pitch bend, channel pressure and
CC 74 stop being one shared gesture and become per-note articulation -- and
per-note pitch bend is also what makes exact microtuning playable without
loading a tuning file (see `tuning.py`).
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Dict, Optional, Sequence

from .smf import Track, BEND_CENTER, cents_to_bend

MAX_EXPRESSION_STEPS = 48

__all__ = ["MPEAllocator", "Expression", "play_note", "reset_channel",
           "EXPRESSION_PRESETS", "get_expression"]


class MPEAllocator:
    """Hands out member channels, avoiding a channel that is still sounding.

    Reusing a live channel is the classic MPE bug: the new note's pitch bend
    yanks the old note with it.  This picks the channel that has been idle
    longest and only steals when every channel is genuinely busy.
    """

    def __init__(self, channels: Sequence[int]) -> None:
        if not channels:
            raise ValueError("MPE allocator needs at least one member channel")
        self.channels = list(channels)
        self._free_at: Dict[int, int] = {c: -1 for c in self.channels}
        self._claimed_at: Dict[int, int] = {c: -1 for c in self.channels}
        self.steals = 0

    def acquire(self, tick: int, duration: int) -> int:
        free = [c for c in self.channels if self._free_at[c] <= tick]
        if free:
            channel = min(free, key=lambda c: (self._free_at[c], self.channels.index(c)))
        else:
            # Everything is sounding: take the note that started longest ago.
            channel = min(self.channels, key=lambda c: (self._claimed_at[c], c))
            self.steals += 1
        self._free_at[channel] = tick + duration
        self._claimed_at[channel] = tick
        return channel

    def busy_at(self, tick: int) -> int:
        return sum(1 for c in self.channels if self._free_at[c] > tick)


def reset_channel(track: Track, tick: int, channel: int,
                  reset_timbre: bool = True) -> None:
    """Return a member channel to neutral so the next note starts clean."""
    track.pitch_bend(tick, BEND_CENTER, channel)
    track.channel_pressure(tick, 0, channel)
    if reset_timbre:
        track.cc(tick, 74, 64, channel)


@dataclass
class Expression:
    """Per-note articulation.  Every field is optional; the defaults are inert."""

    detune_cents: float = 0.0          # static offset, e.g. from a tuning table
    glide_from: float = 0.0            # semitones below/above to slide in from
    glide_ticks: int = 0               # how long the slide takes
    glide_curve: float = 2.0           # >1 eases out, 1.0 is linear
    vibrato_cents: float = 0.0
    vibrato_hz: float = 5.0
    vibrato_delay: float = 0.35        # fraction of the note before full depth
    pressure: str = "none"             # none | flat | swell | decay | attack
    pressure_peak: int = 100
    timbre_from: Optional[int] = None  # CC 74, 0-127
    timbre_to: Optional[int] = None
    resolution_ticks: int = 30         # expression write grid

    @property
    def is_static(self) -> bool:
        return (self.glide_ticks <= 0 and self.vibrato_cents == 0
                and self.pressure in ("none",)
                and self.timbre_from is None and self.timbre_to is None)


def _pressure_value(shape: str, position: float, peak: int) -> Optional[int]:
    if shape == "none":
        return None
    if shape == "flat":
        level = 1.0
    elif shape == "swell":
        level = math.sin(math.pi * position) ** 0.7
    elif shape == "decay":
        level = math.exp(-3.0 * position)
    elif shape == "attack":
        level = 1.0 - math.exp(-6.0 * position)
    else:
        raise ValueError(f"unknown pressure shape {shape!r}")
    return max(0, min(127, int(round(peak * level))))


def play_note(track: Track, tick: int, duration: int, note: int, velocity: int,
              channel: int, expression: Optional[Expression] = None,
              bend_range: float = 48.0, ticks_per_beat: int = 480,
              bpm: float = 120.0, release_velocity: int = 64,
              reset_after: bool = True) -> None:
    """Write one expressive note onto its own channel.

    Expression is written at the note's start tick (and onward), which the SMF
    layer orders ahead of the note-on, so Surge sees the starting bend, timbre
    and pressure before the voice is created.
    """
    expression = expression or Expression()
    end = tick + duration

    if expression.is_static:
        if expression.detune_cents:
            track.pitch_bend(tick, cents_to_bend(expression.detune_cents, bend_range), channel)
        elif reset_after:
            track.pitch_bend(tick, BEND_CENTER, channel)
    else:
        _write_expression_curve(track, tick, duration, channel, expression,
                                bend_range, ticks_per_beat, bpm)

    track.note(tick, duration, note, velocity, channel, release_velocity)

    if reset_after:
        reset_channel(track, end, channel,
                      reset_timbre=expression.timbre_from is not None
                      or expression.timbre_to is not None)


def _write_expression_curve(track: Track, tick: int, duration: int, channel: int,
                            expression: Expression, bend_range: float,
                            ticks_per_beat: int, bpm: float) -> None:
    # Cap the number of writes per note: a two-bar pad at a 30-tick grid would
    # otherwise cost 128 events per stream for a curve nobody can hear that
    # finely.
    step = max(1, expression.resolution_ticks, duration // MAX_EXPRESSION_STEPS)
    ticks_per_second = ticks_per_beat * bpm / 60.0
    last_bend: Optional[int] = None
    last_pressure: Optional[int] = None
    last_timbre: Optional[int] = None

    offset = 0
    while offset <= duration:
        position = offset / duration if duration else 0.0
        now = tick + offset

        cents = expression.detune_cents
        if expression.glide_ticks > 0 and offset < expression.glide_ticks:
            progress = offset / expression.glide_ticks
            eased = 1 - (1 - progress) ** expression.glide_curve
            cents += expression.glide_from * 100.0 * (1 - eased)
        if expression.vibrato_cents:
            ramp = min(1.0, position / expression.vibrato_delay) if expression.vibrato_delay else 1.0
            seconds = offset / ticks_per_second if ticks_per_second else 0.0
            cents += (expression.vibrato_cents * ramp
                      * math.sin(2 * math.pi * expression.vibrato_hz * seconds))

        bend = cents_to_bend(cents, bend_range)
        if bend != last_bend:
            track.pitch_bend(now, bend, channel)
            last_bend = bend

        pressure = _pressure_value(expression.pressure, position, expression.pressure_peak)
        if pressure is not None and pressure != last_pressure:
            track.channel_pressure(now, pressure, channel)
            last_pressure = pressure

        if expression.timbre_from is not None or expression.timbre_to is not None:
            start_value = 64 if expression.timbre_from is None else expression.timbre_from
            end_value = start_value if expression.timbre_to is None else expression.timbre_to
            timbre = int(round(start_value + (end_value - start_value) * position))
            if timbre != last_timbre:
                track.cc(now, 74, timbre, channel)
                last_timbre = timbre

        if offset == duration:
            break
        offset = min(offset + step, duration)


#: Ready-made articulations.  These only do anything audible if the patch
#: routes the corresponding Surge modulation source somewhere -- Timbre and
#: Channel AT are inert until you assign them in the mod matrix.
EXPRESSION_PRESETS = {
    "none": Expression(),
    "swell": Expression(pressure="swell", pressure_peak=110),
    "vocal": Expression(vibrato_cents=32, vibrato_hz=5.4, vibrato_delay=0.45,
                        pressure="swell", pressure_peak=105),
    "lead": Expression(glide_from=-1.0, glide_ticks=60, vibrato_cents=22,
                       vibrato_hz=5.8, pressure="attack", pressure_peak=100,
                       timbre_from=34, timbre_to=104),
    "pluck": Expression(pressure="decay", pressure_peak=118,
                        timbre_from=110, timbre_to=38),
    "slide": Expression(glide_from=-2.0, glide_ticks=140, glide_curve=2.4,
                        pressure="flat", pressure_peak=90),
    "breath": Expression(pressure="swell", pressure_peak=96,
                         timbre_from=20, timbre_to=90, vibrato_cents=14,
                         vibrato_hz=4.6),
}


def get_expression(name: Optional[str]) -> Optional[Expression]:
    """Look up an articulation by name.  None and 'none' both mean 'plain'."""
    if name in (None, "", "none"):
        return None
    if name not in EXPRESSION_PRESETS:
        raise ValueError(f"unknown expression {name!r}. Available: "
                         f"{', '.join(sorted(EXPRESSION_PRESETS))}")
    # Copy, so callers can layer a per-note detune without mutating the table.
    return Expression(**EXPRESSION_PRESETS[name].__dict__)
