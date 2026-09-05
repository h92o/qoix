"""Test suite -- stdlib unittest only, no third-party dependencies.

    python3 -m unittest discover -s tools/surge-midigen -v
"""

from __future__ import annotations

import contextlib
import io
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from surge_midigen import build_song, parse_midi_file          # noqa: E402
from surge_midigen.automation import Lane, parse_lane_spec, render_lane  # noqa: E402
from surge_midigen.generators import Context, build_chord_plan, GENERATORS  # noqa: E402
from surge_midigen.mpe import Expression, MPEAllocator, play_note  # noqa: E402
from surge_midigen.presets import PRESETS                       # noqa: E402
from surge_midigen.rhythm import euclidean, parse_division      # noqa: E402
from surge_midigen.smf import MidiFile, _vlq, cents_to_bend     # noqa: E402
from surge_midigen import surge                                 # noqa: E402
from surge_midigen.theory import (PROGRESSIONS, Scale, note_name, parse_note,
                                  parse_progression, voice_lead)  # noqa: E402
from surge_midigen.tuning import edo_scl, load_tuning, parse_scl  # noqa: E402


def note_pairs(events):
    """Match note-ons to note-offs, failing loudly on anything unbalanced."""
    sounding = {}
    pairs = []
    for event in events:
        if event["type"] == "note_on":
            key = (event["channel"], event["note"])
            if key in sounding:
                raise AssertionError(
                    f"note {key} retriggered at tick {event['tick']} while still "
                    f"sounding from tick {sounding[key]}")
            sounding[key] = event["tick"]
        elif event["type"] == "note_off":
            key = (event["channel"], event["note"])
            if key not in sounding:
                raise AssertionError(f"note off for {key} that was never on")
            pairs.append((key, sounding.pop(key), event["tick"]))
    if sounding:
        raise AssertionError(f"notes left hanging at end of track: {sorted(sounding)}")
    return pairs


class TestSMF(unittest.TestCase):
    def test_vlq(self):
        self.assertEqual(_vlq(0), b"\x00")
        self.assertEqual(_vlq(127), b"\x7f")
        self.assertEqual(_vlq(128), b"\x81\x00")
        self.assertEqual(_vlq(8192), b"\xc0\x00")
        self.assertEqual(_vlq(0x0FFFFFFF), b"\xff\xff\xff\x7f")
        with self.assertRaises(ValueError):
            _vlq(-1)

    def test_header_and_round_trip(self):
        midi = MidiFile(ticks_per_beat=96)
        track = midi.add_track("one")
        track.tempo(0, 140)
        track.note(0, 96, 60, 100)
        data = midi.to_bytes()
        self.assertEqual(data[:4], b"MThd")
        parsed = parse_midi_file(data)
        self.assertEqual(parsed["ticks_per_beat"], 96)
        self.assertEqual(parsed["format"], 0)  # single track collapses to format 0
        # SMF stores microseconds per quarter note as an integer, so the BPM
        # that comes back is quantised rather than exact.
        tempos = [e["bpm"] for e in parsed["tracks"][0] if e.get("bpm")]
        self.assertEqual(len(tempos), 1)
        self.assertAlmostEqual(tempos[0], 140.0, places=2)

    def test_event_order_within_a_tick(self):
        """Note off, then controllers, then note on -- MPE depends on this."""
        midi = MidiFile()
        track = midi.add_track("order")
        track.note_on(0, 60, 100)
        track.note_off(480, 60)
        track.note_on(480, 62, 100)      # written before its predecessor's controller
        track.cc(480, 41, 90)
        order = [e["type"] for e in parse_midi_file(midi.to_bytes())["tracks"][0]
                 if e["tick"] == 480 and e["type"] != "meta"]
        self.assertEqual(order, ["note_off", "cc", "note_on"])

    def test_channels_are_one_indexed(self):
        midi = MidiFile()
        track = midi.add_track("ch")
        track.note(0, 10, 60, 100, channel=16)
        self.assertEqual(parse_midi_file(midi.to_bytes())["tracks"][0][1]["channel"], 16)
        with self.assertRaises(ValueError):
            track.note_on(0, 60, 100, channel=0)
        with self.assertRaises(ValueError):
            track.note_on(0, 60, 100, channel=17)

    def test_bend_maths(self):
        self.assertEqual(cents_to_bend(0, 48), 8192)
        self.assertEqual(cents_to_bend(4800, 48), 16383)
        self.assertEqual(cents_to_bend(-4800, 48), 0)
        self.assertEqual(cents_to_bend(9600, 48), 16383)   # clamped, not wrapped
        self.assertEqual(cents_to_bend(200, 2), 16383)


