# surge-midigen

A Python MIDI generator aimed at [Surge XT](https://surge-synthesizer.github.io/).

It writes Standard MIDI Files that know what Surge XT is: macros on the CCs
Surge already listens to, MPE with per-note bend, pressure and timbre, Scala
microtuning in either direction, and Channel Split scene routing. No
third-party packages — the SMF writer and reader are in the box.

```
python3 -m surge_midigen song --preset berlin-school -o seq.mid
```

## Why "for Surge XT"

Any generator can emit notes. These are the bits that make a file land
correctly on Surge specifically, each checked against Surge's source rather
than recalled:

| Behaviour | Detail | Where it comes from |
|---|---|---|
| Macros 1–8 respond to **CC 41–48** with no MIDI learn | `controllers[i] = 41 + i` | `SurgeStorage.cpp` |
| **CC 74 only works in MPE mode** — outside it, Surge's CC 74 case falls through | `case 74: if (mpeEnabled) …` | `SurgeSynthesizer.cpp` |
| CC 1, 2, 11, 64, 66 are always live as Modwheel, Breath, Expression, Sustain, Sostenuto — and apply to **both scenes** | per-scene `set_target` loops | `SurgeSynthesizer.cpp` |
| MPE is switched on by the MPE Configuration Message: RPN (LSB 6, MSB 0) on channel 1 | `lsbRPN == 6 && msbRPN == 0` | `SurgeSynthesizer.cpp` |
| Per-note bend range is read from RPN 0 on the **first member channel**, and defaults to **48 semitones** | `MPEPitchBendRange, 48` | `SurgeSynthesizer.cpp` |
| Channel Split sends channels at and below the split to scene A | `splitChan = splitpoint / 8 + 1` | `SurgeSynthesizer.cpp` |

CCs that carry protocol rather than performance data (bank select, RPN/NRPN
data entry, channel mode) are refused for automation unless you pass
`--allow-reserved-cc`, because a ramp on CC 6 would reprogram the pitch bend
range mid-song.

## Requirements

Python 3.8 or newer. Nothing else.

```
python3 -m surge_midigen --version
```

Optionally install it so `surge-midigen` is on your PATH:

```
pip install -e tools/surge-midigen
```

## Quick start

```bash
# A preset, straight out of the box
python3 -m surge_midigen song --preset berlin-school -o seq.mid

# Build your own from parts
python3 -m surge_midigen song -o mine.mid \
    --bpm 124 --bars 16 --key F --scale Dorian --progression "im7 IV7 im7 bVImaj7" \
    --part "bass:style=octave:rate=1/8" \
    --part "arp:mode=updown:rate=1/16:octaves=2" \
    --part "pad:octave_shift=-1" \
    --cc "macro1:ramp:8:0.9" --cc "macro2:drift:3:0.4"

# Expressive MPE lead with per-note glide, vibrato, pressure and CC 74
python3 -m surge_midigen song -o lead.mid --mpe --expression lead \
    --part "melody:rate=1/8:density=0.7" --bars 8

# 19-EDO, written as pitch bend so Surge stays in 12-TET
python3 -m surge_midigen song -o micro.mid --mpe --tuning 19-edo --tuning-mode bend \
    --part "melody:low=C4:high=C5" --bars 8

# What did I just make?
python3 -m surge_midigen inspect seq.mid
```

Every run prints what it wrote and what Surge needs set up for it to play
correctly.

## Commands

| Command | What it does |
|---|---|
| `song` | generate a `.mid` file |
| `list [topic]` | presets, scales, progressions, generators, shapes, grooves, tunings, cc, expressions |
| `inspect PATH` | summarise an existing MIDI file — tracks, channels, CCs, bend range |
| `tuning NAME` | print a tuning's degrees, frequencies and 12-TET deviations |

## Presets

`--preset NAME`, then override anything with the usual flags.

| Preset | Sound |
|---|---|
| `ambient-drift` | slow pad and drone, wandering macros, MPE |
| `arp-hypnotic` | up-down arp over a pad and drone |
| `berlin-school` | 16th sequence, root bass, filter opening over 8 bars |
| `cinematic-swell` | wide pads, slow melody, per-bar swells, MPE |
| `dual-scene` | bass on channel 1, lead on channel 2, for Channel Split |
| `euclid-pulse` | interlocking euclidean rhythms |
| `lofi-keys` | swung seventh chords with a sparse right hand |
| `microtonal-19` | 19-EDO sequence, MPE |
| `mpe-expressive` | solo line using glide, vibrato, pressure and CC 74 |
| `techno-stab` | euclidean stabs over a driving bass |

Each preset also prints a `surge_hint` saying what its macro lanes assume —
macro 1 moving a filter only sweeps if macro 1 is routed to a filter.

## Parts

`--part generator[:key=value ...]`, repeatable. Any keyword the generator
accepts works, so there is no flag to learn per option.

| Generator | Options |
|---|---|
| `chords` | `gate`, `velocity`, `spread`, `rate`, `octave_shift` |
| `arp` | `mode` (up, down, updown, downup, converge, diverge, random, order, thumb), `rate`, `octaves`, `gate`, `octave_shift` |
| `bass` | `style` (root, octave, fifth, walk, offbeat, driving, pedal, arp), `rate`, `octave_shift`, `gate` |
| `melody` | `rate`, `density`, `low`, `high`, `leap`, `gate` |
| `pad` | `velocity`, `spread`, `overlap`, `octave_shift` |
| `euclid` | `pulses`, `steps`, `rotation`, `rate`, `gate`, `pitch_mode` (root, chord, random) |
| `drone` | `intervals`, `octave_shift`, `velocity` |

Plus `channel=N`, `name=Text` and `expression=NAME` on any part.

Note lengths accept `1/4`, `1/8`, `1/16`, `1/8T` (triplet) and `1/4.` (dotted).

Parts share one chord plan, so the bass, the arp and the melody always agree
about what bar 9 is doing. Roman numerals set the harmony — case carries the
quality (`IV` major, `iv` minor) and a suffix overrides it (`iim7b5`, `bVImaj9`).

### Notes that would collide

Two note-ons for the same pitch on the same channel, with no note-off between,
retrigger the voice — and then the first note-off silences it. Generators
produce that honestly (a melody note held across its own repeat, a pad tail
reaching a chord that shares the pitch), so it is cleaned up after generation:
a note entirely covered by one already sounding is dropped, otherwise the
sounding note is shortened to release just before the new one. If parts are
fighting over a register badly enough to lose notes, the run says so and
suggests `channel=`, `octave_shift=` or `--mpe`.

## Automation lanes

`--cc SPEC` (or `--macro`), repeatable:

```
cc:shape[:period_bars[:depth[:center[:phase]]]]
```

`cc` is a number, `macro1`–`macro8`, or a name (`mod`, `breath`, `expr`,
`sustain`, `timbre`, `pan`). Shapes: `sine`, `cosine`, `triangle`, `saw`,
`ramp`, `ramp-down`, `square`, `pulse`, `arch`/`swell`, `decay`, `rise`,
`hold`, plus `sh` (sample and hold), `random` and `drift` (smoothed random).

```bash
--cc "macro1:sine:8:0.9"      # slow filter sweep, 8 bars per cycle
--cc "macro5:sh:1:0.7:0.5"    # stepped random, new value 8 times a bar
--cc "mod:arch:16:0.8:0.3"    # one swell across 16 bars
```

Consecutive identical values are dropped, so a long sweep stays small.

## MPE

`--mpe` puts every note on its own member channel (2–16), which turns pitch
bend, channel pressure and CC 74 into per-note articulation. The file emits the
MPE Configuration Message and the per-note bend range itself, so it plays
correctly on a Surge instance that has never seen MPE — you still need to turn
MPE on in Surge, and to set your DAW track to MPE or all-channels rather than
channel 1.

Channels are allocated across every part in one time-ordered pass. Allocating
part by part looks fine and is wrong: each part restarts at tick 0, so by the
second part the allocator thinks every channel is busy and starts stealing them
from sounding notes.

`--expression NAME` applies an articulation to parts that do not set their own:

| Expression | Gesture |
|---|---|
| `swell` | pressure swell across the note |
| `vocal` | delayed vibrato plus a pressure swell |
| `lead` | slide in, vibrato, pressure attack, CC 74 opening |
| `pluck` | pressure decay, CC 74 closing |
| `slide` | a long portamento into the note |
| `breath` | soft swell with a CC 74 rise and light vibrato |

Timbre and pressure are inert until the patch routes Surge's Timbre and
Channel AT modulation sources somewhere. That is a patch decision, not a MIDI
one.

## Microtuning

`--tuning` takes a built-in name (`12-edo`, `19-edo`, `24-edo`, `31-edo`,
`53-edo`, `just`, `pythagorean`, `meantone`, `werckmeister3`, `harmonics`,
`bohlen-pierce`), `edo:N` for any equal division, or a path to a `.scl` file.

There are two ways to play microtonal material, and picking the wrong one
applies the tuning twice:

**`--tuning-mode scala`** (default) writes plain MIDI notes and lets Surge do
the retuning — load the same `.scl` from Surge's Tuning menu. Scale degrees
land on consecutive MIDI keys, so key 61 is the first degree above the root
whatever the scale.

**`--tuning-mode bend`** leaves Surge in 12-TET and carries the tuning as
per-note pitch bend. Polyphony needs `--mpe`, since pitch bend is per channel;
a monophonic line is fine on one channel. Useful when the file has to play on
an instance you do not control, or alongside 12-TET parts.

```bash
python3 -m surge_midigen tuning just --keys 13     # see what a tuning does
```

The `.scl` parser matches the QOIX synth's `js/microtonal.js` token for token:
a token containing `.` is cents, `n/d` is a ratio, a bare integer is `n/1`.

## Scene split

`--scene-split N` records that the file targets Surge's Channel Split scene
mode. Scene A takes channels 1..N and scene B everything above, so
`--part "bass:channel=1" --part "arp:channel=2"` gives each scene its own
patch. The `dual-scene` preset is this arrangement ready-made. Macros stay
global across both scenes.

## Python API

```python
from surge_midigen import build_song

result = build_song(
    bpm=96, bars=16, key="F#", scale="Phrygian",
    progression="i bII bVII i",
    parts=["pad:octave_shift=-1", "arp:mode=thumb:rate=1/16", "bass:style=walk"],
    lanes=["macro1:drift:6:0.6"],
    mpe=True, expression="pluck", seed=42,
)
result.save("out.mid")
print(result.summary("out.mid"))
```

Lower-level pieces are importable too — `MidiFile`/`Track` for raw SMF writing,
`Scale`/`parse_progression` for theory, `Tuning` for Scala files, `MPEAllocator`
and `Expression` for per-note articulation, and `parse_midi_file` for reading a
file back.

Every run is deterministic: the same flags and `--seed` produce byte-identical
output. `--random-seed` picks one and prints it so you can pin it afterwards.

## Tests

```
python3 -m unittest discover -s tools/surge-midigen -v
```

The suite covers the SMF bytes (variable-length quantities, event ordering,
1-indexed channels), the Surge facts above as executable assertions, tuning
maths against known just-intonation deviations, MPE channel allocation, and a
sweep over every preset checking that no note is left hanging and no channel
ever has two notes at once.

## Relationship to QOIX

The scale table matches `js/randomgen.js` and the `.scl` parser matches
`js/microtonal.js`, so a pattern means the same thing whether it is generated
here or played live in the QOIX synth. The generated files are ordinary MIDI —
QOIX's own renderer will read them as happily as Surge XT will.
