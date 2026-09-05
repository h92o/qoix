"""Continuous-controller lanes: the slow movement that makes a static patch
sound alive.

Aimed squarely at Surge XT's macros (CC 41-48 out of the box), but any CC
works.  Lanes are written at a fixed grid and consecutive duplicate values are
dropped, so a four-bar sine sweep costs a few dozen bytes rather than a few
thousand.
"""

from __future__ import annotations

import math
import random
import re
from dataclasses import dataclass
from typing import Callable, Dict, Optional

from .rhythm import parse_division
from .smf import Track
from .surge import MACRO_CC, CC, describe_cc, validate_cc

__all__ = ["SHAPES", "Lane", "render_lane", "parse_lane_spec", "resolve_controller"]


def _sine(phase: float) -> float:
    return math.sin(2 * math.pi * phase)


def _triangle(phase: float) -> float:
    return 4 * abs(phase - math.floor(phase + 0.5)) - 1


def _saw_up(phase: float) -> float:
    return 2 * (phase % 1.0) - 1


def _saw_down(phase: float) -> float:
    return 1 - 2 * (phase % 1.0)


def _square(phase: float) -> float:
    return 1.0 if (phase % 1.0) < 0.5 else -1.0


def _pulse(width: float) -> Callable[[float], float]:
    def shape(phase: float) -> float:
        return 1.0 if (phase % 1.0) < width else -1.0
    return shape


def _arch(phase: float) -> float:
    """One hump per cycle -- a swell rather than an oscillation."""
    return 2 * math.sin(math.pi * (phase % 1.0)) - 1


def _exp_down(phase: float) -> float:
    return 2 * math.exp(-5.0 * (phase % 1.0)) - 1


def _exp_up(phase: float) -> float:
    return 2 * (1 - math.exp(-5.0 * (phase % 1.0))) - 1


#: Deterministic shapes, phase 0..1 in, -1..+1 out.
SHAPES: Dict[str, Callable[[float], float]] = {
    "sine": _sine,
    "cosine": lambda p: math.cos(2 * math.pi * p),
    "triangle": _triangle,
    "saw": _saw_up,
    "ramp": _saw_up,
    "ramp-down": _saw_down,
    "square": _square,
    "pulse": _pulse(0.25),
    "arch": _arch,
    "swell": _arch,
    "decay": _exp_down,
    "rise": _exp_up,
    "hold": lambda p: 1.0,
}

#: Shapes that need the RNG, handled separately in `render_lane`.
RANDOM_SHAPES = ("sh", "random", "drift")

_CC_ALIASES = {
    "mod": CC.MODWHEEL, "modwheel": CC.MODWHEEL, "wheel": CC.MODWHEEL,
    "breath": CC.BREATH,
    "expr": CC.EXPRESSION, "expression": CC.EXPRESSION,
    "pan": CC.PAN,
    "sustain": CC.SUSTAIN, "pedal": CC.SUSTAIN,
    "timbre": CC.TIMBRE, "slide": CC.TIMBRE,
}


def resolve_controller(value) -> int:
    """`'macro3' -> 43`, `'timbre' -> 74`, `'41' -> 41`."""
    if isinstance(value, int):
        return value
    text = str(value).strip().lower()
    if re.fullmatch(r"\d+", text):
        return int(text)
    match = re.fullmatch(r"macro\s*([1-8])", text)
    if match:
        return MACRO_CC[int(match.group(1))]
    if text in _CC_ALIASES:
        return _CC_ALIASES[text]
    raise ValueError(
        f"cannot resolve controller {value!r}. Use a CC number, 'macro1'-'macro8', "
        f"or one of: {', '.join(sorted(_CC_ALIASES))}")