class TestSurgeFacts(unittest.TestCase):
    def test_macro_ccs(self):
        """Surge initialises controllers[i] = 41 + i."""
        self.assertEqual(surge.MACRO_CC, {1: 41, 2: 42, 3: 43, 4: 44,
                                          5: 45, 6: 46, 7: 47, 8: 48})
        self.assertEqual(surge.macro_cc(1), 41)
        with self.assertRaises(ValueError):
            surge.macro_cc(9)

    def test_reserved_ccs_are_refused(self):
        for controller in (0, 6, 32, 38, 98, 99, 100, 101, 120, 123):
            with self.assertRaises(ValueError):
                surge.validate_cc(controller)
        self.assertEqual(surge.validate_cc(41), ["CC 41 is Surge macro 1 by default"])

    def test_mpe_configuration_message(self):
        """Bn 65 00 / Bn 64 06 / Bn 06 mm on channel 1, then RPN 0 on channel 2."""
        midi = MidiFile()
        track = midi.add_track("mpe")
        surge.write_mpe_setup(track, member_channels=15, bend_range=48,
                              master_bend_range=2)
        ccs = [(e["channel"], e["controller"], e["value"])
               for e in parse_midi_file(midi.to_bytes())["tracks"][0]
               if e["type"] == "cc"]
        self.assertEqual(ccs[:3], [(1, 101, 0), (1, 100, 6), (1, 6, 15)])
        self.assertEqual(ccs[3:6], [(2, 101, 0), (2, 100, 0), (2, 6, 48)])
        self.assertEqual(ccs[6:9], [(1, 101, 0), (1, 100, 0), (1, 6, 2)])
        self.assertEqual(ccs[-2:], [(1, 101, 127), (1, 100, 127)])

    def test_scene_split(self):
        """Surge: splitChan = splitpoint / 8 + 1 on 0-indexed channels."""
        split = surge.scene_split_channels(2)
        self.assertEqual(split["A"], [1, 2])
        self.assertEqual(split["B"][0], 3)
        self.assertEqual(surge.splitpoint_for_channel(2), 8)
        self.assertEqual(surge.splitpoint_for_channel(1), 0)


class TestTheory(unittest.TestCase):
    def test_note_names(self):
        self.assertEqual(note_name(60), "C4")
        self.assertEqual(parse_note("C4"), 60)
        self.assertEqual(parse_note("F#2"), 42)
        self.assertEqual(parse_note("Bb3"), 58)
        self.assertEqual(parse_note(60), 60)
        self.assertEqual(note_name(60, middle_c_octave=3), "C3")

    def test_scale_degree_round_trip(self):
        scale = Scale("D", "Dorian")
        for index in range(-7, 15):
            self.assertEqual(scale.index_of(scale.degree(index)), index)
        self.assertIsNone(scale.index_of(61))          # C# is not in D dorian
        self.assertEqual(scale.quantize(61), 60)

    def test_case_sets_chord_quality(self):
        major, minor = parse_progression(["IV", "iv"], "C")
        self.assertEqual(major.notes(), [53, 57, 60])
        self.assertEqual(minor.notes(), [53, 56, 60])

    def test_flat_degrees(self):
        chord = parse_progression(["bVII"], "C")[0]
        self.assertEqual(chord.root % 12, 10)          # Bb

    def test_every_named_progression_parses(self):
        for name, symbols in PROGRESSIONS.items():
            with self.subTest(progression=name):
                self.assertTrue(parse_progression(symbols, "C"))

    def test_voice_leading_reduces_movement(self):
        chords = parse_progression(["I", "V"], "C")
        naive = sum(abs(a - b) for a, b in zip(chords[0].notes(), chords[1].notes()))
        led = voice_lead(chords[1], voice_lead(chords[0], None))
        smart = sum(min(abs(n - p) for p in voice_lead(chords[0], None)) for n in led)
        self.assertLess(smart, naive)


