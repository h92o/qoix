#!/usr/bin/env python3
"""Render one MIDI file per preset into examples/output/.

    python3 tools/surge-midigen/examples/generate_all.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from surge_midigen import PRESETS, build_song

OUTPUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "output")


def main() -> int:
    os.makedirs(OUTPUT, exist_ok=True)
    for name in sorted(PRESETS):
        result = build_song(name, seed=1)
        path = os.path.join(OUTPUT, f"{name}.mid")
        result.save(path)
        notes = sum(len(part.notes) for part in result.parts)
        print(f"{name:<16} {notes:5d} notes -> {os.path.relpath(path)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
