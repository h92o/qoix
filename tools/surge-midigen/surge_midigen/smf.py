"""Standard MIDI File reading and writing, with no third-party dependencies.

Everything in this module speaks **1-indexed MIDI channels** (1..16), the way
Surge XT's UI and every MIDI cable in the world label them.  The 0-indexed
nibble that actually goes on the wire is an implementation detail handled here
and nowhere else.

Events are collected with absolute ticks and sorted on the way out, so callers
can emit notes, controllers and automation in whatever order is convenient.
Ordering *within* a tick matters for MPE, so each event carries a priority:

    meta/setup  ->  note off  ->  controller  ->  note on

That ordering means a per-note pitch bend, CC 74 or channel pressure written at
the same tick as its note-on always reaches Surge *before* the note starts (as
the MPE spec requires), and a note-off at the boundary between two notes frees
the channel before the next note claims it.
"""

from __future__ import annotations

import struct
from typing import List, Optional, Tuple

__all__ = [
    "TICKS_PER_BEAT",
    "Track",
    "MidiFile",
    "parse_midi_file",
    "bend_to_14bit",
    "cents_to_bend",
]

TICKS_PER_BEAT = 480

# Event priorities within a single tick (lower value is emitted first).
_ORDER_META = 0
_ORDER_NOTE_OFF = 1
_ORDER_CTRL = 2
_ORDER_NOTE_ON = 3

BEND_CENTER = 8192
BEND_MAX = 16383


def _clamp(value: int, low: int, high: int) -> int:
    return low if value < low else (high if value > high else value)


def _clamp7(value: float) -> int:
    return _clamp(int(round(value)), 0, 127)


def _vlq(value: int) -> bytes:
    """Encode a MIDI variable-length quantity."""
    if value < 0:
        raise ValueError(f"variable-length quantity cannot be negative: {value}")
    if value > 0x0FFFFFFF:
        raise ValueError(f"variable-length quantity too large: {value}")
    out = bytearray([value & 0x7F])
    value >>= 7
    while value:
        out.append((value & 0x7F) | 0x80)
        value >>= 7
    out.reverse()
    return bytes(out)


def _status(kind: int, channel: int) -> int:
    if not 1 <= channel <= 16:
        raise ValueError(f"MIDI channel must be 1..16, got {channel}")
    return kind | (channel - 1)


def bend_to_14bit(normalized: float) -> int:
    """Map -1.0 .. +1.0 onto the 14-bit pitch bend range, 0 sitting dead centre."""
    normalized = max(-1.0, min(1.0, normalized))
    if normalized >= 0:
        return _clamp(BEND_CENTER + int(round(normalized * (BEND_MAX - BEND_CENTER))), 0, BEND_MAX)
    return _clamp(BEND_CENTER + int(round(normalized * BEND_CENTER)), 0, BEND_MAX)


def cents_to_bend(cents: float, bend_range_semitones: float) -> int:
    """14-bit bend value that detunes a note by `cents`, given the bend range.

    Surge XT's MPE per-note bend range defaults to 48 semitones, so a cent of
    detune is a very small bend step -- roughly 1.7 bend units.  Anything
    outside the range is clamped rather than silently wrapping.
    """
    if bend_range_semitones <= 0:
        raise ValueError("bend range must be positive")
    return bend_to_14bit(cents / (bend_range_semitones * 100.0))