class TestRhythm(unittest.TestCase):
    def test_divisions(self):
        self.assertEqual(parse_division("1/4", 480), 480)
        self.assertEqual(parse_division("1/16", 480), 120)
        self.assertEqual(parse_division("1/8T", 480), 160)
        self.assertEqual(parse_division("1/4.", 480), 720)
        self.assertEqual(parse_division(37, 480), 37)
        with self.assertRaises(ValueError):
            parse_division("quaver", 480)

    def test_known_euclidean_rhythms(self):
        self.assertEqual(euclidean(3, 8), [True, False, False, True, False,
                                           False, True, False])   # tresillo
        self.assertEqual(sum(euclidean(5, 8)), 5)
        self.assertEqual(euclidean(0, 4), [False] * 4)
        self.assertEqual(euclidean(4, 4), [True] * 4)
        self.assertEqual(len(euclidean(7, 16)), 16)

    def test_euclidean_is_maximally_even(self):
        pattern = euclidean(5, 13)
        gaps = []
        indices = [i for i, hit in enumerate(pattern) if hit]
        for a, b in zip(indices, indices[1:] + [indices[0] + 13]):
            gaps.append(b - a)
        self.assertLessEqual(max(gaps) - min(gaps), 1)


class TestAutomation(unittest.TestCase):
    def test_lane_spec(self):
        lane = parse_lane_spec("macro3:sine:8:0.5:0.25")
        self.assertEqual((lane.controller, lane.shape, lane.period_bars), (43, "sine", 8.0))
        self.assertEqual(parse_lane_spec("timbre:ramp").controller, 74)
        with self.assertRaises(ValueError):
            parse_lane_spec("nonsense:sine")

    def test_lane_values_stay_in_range_and_dedupe(self):
        midi = MidiFile()
        track = midi.add_track("auto")
        written = render_lane(track, Lane(41, "sine", 2.0), 0, 480 * 16, 480)
        events = [e for e in parse_midi_file(midi.to_bytes())["tracks"][0]
                  if e["type"] == "cc"]
        self.assertEqual(len(events), written)
        self.assertTrue(all(0 <= e["value"] <= 127 for e in events))
        for a, b in zip(events, events[1:]):
            self.assertNotEqual(a["value"], b["value"])

    def test_reserved_cc_is_refused(self):
        midi = MidiFile()
        with self.assertRaises(ValueError):
            render_lane(midi.add_track("x"), Lane(6, "sine"), 0, 480, 480)


class TestTuning(unittest.TestCase):
    def test_scl_token_forms(self):
        tuning = parse_scl("! t.scl\ntest\n 3\n 100.0\n 3/2\n 2\n")
        self.assertEqual(len(tuning.pitches), 4)
        self.assertAlmostEqual(tuning.pitches[1], 100.0)
        self.assertAlmostEqual(tuning.pitches[2], 701.955, places=3)
        self.assertAlmostEqual(tuning.pitches[3], 1200.0, places=6)

    def test_12_edo_matches_equal_temperament(self):
        tuning = load_tuning("12-edo")
        for note in range(24, 108):
            self.assertAlmostEqual(tuning.deviation_cents(note), 0.0, places=6)

    def test_just_intonation_deviations(self):
        tuning = load_tuning("just")
        self.assertAlmostEqual(tuning.deviation_cents(64), -13.686, places=2)  # major 3rd
        self.assertAlmostEqual(tuning.deviation_cents(67), 1.955, places=2)    # fifth
        self.assertAlmostEqual(tuning.frequency(60), 261.626, places=2)

    def test_non_octave_period(self):
        tuning = load_tuning("bohlen-pierce")
        self.assertEqual(tuning.count, 13)
        self.assertAlmostEqual(tuning.period, 1901.955, places=2)
        self.assertAlmostEqual(tuning.frequency(73) / tuning.frequency(60), 3.0, places=6)

    def test_edo_generator(self):
        tuning = parse_scl(edo_scl(19))
        self.assertEqual(tuning.count, 19)
        self.assertAlmostEqual(tuning.pitches[1], 1200 / 19, places=4)

    def test_malformed_scl(self):
        for text in ("", "just a line", "desc\n0\n", "desc\n3\n100.0\n"):
            with self.subTest(text=text):
                with self.assertRaises(ValueError):
                    parse_scl(text)


