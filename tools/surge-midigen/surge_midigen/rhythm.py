"""Grids, note lengths and the small timing deviations that stop a pattern
sounding like a spreadsheet."""

from __future__ import annotations

import random
import re
from typing import List, Optional, Sequence, Tuple

__all__ = [
    "parse_division", "euclidean", "rotate", "GROOVES", "groove_offsets",
    "swing_offset", "humanize_tick", "humanize_velocity", "accent",
]

_DIVISION_RE = re.compile(r"^(\d+)\s*/\s*(\d+)([td.]?)$", re.IGNORECASE)


def parse_division(value, ticks_per_beat: int) -> int:
    """`'1/16' -> ticks`.  Accepts `T` for triplets and `.` for dotted values.

    A bare integer is taken as a tick count so callers can pass either.
    """
    if isinstance(value, int):
        return value
    text = str(value).strip()
    if re.fullmatch(r"\d+", text):
        return int(text)
    match = _DIVISION_RE.match(text)
    if not match:
        raise ValueError(f"cannot parse note division {value!r} (try '1/16', '1/8T', '1/4.')")
    numerator, denominator, modifier = match.groups()
    ticks = ticks_per_beat * 4 * int(numerator) / int(denominator)
    modifier = modifier.lower()
    if modifier == "t":
        ticks = ticks * 2 / 3
    elif modifier == ".":
        ticks = ticks * 3 / 2
    result = int(round(ticks))
    if result <= 0:
        raise ValueError(f"note division {value!r} rounds to zero ticks")
    return result


def euclidean(pulses: int, steps: int, rotation: int = 0) -> List[bool]:
    """Bjorklund's algorithm: spread `pulses` as evenly as possible over `steps`.

    E(3,8) gives the tresillo, E(5,8) the cinquillo -- the rhythms that make a
    plucky Surge patch sound like a part rather than a metronome.
    """
    if steps <= 0:
        raise ValueError("euclidean rhythm needs at least one step")
    pulses = max(0, min(pulses, steps))
    if pulses == 0:
        return [False] * steps
    if pulses == steps:
        return [True] * steps

    groups: List[List[bool]] = [[True] for _ in range(pulses)]
    remainder: List[List[bool]] = [[False] for _ in range(steps - pulses)]
    while len(remainder) > 1:
        pairs = min(len(groups), len(remainder))
        merged = [groups[i] + remainder[i] for i in range(pairs)]
        if len(groups) > pairs:
            leftover = groups[pairs:]
        else:
            leftover = remainder[pairs:]
        groups, remainder = merged, leftover

    pattern = [step for group in groups + remainder for step in group]
    return rotate(pattern, rotation)


def rotate(pattern: Sequence[bool], amount: int) -> List[bool]:
    if not pattern:
        return []
    amount %= len(pattern)
    return list(pattern[amount:]) + list(pattern[:amount])


#: Per-16th timing pushes as a fraction of a 16th note, one cycle per beat.
GROOVES = {
    "straight":  (0.0, 0.0, 0.0, 0.0),
    "swing":     (0.0, 0.24, 0.0, 0.24),
    "hard-swing": (0.0, 0.36, 0.0, 0.36),
    "shuffle":   (0.0, 0.33, 0.0, 0.33),
    "laidback":  (0.0, 0.06, 0.03, 0.08),
    "pushed":    (0.0, -0.05, -0.02, -0.06),
    "dilla":     (0.0, 0.30, -0.04, 0.18),
}


def groove_offsets(name: str) -> Tuple[float, ...]:
    if name not in GROOVES:
        raise ValueError(f"unknown groove {name!r}. Available: {', '.join(sorted(GROOVES))}")
    return GROOVES[name]


def swing_offset(step_index: int, step_ticks: int, amount: float = 0.0,
                 groove: Optional[str] = None) -> int:
    """Tick offset for one step of a grid.

    `amount` is classic swing on odd steps; `groove` applies one of the named
    four-step feels on top.  Both are expressed as a fraction of a step.
    """
    offset = 0.0
    if amount:
        offset += amount * 0.5 * step_ticks if step_index % 2 else 0.0
    if groove:
        offsets = groove_offsets(groove)
        offset += offsets[step_index % len(offsets)] * step_ticks
    return int(round(offset))


def humanize_tick(rng: random.Random, tick: int, amount_ticks: int) -> int:
    """Nudge a note earlier or later.  Never returns a negative tick."""
    if amount_ticks <= 0:
        return tick
    return max(0, tick + int(round(rng.gauss(0, amount_ticks / 2.0))))


def humanize_velocity(rng: random.Random, velocity: int, amount: int) -> int:
    if amount <= 0:
        return velocity
    return max(1, min(127, velocity + int(round(rng.gauss(0, amount / 2.0)))))


def accent(step_index: int, steps_per_bar: int, velocity: int,
           downbeat: int = 14, backbeat: int = 6) -> int:
    """Lift downbeats and, more gently, the half-bar."""
    if steps_per_bar <= 0:
        return velocity
    position = step_index % steps_per_bar
    if position == 0:
        return min(127, velocity + downbeat)
    if position == steps_per_bar // 2:
        return min(127, velocity + backbeat)
    if position % (max(1, steps_per_bar // 4)) == 0:
        return min(127, velocity + backbeat // 2)
    return velocity
