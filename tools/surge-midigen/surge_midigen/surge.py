"""What Surge XT actually does with incoming MIDI.

Every constant and behaviour note below was checked against the Surge source
(`src/common/SurgeSynthesizer.cpp`, `src/common/SurgeStorage.cpp`) rather than
recalled, because "the synth ignores that CC" is an expensive thing to find out
after rendering a track.

The short version:

* **Macros 1-8 default to CC 41-48.**  `SurgeStorage` initialises its custom
  controllers with `controllers[i] = 41 + i`, so a freshly installed Surge XT
  responds to those eight CCs with no MIDI learn at all.  Anything else has to
  be learned by right-clicking the parameter.
* **CC 74 only does something in MPE mode.**  Outside MPE, Surge's CC 74 case
  falls through to the generic controller path, so a timbre lane on a non-MPE
  file is inert unless you have learned it somewhere.
* **CC 1 / 2 / 11 / 64 / 66 are always live** as the Modwheel, Breath,
  Expression, Sustain and Sostenuto modulation sources, applied to *both*
  scenes.
* **Some CCs are structural** (RPN/NRPN data entry and bank select) and must
  never be borrowed for automation.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Optional

from .smf import Track

__all__ = [
    "CC", "MACRO_CC", "RESERVED_CC", "SURGE_NATIVE_CC",
    "MPE_MASTER_CHANNEL", "MPE_DEFAULT_BEND_RANGE", "MPE_DEFAULT_MEMBER_CHANNELS",
    "SurgeConfig", "macro_cc", "validate_cc", "describe_cc",
    "write_mpe_setup", "write_mpe_disable", "write_bend_range",
    "scene_split_channels", "splitpoint_for_channel",
]


class CC:
    """MIDI controller numbers Surge XT treats specially."""

    BANK_SELECT_MSB = 0     # stored as CC0, used with program change
    MODWHEEL = 1            # modulation source, both scenes
    BREATH = 2              # modulation source, both scenes
    DATA_ENTRY_MSB = 6      # RPN/NRPN value -- structural, never automate
    VOLUME = 7              # not consumed by Surge itself; host/DAW level
    PAN = 10                # per-note pan, MPE mode only
    EXPRESSION = 11         # modulation source, both scenes
    BANK_SELECT_LSB = 32    # stored as CC32
    DATA_ENTRY_LSB = 38     # RPN/NRPN value -- structural, never automate
    SUSTAIN = 64            # sustain pedal + modulation source
    SOSTENUTO = 66          # sostenuto pedal
    TIMBRE = 74             # MPE "slide" / Y axis -- MPE mode only
    NRPN_LSB = 98
    NRPN_MSB = 99
    RPN_LSB = 100
    RPN_MSB = 101
    ALL_SOUND_OFF = 120
    ALL_NOTES_OFF = 123


#: Surge XT's factory macro assignments: macro 1..8 -> CC 41..48.
MACRO_CC: Dict[int, int] = {n: 40 + n for n in range(1, 9)}

#: CCs that carry protocol rather than performance data.
RESERVED_CC = frozenset({
    CC.BANK_SELECT_MSB, CC.DATA_ENTRY_MSB, CC.BANK_SELECT_LSB, CC.DATA_ENTRY_LSB,
    CC.NRPN_LSB, CC.NRPN_MSB, CC.RPN_LSB, CC.RPN_MSB,
    *range(120, 128),
})

#: CCs Surge already routes to a built-in modulation source or pedal.
SURGE_NATIVE_CC = {
    CC.MODWHEEL: "Modwheel modulation source (both scenes)",
    CC.BREATH: "Breath modulation source (both scenes)",
    CC.EXPRESSION: "Expression modulation source (both scenes)",
    CC.PAN: "Per-note pan (MPE mode only)",
    CC.SUSTAIN: "Sustain pedal and Sustain modulation source",
    CC.SOSTENUTO: "Sostenuto pedal",
    CC.TIMBRE: "MPE timbre / slide axis (MPE mode only)",
}

MPE_MASTER_CHANNEL = 1
MPE_DEFAULT_MEMBER_CHANNELS = 15
MPE_DEFAULT_BEND_RANGE = 48      # Surge's MPEPitchBendRange user default
MPE_DEFAULT_MASTER_BEND_RANGE = 2


def macro_cc(macro: int) -> int:
    """CC number for Surge macro 1-8."""
    if macro not in MACRO_CC:
        raise ValueError(f"Surge XT has macros 1-8, got {macro}")
    return MACRO_CC[macro]


def validate_cc(controller: int, *, strict: bool = True) -> List[str]:
    """Return human-readable warnings about automating `controller`.

    With `strict` the structural CCs raise instead of warning -- writing an
    automation ramp onto CC 6 would reprogram the pitch bend range mid-song.
    """
    if not 0 <= controller <= 127:
        raise ValueError(f"CC number must be 0..127, got {controller}")
    notes: List[str] = []
    if controller in RESERVED_CC:
        message = (f"CC {controller} carries MIDI protocol data (bank select, RPN/NRPN "
                   f"or channel mode) and must not be used for automation")
        if strict:
            raise ValueError(message)
        notes.append(message)
    if controller in SURGE_NATIVE_CC:
        notes.append(f"CC {controller} is already {SURGE_NATIVE_CC[controller]}")
    if controller in MACRO_CC.values():
        macro = next(m for m, c in MACRO_CC.items() if c == controller)
        notes.append(f"CC {controller} is Surge macro {macro} by default")
    return notes


#: Protocol CCs, named so `inspect` can say what a file's setup bytes are.
_PROTOCOL_CC = {
    CC.BANK_SELECT_MSB: "bank select MSB",
    CC.DATA_ENTRY_MSB: "RPN/NRPN data entry MSB",
    CC.BANK_SELECT_LSB: "bank select LSB",
    CC.DATA_ENTRY_LSB: "RPN/NRPN data entry LSB",
    CC.NRPN_LSB: "NRPN select LSB",
    CC.NRPN_MSB: "NRPN select MSB",
    CC.RPN_LSB: "RPN select LSB",
    CC.RPN_MSB: "RPN select MSB",
    CC.ALL_SOUND_OFF: "all sound off",
    CC.ALL_NOTES_OFF: "all notes off",
}


def describe_cc(controller: int) -> str:
    if controller in MACRO_CC.values():
        macro = next(m for m, c in MACRO_CC.items() if c == controller)
        return f"Macro {macro}"
    if controller in SURGE_NATIVE_CC:
        return SURGE_NATIVE_CC[controller]
    if controller in _PROTOCOL_CC:
        return _PROTOCOL_CC[controller]
    if controller in RESERVED_CC:
        return "reserved / channel mode"
    return "unassigned (MIDI learn required)"


# ---------------------------------------------------------------------------
# MPE
# ---------------------------------------------------------------------------

def write_mpe_setup(track: Track, tick: int = 0,
                    member_channels: int = MPE_DEFAULT_MEMBER_CHANNELS,
                    bend_range: int = MPE_DEFAULT_BEND_RANGE,
                    master_bend_range: Optional[int] = MPE_DEFAULT_MASTER_BEND_RANGE) -> None:
    """Emit the MPE Configuration Message and the zone's bend ranges.

    Surge reads the MCM as RPN (LSB 6, MSB 0) on the master channel, and takes
    the member-channel bend range from RPN 0 sent on the *first member channel*
    -- channel 2 for the lower zone.  Both are written here so the file plays
    correctly on a Surge instance that has never seen MPE before.
    """
    if not 1 <= member_channels <= 15:
        raise ValueError(f"MPE lower zone supports 1..15 member channels, got {member_channels}")
    if not 0 <= bend_range <= 96:
        raise ValueError(f"implausible MPE bend range: {bend_range}")

    track.text(tick, f"MPE lower zone: {member_channels} member channels, "
                     f"+/-{bend_range} semitone per-note bend")
    # MPE Configuration Message -- Bn 65 00 / Bn 64 06 / Bn 06 mm on channel 1.
    track.rpn(tick, msb=0, lsb=6, value_msb=member_channels, channel=MPE_MASTER_CHANNEL)
    # Per-note bend range lives on the first member channel.
    track.rpn(tick, msb=0, lsb=0, value_msb=bend_range, channel=MPE_MASTER_CHANNEL + 1)
    if master_bend_range is not None:
        track.rpn(tick, msb=0, lsb=0, value_msb=master_bend_range, channel=MPE_MASTER_CHANNEL)
    track.rpn_null(tick, channel=MPE_MASTER_CHANNEL)


def write_mpe_disable(track: Track, tick: int = 0) -> None:
    """Turn MPE back off (MCM with zero member channels)."""
    track.rpn(tick, msb=0, lsb=6, value_msb=0, channel=MPE_MASTER_CHANNEL)


def write_bend_range(track: Track, tick: int, semitones: int, channel: int = 1) -> None:
    """Plain (non-MPE) pitch bend sensitivity for one channel."""
    track.rpn(tick, msb=0, lsb=0, value_msb=semitones, channel=channel)
    track.rpn_null(tick, channel=channel)


# ---------------------------------------------------------------------------
# Scene split
# ---------------------------------------------------------------------------

def scene_split_channels(split_channel: int) -> Dict[str, List[int]]:
    """Which MIDI channels reach which scene in Channel Split mode.

    Surge computes `splitChan = splitpoint / 8 + 1` on 0-indexed channels and
    sends everything below it to scene A.  Expressed in the 1-indexed channels
    people actually use: scene A gets channels 1..`split_channel`, scene B gets
    everything above.
    """
    if not 1 <= split_channel <= 15:
        raise ValueError(f"split channel must be 1..15, got {split_channel}")
    return {
        "A": list(range(1, split_channel + 1)),
        "B": list(range(split_channel + 1, 17)),
    }


def splitpoint_for_channel(split_channel: int) -> int:
    """The raw `splitpoint` parameter value matching a 1-indexed split channel."""
    if not 1 <= split_channel <= 15:
        raise ValueError(f"split channel must be 1..15, got {split_channel}")
    return (split_channel - 1) * 8


@dataclass
class SurgeConfig:
    """How the generated file expects Surge XT to be set up."""

    mpe: bool = False
    member_channels: int = MPE_DEFAULT_MEMBER_CHANNELS
    bend_range: int = MPE_DEFAULT_BEND_RANGE
    master_bend_range: int = MPE_DEFAULT_MASTER_BEND_RANGE
    scene_split_channel: Optional[int] = None
    macro_ccs: Dict[int, int] = field(default_factory=lambda: dict(MACRO_CC))

    def channels(self) -> List[int]:
        """Channels notes may be placed on."""
        if self.mpe:
            return list(range(MPE_MASTER_CHANNEL + 1,
                              MPE_MASTER_CHANNEL + 1 + self.member_channels))
        return [1]

    def apply(self, track: Track, tick: int = 0) -> None:
        if self.mpe:
            write_mpe_setup(track, tick, self.member_channels,
                            self.bend_range, self.master_bend_range)

    def setup_notes(self) -> List[str]:
        """Setup steps to print after generating, so the file actually plays."""
        notes: List[str] = []
        if self.mpe:
            notes.append("Enable MPE in Surge XT (the MPE button in the top bar). "
                         f"The file also sends the MPE Configuration Message and a "
                         f"+/-{self.bend_range} semitone per-note bend range.")
            notes.append(f"Notes are spread over channels 2-{1 + self.member_channels}; "
                         "keep your DAW track set to 'MPE' or 'all channels', not channel 1.")
        elif not self.scene_split_channel:
            notes.append("Standard single-channel MIDI - no Surge setup required.")
        if self.scene_split_channel:
            split = scene_split_channels(self.scene_split_channel)
            notes.append(
                f"Set Scene mode to 'Channel Split' with the split at channel "
                f"{self.scene_split_channel}: scene A plays channels "
                f"{split['A'][0]}-{split['A'][-1]}, scene B plays "
                f"{split['B'][0]}-{split['B'][-1]}.")
        return notes