class TestMPE(unittest.TestCase):
    def test_allocator_never_reuses_a_sounding_channel(self):
        allocator = MPEAllocator(range(2, 17))
        busy = {}
        for tick in range(0, 4000, 40):
            channel = allocator.acquire(tick, 400)
            if channel in busy:
                self.assertLessEqual(busy[channel], tick,
                                     "channel handed out while still sounding")
            busy[channel] = tick + 400
        self.assertEqual(allocator.steals, 0)

    def test_allocator_steals_only_when_saturated(self):
        allocator = MPEAllocator([2, 3])
        for tick in range(3):
            allocator.acquire(tick, 1000)
        self.assertEqual(allocator.steals, 1)

    def test_expression_precedes_note_on_and_resets_after(self):
        midi = MidiFile()
        track = midi.add_track("note")
        play_note(track, 0, 480, 60, 100, channel=2,
                  expression=Expression(pressure="swell", timbre_from=10, timbre_to=100),
                  bend_range=48)
        events = [e for e in parse_midi_file(midi.to_bytes())["tracks"][0]
                  if e["type"] != "meta"]
        first_note = next(i for i, e in enumerate(events) if e["type"] == "note_on")
        self.assertTrue(any(e["type"] in ("pitch_bend", "channel_pressure", "cc")
                            for e in events[:first_note]))
        tail = [e for e in events if e["tick"] == 480]
        self.assertEqual(tail[0]["type"], "note_off")
        self.assertIn(8192, [e["value"] for e in tail if e["type"] == "pitch_bend"])
        self.assertIn(0, [e["value"] for e in tail if e["type"] == "channel_pressure"])

    def test_microtonal_detune_is_written_before_the_note(self):
        midi = MidiFile()
        track = midi.add_track("note")
        play_note(track, 0, 480, 60, 100, channel=2,
                  expression=Expression(detune_cents=-13.686), bend_range=48)
        events = [e for e in parse_midi_file(midi.to_bytes())["tracks"][0]
                  if e["type"] in ("pitch_bend", "note_on")]
        self.assertEqual(events[0]["type"], "pitch_bend")
        self.assertLess(events[0]["value"], 8192)


class TestGenerators(unittest.TestCase):
    def setUp(self):
        self.ctx = Context(bpm=120, bars=4, key="A", scale_name="Natural Minor", seed=5)
        self.plan = build_chord_plan(self.ctx, "minor-loop")

    def test_chord_plan_covers_every_bar(self):
        self.assertEqual(self.plan.slots[0].start, 0)
        self.assertEqual(self.plan.slots[-1].end, self.ctx.total_ticks)
        for a, b in zip(self.plan.slots, self.plan.slots[1:]):
            self.assertEqual(a.end, b.start)

    def test_every_generator_produces_notes_inside_the_piece(self):
        for name, generator in GENERATORS.items():
            with self.subTest(generator=name):
                part = generator(self.ctx, self.plan)
                self.assertTrue(part.notes, f"{name} produced nothing")
                for note in part.notes:
                    self.assertGreaterEqual(note.tick, 0)
                    self.assertGreater(note.duration, 0)
                    self.assertTrue(0 <= note.pitch <= 127)
                    self.assertTrue(1 <= note.velocity <= 127)

    def test_bass_sits_below_the_lead(self):
        bass = GENERATORS["bass"](self.ctx, self.plan)
        lead = GENERATORS["melody"](self.ctx, self.plan)
        self.assertLess(max(n.pitch for n in bass.notes),
                        min(n.pitch for n in lead.notes))

    def test_unknown_options_are_rejected_clearly(self):
        from surge_midigen.song import build_song, parse_part_spec
        with self.assertRaises(ValueError):
            parse_part_spec("wobble")               # unknown generator
        with self.assertRaises(ValueError):
            parse_part_spec("arp:mode")             # not key=value
        with self.assertRaises(ValueError) as caught:
            build_song(bars=1, parts=["arp:nonsense=1"])
        self.assertIn("nonsense", str(caught.exception))