class Track:
    """One MTrk chunk: a bag of timestamped events that sorts itself."""

    def __init__(self, name: Optional[str] = None) -> None:
        self._events: List[Tuple[int, int, int, bytes]] = []
        self._seq = 0
        if name:
            self.track_name(name)

    # -- plumbing ---------------------------------------------------------
    def _add(self, tick: int, order: int, data: bytes) -> None:
        if tick < 0:
            raise ValueError(f"event tick cannot be negative: {tick}")
        self._events.append((int(tick), order, self._seq, data))
        self._seq += 1

    def __len__(self) -> int:
        return len(self._events)

    @property
    def end_tick(self) -> int:
        return max((e[0] for e in self._events), default=0)

    # -- meta events ------------------------------------------------------
    def meta(self, tick: int, meta_type: int, payload: bytes) -> None:
        self._add(tick, _ORDER_META, bytes([0xFF, meta_type]) + _vlq(len(payload)) + payload)

    def track_name(self, name: str, tick: int = 0) -> None:
        self.meta(tick, 0x03, name.encode("utf-8"))

    def instrument_name(self, name: str, tick: int = 0) -> None:
        self.meta(tick, 0x04, name.encode("utf-8"))

    def text(self, tick: int, value: str) -> None:
        self.meta(tick, 0x01, value.encode("utf-8"))

    def marker(self, tick: int, value: str) -> None:
        self.meta(tick, 0x06, value.encode("utf-8"))

    def tempo(self, tick: int, bpm: float) -> None:
        if bpm <= 0:
            raise ValueError("tempo must be positive")
        micros = int(round(60_000_000.0 / bpm))
        self.meta(tick, 0x51, struct.pack(">I", micros)[1:])

    def time_signature(self, tick: int, numerator: int, denominator: int,
                       clocks_per_click: int = 24, notated_32nds: int = 8) -> None:
        power = denominator.bit_length() - 1
        if 1 << power != denominator:
            raise ValueError(f"time signature denominator must be a power of two: {denominator}")
        self.meta(tick, 0x58, bytes([numerator, power, clocks_per_click, notated_32nds]))

    def key_signature(self, tick: int, sharps_flats: int, minor: bool = False) -> None:
        self.meta(tick, 0x59, bytes([sharps_flats & 0xFF, 1 if minor else 0]))

    # -- channel voice events --------------------------------------------
    def note_on(self, tick: int, note: int, velocity: int = 100, channel: int = 1) -> None:
        self._add(tick, _ORDER_NOTE_ON,
                  bytes([_status(0x90, channel), _clamp(note, 0, 127), _clamp7(velocity)]))

    def note_off(self, tick: int, note: int, velocity: int = 64, channel: int = 1) -> None:
        self._add(tick, _ORDER_NOTE_OFF,
                  bytes([_status(0x80, channel), _clamp(note, 0, 127), _clamp7(velocity)]))

    def note(self, tick: int, duration: int, note: int, velocity: int = 100,
             channel: int = 1, release_velocity: int = 64) -> None:
        """A note-on plus its matching note-off.

        Surge XT exposes release velocity as a modulation source, so the
        note-off velocity is a real musical parameter here, not filler.
        """
        if duration <= 0:
            raise ValueError("note duration must be positive")
        self.note_on(tick, note, velocity, channel)
        self.note_off(tick + duration, note, release_velocity, channel)

    def cc(self, tick: int, controller: int, value: int, channel: int = 1) -> None:
        self._add(tick, _ORDER_CTRL,
                  bytes([_status(0xB0, channel), _clamp(controller, 0, 127), _clamp7(value)]))

    def pitch_bend(self, tick: int, value: int, channel: int = 1) -> None:
        """Raw 14-bit bend, 8192 == no bend."""
        value = _clamp(int(value), 0, BEND_MAX)
        self._add(tick, _ORDER_CTRL,
                  bytes([_status(0xE0, channel), value & 0x7F, (value >> 7) & 0x7F]))

    def bend_semitones(self, tick: int, semitones: float, bend_range: float,
                       channel: int = 1) -> None:
        self.pitch_bend(tick, cents_to_bend(semitones * 100.0, bend_range), channel)

    def channel_pressure(self, tick: int, value: int, channel: int = 1) -> None:
        self._add(tick, _ORDER_CTRL, bytes([_status(0xD0, channel), _clamp7(value)]))

    def poly_pressure(self, tick: int, note: int, value: int, channel: int = 1) -> None:
        self._add(tick, _ORDER_CTRL,
                  bytes([_status(0xA0, channel), _clamp(note, 0, 127), _clamp7(value)]))

    def program_change(self, tick: int, program: int, channel: int = 1) -> None:
        self._add(tick, _ORDER_CTRL, bytes([_status(0xC0, channel), _clamp(program, 0, 127)]))

    def rpn(self, tick: int, msb: int, lsb: int, value_msb: int,
            value_lsb: Optional[int] = None, channel: int = 1) -> None:
        """Registered Parameter Number write (CC 101 / 100 / 6 / 38).

        Surge only reads the data MSB for the RPNs it understands, so
        `value_lsb` is optional and omitted by default.
        """
        self.cc(tick, 101, msb, channel)
        self.cc(tick, 100, lsb, channel)
        self.cc(tick, 6, value_msb, channel)
        if value_lsb is not None:
            self.cc(tick, 38, value_lsb, channel)

    def rpn_null(self, tick: int, channel: int = 1) -> None:
        """Park the RPN parameter so stray data-entry CCs cannot land on it."""
        self.cc(tick, 101, 127, channel)
        self.cc(tick, 100, 127, channel)

    def all_notes_off(self, tick: int, channel: int = 1) -> None:
        self.cc(tick, 123, 0, channel)

    def all_sound_off(self, tick: int, channel: int = 1) -> None:
        self.cc(tick, 120, 0, channel)

    # -- serialisation ----------------------------------------------------
    def to_bytes(self, end_tick: Optional[int] = None) -> bytes:
        events = sorted(self._events, key=lambda e: (e[0], e[1], e[2]))
        body = bytearray()
        previous = 0
        for tick, _order, _seq, data in events:
            body += _vlq(tick - previous)
            body += data
            previous = tick
        final = self.end_tick if end_tick is None else max(end_tick, self.end_tick)
        body += _vlq(max(0, final - previous)) + b"\xff\x2f\x00"
        return b"MTrk" + struct.pack(">I", len(body)) + bytes(body)