@dataclass
class Lane:
    """One CC automation lane."""

    controller: int
    shape: str = "sine"
    period_bars: float = 4.0
    depth: float = 1.0
    center: float = 0.5
    phase: float = 0.0
    resolution: str = "1/16"
    channel: int = 1
    steps: int = 8          # quantisation for 'sh' / 'random'

    def __post_init__(self) -> None:
        self.controller = resolve_controller(self.controller)
        if self.shape not in SHAPES and self.shape not in RANDOM_SHAPES:
            known = ", ".join(sorted(list(SHAPES) + list(RANDOM_SHAPES)))
            raise ValueError(f"unknown lane shape {self.shape!r}. Available: {known}")
        if self.period_bars <= 0:
            raise ValueError("lane period must be positive")
        self.depth = max(0.0, min(1.0, self.depth))
        self.center = max(0.0, min(1.0, self.center))

    def describe(self) -> str:
        return (f"CC {self.controller} ({describe_cc(self.controller)}) "
                f"{self.shape} over {self.period_bars:g} bar(s), "
                f"depth {self.depth:g}, centre {self.center:g}")


def render_lane(track: Track, lane: Lane, start_tick: int, length_ticks: int,
                ticks_per_beat: int, beats_per_bar: int = 4,
                rng: Optional[random.Random] = None,
                strict: bool = True) -> int:
    """Write `lane` into `track`.  Returns the number of CC events written."""
    validate_cc(lane.controller, strict=strict)
    rng = rng or random.Random(0)
    step_ticks = parse_division(lane.resolution, ticks_per_beat)
    cycle_ticks = max(1.0, lane.period_bars * beats_per_bar * ticks_per_beat)

    # Random shapes hold a value for a fraction of the cycle rather than
    # jittering at every grid point.
    hold_ticks = max(1.0, cycle_ticks / max(1, lane.steps))
    random_points: Dict[int, float] = {}

    def random_value(index: int) -> float:
        if index not in random_points:
            random_points[index] = rng.uniform(-1.0, 1.0)
        return random_points[index]

    written = 0
    last_value: Optional[int] = None
    tick = start_tick
    end = start_tick + length_ticks

    while tick <= end:
        elapsed = tick - start_tick
        phase = (elapsed / cycle_ticks + lane.phase) % 1.0
        if lane.shape in RANDOM_SHAPES:
            index = int(elapsed // hold_ticks)
            if lane.shape == "sh":
                raw = random_value(index)
            else:  # 'random' / 'drift' interpolate between hold points
                position = (elapsed % hold_ticks) / hold_ticks
                start_value, end_value = random_value(index), random_value(index + 1)
                if lane.shape == "drift":
                    position = position * position * (3 - 2 * position)  # smoothstep
                raw = start_value + (end_value - start_value) * position
        else:
            raw = SHAPES[lane.shape](phase)

        value = int(round(127 * max(0.0, min(1.0, lane.center + lane.depth * 0.5 * raw))))
        if value != last_value:
            track.cc(tick, lane.controller, value, lane.channel)
            last_value = value
            written += 1
        tick += step_ticks

    return written


def parse_lane_spec(spec: str, default_channel: int = 1) -> Lane:
    """Parse the CLI form `cc:shape[:period[:depth[:center[:phase]]]]`.

    Examples::

        macro1:sine:8:0.9          slow filter sweep on macro 1
        mod:drift:2:0.5:0.4        wandering mod wheel
        74:ramp:1:1:0.5            per-bar timbre ramp (MPE only)
    """
    parts = [p.strip() for p in str(spec).split(":")]
    if not parts or not parts[0]:
        raise ValueError(f"empty automation spec: {spec!r}")

    controller = resolve_controller(parts[0])
    shape = parts[1] if len(parts) > 1 and parts[1] else "sine"

    def number(index: int, default: float) -> float:
        if len(parts) <= index or not parts[index]:
            return default
        text = parts[index]
        if "/" in text:
            numerator, denominator = text.split("/", 1)
            return float(numerator) / float(denominator)
        return float(text)

    return Lane(
        controller=controller,
        shape=shape,
        period_bars=number(2, 4.0),
        depth=number(3, 1.0),
        center=number(4, 0.5),
        phase=number(5, 0.0),
        channel=default_channel,
    )