class TestSongBuilds(unittest.TestCase):
    def test_every_preset_builds_cleanly(self):
        for name in PRESETS:
            with self.subTest(preset=name):
                result = build_song(name, seed=3)
                data = parse_midi_file(result.midi.to_bytes())
                self.assertGreater(len(data["tracks"]), 1)
                self.assertEqual(result.warnings, [], f"{name}: {result.warnings}")
                total = 0
                for track in data["tracks"]:
                    total += len(note_pairs(track))     # raises on stuck notes
                self.assertGreater(total, 0, f"{name} produced no notes")

    def test_mpe_presets_never_overlap_on_a_channel(self):
        for name, preset in PRESETS.items():
            if not preset.mpe:
                continue
            with self.subTest(preset=name):
                data = parse_midi_file(build_song(name, seed=1).midi.to_bytes())
                spans = []
                for track in data["tracks"]:
                    for (channel, _pitch), start, end in note_pairs(track):
                        spans.append((channel, start, end))
                by_channel = {}
                for channel, start, end in sorted(spans, key=lambda s: (s[0], s[1])):
                    previous = by_channel.get(channel)
                    if previous is not None:
                        self.assertGreaterEqual(
                            start, previous,
                            f"{name}: channel {channel} had two notes at once")
                    by_channel[channel] = end

    def test_determinism(self):
        first = build_song("berlin-school", seed=9).midi.to_bytes()
        second = build_song("berlin-school", seed=9).midi.to_bytes()
        self.assertEqual(first, second)
        third = build_song("berlin-school", seed=10).midi.to_bytes()
        self.assertNotEqual(first, third)

    def test_bend_mode_tuning_writes_bends(self):
        result = build_song(bars=2, parts=["melody"], tuning="19-edo",
                            tuning_mode="bend", mpe=True, seed=2)
        bends = [e for track in parse_midi_file(result.midi.to_bytes())["tracks"]
                 for e in track if e["type"] == "pitch_bend"]
        self.assertTrue(any(e["value"] != 8192 for e in bends))

    def test_scala_mode_leaves_pitch_alone(self):
        result = build_song(bars=2, parts=["melody"], tuning="19-edo",
                            tuning_mode="scala", seed=2)
        bends = [e for track in parse_midi_file(result.midi.to_bytes())["tracks"]
                 for e in track if e["type"] == "pitch_bend"]
        self.assertTrue(all(e["value"] == 8192 for e in bends))

    def test_custom_parts_and_channels(self):
        result = build_song(bars=2, parts=["bass:channel=1", "arp:channel=2:mode=down"],
                            lanes=["macro1:ramp:2"], seed=4)
        data = parse_midi_file(result.midi.to_bytes())
        channels = {e["channel"] for track in data["tracks"] for e in track
                    if e["type"] == "note_on"}
        self.assertEqual(channels, {1, 2})

    def test_time_signature_changes_bar_length(self):
        result = build_song(bars=2, parts=["chords"], time_signature=(7, 8), seed=1)
        self.assertEqual(result.context.beats_per_bar, 7)
        self.assertEqual(result.context.total_ticks, 2 * 7 * 480)