class MidiFile:
    """A type-1 Standard MIDI File (one tempo map plus parallel tracks)."""

    def __init__(self, ticks_per_beat: int = TICKS_PER_BEAT, fmt: int = 1) -> None:
        if fmt not in (0, 1):
            raise ValueError("only SMF format 0 and 1 are supported")
        if not 1 <= ticks_per_beat <= 0x7FFF:
            raise ValueError("ticks per beat out of range")
        self.ticks_per_beat = ticks_per_beat
        self.format = fmt
        self.tracks: List[Track] = []

    def add_track(self, name: Optional[str] = None) -> Track:
        track = Track(name)
        self.tracks.append(track)
        return track

    @property
    def end_tick(self) -> int:
        return max((t.end_tick for t in self.tracks), default=0)

    def to_bytes(self) -> bytes:
        if not self.tracks:
            raise ValueError("cannot write a MIDI file with no tracks")
        fmt = 0 if len(self.tracks) == 1 else self.format
        header = b"MThd" + struct.pack(">IHHH", 6, fmt, len(self.tracks), self.ticks_per_beat)
        end = self.end_tick
        return header + b"".join(t.to_bytes(end) for t in self.tracks)

    def save(self, path: str) -> str:
        with open(path, "wb") as handle:
            handle.write(self.to_bytes())
        return path

    def event_count(self) -> int:
        return sum(len(t) for t in self.tracks)


# ---------------------------------------------------------------------------
# Reading, for `surge-midigen inspect` and for the tests to verify round trips.
# ---------------------------------------------------------------------------

def _read_vlq(data: bytes, index: int) -> Tuple[int, int]:
    value = 0
    while True:
        byte = data[index]
        index += 1
        value = (value << 7) | (byte & 0x7F)
        if not byte & 0x80:
            return value, index


def parse_midi_file(path_or_bytes) -> dict:
    """Parse an SMF into plain dicts.  Deliberately small: enough to verify
    output and to power `inspect`, not a general-purpose MIDI library."""
    if isinstance(path_or_bytes, (bytes, bytearray)):
        data = bytes(path_or_bytes)
    else:
        with open(path_or_bytes, "rb") as handle:
            data = handle.read()

    if data[:4] != b"MThd":
        raise ValueError("not a Standard MIDI File (missing MThd)")
    header_len, fmt, ntracks, division = struct.unpack(">IHHH", data[4:14])
    index = 8 + header_len
    tracks = []

    for _ in range(ntracks):
        if data[index:index + 4] != b"MTrk":
            raise ValueError(f"expected MTrk chunk at byte {index}")
        length = struct.unpack(">I", data[index + 4:index + 8])[0]
        end = index + 8 + length
        cursor = index + 8
        tick = 0
        running_status = None
        events = []

        while cursor < end:
            delta, cursor = _read_vlq(data, cursor)
            tick += delta
            byte = data[cursor]
            if byte & 0x80:
                status = byte
                cursor += 1
                if status < 0xF0:
                    running_status = status
            elif running_status is not None:
                status = running_status
            else:
                raise ValueError(f"running status used before any status byte at {cursor}")

            if status == 0xFF:
                meta_type = data[cursor]
                cursor += 1
                size, cursor = _read_vlq(data, cursor)
                payload = data[cursor:cursor + size]
                cursor += size
                event = {"tick": tick, "type": "meta", "meta_type": meta_type, "data": payload}
                if meta_type == 0x51 and size == 3:
                    micros = (payload[0] << 16) | (payload[1] << 8) | payload[2]
                    event["bpm"] = round(60_000_000.0 / micros, 6)
                elif meta_type in (0x01, 0x03, 0x04, 0x06):
                    event["text"] = payload.decode("utf-8", "replace")
                elif meta_type == 0x58 and size == 4:
                    event["time_signature"] = (payload[0], 1 << payload[1])
                events.append(event)
            elif status in (0xF0, 0xF7):
                size, cursor = _read_vlq(data, cursor)
                events.append({"tick": tick, "type": "sysex", "data": data[cursor:cursor + size]})
                cursor += size
            else:
                kind = status & 0xF0
                channel = (status & 0x0F) + 1
                nbytes = 1 if kind in (0xC0, 0xD0) else 2
                params = data[cursor:cursor + nbytes]
                cursor += nbytes
                event = {"tick": tick, "channel": channel}
                if kind == 0x90 and params[1] > 0:
                    event.update(type="note_on", note=params[0], velocity=params[1])
                elif kind == 0x80 or kind == 0x90:
                    event.update(type="note_off", note=params[0], velocity=params[1])
                elif kind == 0xB0:
                    event.update(type="cc", controller=params[0], value=params[1])
                elif kind == 0xE0:
                    event.update(type="pitch_bend", value=(params[1] << 7) | params[0])
                elif kind == 0xD0:
                    event.update(type="channel_pressure", value=params[0])
                elif kind == 0xA0:
                    event.update(type="poly_pressure", note=params[0], value=params[1])
                elif kind == 0xC0:
                    event.update(type="program_change", program=params[0])
                else:
                    event.update(type="unknown", status=status)
                events.append(event)

        tracks.append(events)
        index = end

    return {"format": fmt, "ticks_per_beat": division, "tracks": tracks}