class TestCombinationSweep(unittest.TestCase):
    """Every mode, meter and tuning combination has to survive a structural check.

    The failure this guards against is not a crash but a file that loads and
    then misbehaves: a hanging note, a bend outside 14 bits, a channel outside
    1-16.
    """

    def assertStructurallyValid(self, result, label):
        data = parse_midi_file(result.midi.to_bytes())
        for track in data["tracks"]:
            note_pairs(track)                    # raises on retrigger or hang
            for event in track:
                if "channel" in event:
                    self.assertTrue(1 <= event["channel"] <= 16, label)
                if event["type"] == "cc":
                    self.assertTrue(0 <= event["value"] <= 127, label)
                if event["type"] == "pitch_bend":
                    self.assertTrue(0 <= event["value"] <= 16383, label)

    def test_every_arp_mode(self):
        from surge_midigen.generators import ARP_MODES
        for mode in ARP_MODES:
            for mpe in (False, True):
                label = f"arp {mode} mpe={mpe}"
                with self.subTest(mode=mode, mpe=mpe):
                    self.assertStructurallyValid(
                        build_song(bars=4, parts=[f"arp:mode={mode}"], mpe=mpe, seed=2),
                        label)

    def test_every_bass_style(self):
        from surge_midigen.generators import BASS_STYLES
        for style in BASS_STYLES:
            with self.subTest(style=style):
                self.assertStructurallyValid(
                    build_song(bars=4, parts=[f"bass:style={style}"], seed=3), style)

    def test_odd_meters_and_resolutions(self):
        for signature in ((3, 4), (5, 4), (7, 8)):
            for ppq in (96, 480, 960):
                with self.subTest(signature=signature, ppq=ppq):
                    self.assertStructurallyValid(
                        build_song(bars=4, parts=["chords:rate=1/8", "bass", "melody"],
                                   time_signature=signature, ticks_per_beat=ppq,
                                   swing=0.3, groove="dilla", humanize=12,
                                   humanize_velocity=15, seed=8),
                        f"{signature} @ {ppq}")

    def test_narrow_mpe_zones(self):
        """One member channel is legal MPE and must still not double up."""
        for members in (1, 2, 15):
            with self.subTest(members=members):
                self.assertStructurallyValid(
                    build_song(bars=4, parts=["pad", "arp"], mpe=True,
                               member_channels=members, seed=4),
                    f"{members} member channels")

    def test_tuning_combinations(self):
        for name in ("19-edo", "just", "bohlen-pierce", "edo:31"):
            for mode in ("scala", "bend"):
                with self.subTest(tuning=name, mode=mode):
                    self.assertStructurallyValid(
                        build_song(bars=4, parts=["melody"], tuning=name,
                                   tuning_mode=mode, mpe=(mode == "bend"), seed=5),
                        f"{name}/{mode}")


class TestCLI(unittest.TestCase):
    def test_song_command_writes_a_file(self):
        import tempfile
        from surge_midigen.cli import main
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "nested", "out.mid")
            self.assertEqual(main(["song", "--preset", "techno-stab", "-o", path, "-q"]), 0)
            self.assertTrue(os.path.exists(path))
            self.assertEqual(parse_midi_file(path)["format"], 1)

    def test_bad_input_exits_cleanly(self):
        from surge_midigen.cli import main
        errors = io.StringIO()
        with contextlib.redirect_stderr(errors):
            self.assertEqual(main(["song", "-o", "/tmp/should-not-exist.mid",
                                   "--part", "wobble"]), 2)
        self.assertIn("wobble", errors.getvalue())

    def test_list_and_tuning_commands(self):
        from surge_midigen.cli import main
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            self.assertEqual(main(["list", "cc"]), 0)
            self.assertEqual(main(["tuning", "just", "--keys", "3"]), 0)
        self.assertIn("CC 41", output.getvalue())
        self.assertIn("261.6", output.getvalue())


if __name__ == "__main__":
    unittest.main()
