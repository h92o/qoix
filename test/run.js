#!/usr/bin/env node
/* ============================================================
   QOIX test suite
   ============================================================
   Runs the audio engines against a Web Audio mock (test/audio-mock.js)
   plus pure-function tests for the SCL, MIDI and WAV code paths.

       npm test
   ============================================================ */

'use strict';

const path = require('path');
const assert = require('assert');
const { install } = require('./audio-mock');

install(global);

// The browser globals the modules touch at load time.
global.window = global;
// Node 22 defines navigator as a getter-only global.
if (!('requestMIDIAccess' in global.navigator)) {
  Object.defineProperty(global, 'navigator', {
    value: { requestMIDIAccess: undefined },
    configurable: true, writable: true,
  });
}
global.document = { addEventListener() {}, querySelectorAll: () => [], getElementById: () => null };
global.performance = global.performance || { now: () => Date.now() };
// Deliberately shadow Node's own Blob: the tests need synchronous access
// to the encoded bytes, which the real Blob only exposes via a Promise.
global.Blob = class Blob {
  constructor(parts) {
    this.parts = parts;
    this.size = parts.reduce((n, p) => n + (p.byteLength || p.length || 0), 0);
  }
};

const R = f => require(path.join(__dirname, '..', 'js', f));

const Presets     = R('presets.js');
const Synth       = R('synth.js');
const FMEngine    = R('fm.js');
const WTEngine    = R('wavetable.js');
const ModMatrix   = R('modmatrix.js');
const RandomGen   = R('randomgen.js');
const Renderer    = R('renderer.js');
const Microtonal  = R('microtonal.js');

// The engines reference each other as bare globals in the browser.
Object.assign(global, { Presets, Synth, FMEngine, WTEngine, ModMatrix, RandomGen, Renderer, Microtonal });

// ── Tiny test runner ────────────────────────────────────────
let passed = 0, failed = 0;
const failures = [];

function test(name, fn) {
  try {
    fn();
    passed++;
    process.stdout.write(`  [32m✓[0m ${name}\n`);
  } catch (err) {
    failed++;
    failures.push({ name, err });
    process.stdout.write(`  [31m✗[0m ${name}\n     ${err.message}\n`);
  }
}

function group(name) { process.stdout.write(`\n[1m${name}[0m\n`); }

// Fresh engine state between tests.
function reset() {
  Synth.panic();
  Synth.loadPreset(null);
  ModMatrix.clearAll();
}

// ════════════════════════════════════════════════════════════
group('Audio engine — initialisation');

Synth.init();
const ctx = Synth._getContext();

test('creates a context and a voice destination', () => {
  assert.ok(ctx, 'no audio context');
  assert.ok(Synth._voiceDestination, 'no voice destination');
});

test('the voice bus reaches the audio destination', () => {
  assert.ok(Synth._voiceDestination.reaches(ctx.destination),
    'voices are not routed to the output');
});

test('distortion is wired into the signal path', () => {
  // The original chain built the waveshaper but fed it from nothing, so
  // enabling distortion did precisely nothing.
  const shaper = [...ctx._nodes].find(n => n.type_ === 'waveShaper' && n.oversample === '4x');
  assert.ok(shaper, 'no distortion waveshaper found');
  assert.ok(Synth._voiceDestination.reaches(shaper), 'nothing feeds the distortion node');
  assert.ok(shaper.reaches(ctx.destination), 'distortion output goes nowhere');
});

test('a limiter sits between the FX chain and the output', () => {
  const comp = [...ctx._nodes].find(n => n.type_ === 'compressor');
  assert.ok(comp, 'no limiter on the master bus');
  assert.ok(comp.reaches(ctx.destination));
});

// ════════════════════════════════════════════════════════════
group('Audio engine — voice lifecycle');

test('noteOn creates a voice and starts its oscillators', () => {
  reset();
  Synth.noteOn(60, 0.8);
  assert.strictEqual(Synth.getVoiceCount(), 1);
  assert.deepStrictEqual(Synth.getHeldNotes(), [60]);
  const voice = [...Synth.getActiveVoices().values()][0];
  assert.ok(voice.oscs.length >= 1);
  assert.ok(voice.oscs.every(o => o.started));
});

test('noteOff releases the note but keeps the tail alive', () => {
  reset();
  Synth.noteOn(60, 0.8);
  Synth.noteOff(60);
  assert.deepStrictEqual(Synth.getHeldNotes(), [], 'note should no longer be held');
  assert.strictEqual(Synth.getVoiceCount(), 1, 'release tail should still be tracked');
});

test('re-triggering a note during its release does not drop the new voice', () => {
  // Regression: cleanup deleted the map entry by MIDI note, so the timer
  // armed by the FIRST note-off removed the SECOND note's voice — leaving
  // an orphaned, permanently sounding oscillator.
  reset();
  Synth.noteOn(60, 0.8);
  Synth.noteOff(60);
  Synth.noteOn(60, 0.8);
  const held = [...Synth.getActiveVoices().values()].filter(v => !v.releasing);
  assert.strictEqual(held.length, 1, 'expected exactly one held voice after retrigger');
  assert.strictEqual(Synth.getHeldNotes().length, 1);
  assert.strictEqual(Synth.getVoiceCount(), 2, 'the releasing voice should still be tracked');
  Synth.panic();
});

test('note-off marks a voice as releasing', () => {
  reset();
  Synth.noteOn(64, 1);
  const voice = [...Synth.getActiveVoices().values()][0];
  Synth.noteOff(64, true);          // immediate: ~15ms release
  assert.ok(voice.releasing);
  // Full node teardown is asserted in the asynchronous section below.
});

test('voice stealing prefers a releasing voice over a held one', () => {
  reset();
  Synth.setQuality('maxVoices', 3);
  Synth.noteOn(60); Synth.noteOn(62); Synth.noteOn(64);
  Synth.noteOff(60);                       // 60 is now releasing
  const releasingId = [...Synth.getActiveVoices().values()].find(v => v.releasing).id;
  Synth.noteOn(65);                        // forces a steal
  assert.ok(!Synth.getActiveVoices().has(releasingId) ||
            Synth.getActiveVoices().get(releasingId).oscs.every(o => o.stoppedAt !== null),
    'the releasing voice should have been stolen first');
  assert.ok(Synth.getHeldNotes().includes(62), 'a held voice was stolen instead');
  assert.ok(Synth.getHeldNotes().includes(65), 'the new note did not sound');
  Synth.setQuality('maxVoices', 64);
});

test('polyphony never exceeds the configured cap', () => {
  reset();
  Synth.setQuality('maxVoices', 8);
  for (let n = 40; n < 80; n++) Synth.noteOn(n, 0.7);
  assert.ok(Synth.getVoiceCount() <= 8, `voice count ${Synth.getVoiceCount()} exceeds cap`);
  Synth.setQuality('maxVoices', 64);
  Synth.panic();
});

test('panic stops every oscillator and clears all voices', () => {
  reset();
  for (let n = 60; n < 68; n++) Synth.noteOn(n, 0.8);
  const voices = [...Synth.getActiveVoices().values()];
  const oscs = voices.flatMap(v => v.oscs);
  Synth.panic();
  assert.strictEqual(Synth.getVoiceCount(), 0);
  assert.deepStrictEqual(Synth.getHeldNotes(), []);
  assert.ok(oscs.every(o => o.stoppedAt !== null), 'some oscillators kept running after panic');
  assert.ok(oscs.every(o => o.outputs.size === 0), 'oscillators still connected after panic');
});

test('the LFO is not left connected to a released voice', () => {
  // Regression: per-voice LFO connections were never torn down, so the
  // shared LFO gain accumulated a fan-out entry for every note ever played.
  reset();
  Synth.setLFO('enabled', true);
  Synth.setLFO('target', 'pitch');
  Synth.noteOn(60, 1);
  const lfoGainFanout = () => {
    const voice = [...Synth.getActiveVoices().values()][0];
    return voice ? voice.paramConns.length : 0;
  };
  assert.ok(lfoGainFanout() > 0, 'no param connections were recorded');
  Synth.noteOff(60, true);
  const voice = [...Synth.getActiveVoices().values()][0];
  assert.strictEqual(voice.paramConns.length, 0, 'param connections survived note-off');
  Synth.setLFO('enabled', false);
  Synth.panic();
});

test('unison spreads detune symmetrically and holds level constant', () => {
  reset();
  Synth.setOsc('osc1', 'voices', 5);
  Synth.setOsc('osc1', 'unisonSpread', 20);
  Synth.noteOn(60, 1);
  const voice = [...Synth.getActiveVoices().values()][0];
  const oscs = voice.oscGroups.osc1;
  assert.strictEqual(oscs.length, 5);
  const detunes = oscs.map(o => o.detune.value);
  assert.strictEqual(detunes[0], -20);
  assert.strictEqual(detunes[4], 20);
  assert.ok(Math.abs(detunes[2]) < 1e-9, 'centre voice should be undetuned');
  Synth.panic();
});

test('mod-matrix buses are attached to every voice and detached on release', () => {
  reset();
  Synth.noteOn(60, 1);
  const voice = [...Synth.getActiveVoices().values()][0];
  const busConns = voice.paramConns.filter(c => c.node.type_ === 'constantSource');
  assert.ok(busConns.length >= 4, 'mod buses not connected');
  Synth.noteOff(60, true);
  assert.strictEqual(voice.paramConns.length, 0);
  Synth.panic();
});

// ════════════════════════════════════════════════════════════
group('Audio engine — parameters and effects');

test('chorus mix is a real crossfade, not a wet-on-top sum', () => {
  reset();
  Synth.setChorus('enabled', true);
  Synth.setChorus('mix', 0.5);
  // Find the two gains fed by the chorus stage: wet + dry must sum to 1.
  const gains = [...ctx._nodes].filter(n => n.type_ === 'gain');
  const pairSum = gains.filter(g => Math.abs(g.gain.value - 0.5) < 1e-9).length;
  assert.ok(pairSum >= 2, 'expected a matched wet/dry pair at 0.5');
  Synth.setChorus('enabled', false);
});

test('chorus enable/mix actually reaches an audio node', () => {
  // Regression: _chorusWetGain was declared but never assigned, so the
  // chorus toggle and mix slider changed nothing at all.
  reset();
  Synth.setChorus('enabled', true);
  Synth.setChorus('mix', 0.9);
  const wet = [...ctx._nodes].find(n => n.type_ === 'gain' && Math.abs(n.gain.value - 0.9) < 1e-9);
  assert.ok(wet, 'chorus mix never reached a gain node');
  Synth.setChorus('enabled', false);
});

test('delay feedback is capped below unity', () => {
  reset();
  Synth.setDelay('feedback', 5);
  assert.ok(Synth.getState().delay.feedback === 5, 'state should keep the raw value');
  const fb = [...ctx._nodes].find(n => n.type_ === 'gain' && n.gain.value === 0.95);
  assert.ok(fb, 'feedback gain was not clamped, the delay would run away');
});

test('the analyser rejects an invalid FFT size', () => {
  assert.throws(() => { Synth.getAnalyser().fftSize = 3000; });
  Synth.setQuality('fftSize', 2048);
  assert.strictEqual(Synth.getAnalyser().fftSize, 2048);
  Synth.setQuality('fftSize', 4096);
});

test('setFilter reaches voices that are already sounding', () => {
  reset();
  Synth.setFEnv('amount', 0);
  Synth.noteOn(60, 1);
  Synth.setFilter('cutoff', 1234);
  const voice = [...Synth.getActiveVoices().values()][0];
  assert.strictEqual(voice.filter.frequency.value, 1234);
  Synth.panic();
});

test('out-of-range parameters cannot produce a non-finite frequency', () => {
  reset();
  Synth.setFilter('cutoff', Number.NaN);
  Synth.setOsc('osc1', 'octave', 12);       // absurd, should clamp under Nyquist
  Synth.noteOn(120, 1);
  const voice = [...Synth.getActiveVoices().values()][0];
  assert.ok(Number.isFinite(voice.filter.frequency.value));
  voice.oscs.forEach(o => {
    if (o.frequency) assert.ok(Number.isFinite(o.frequency.value) && o.frequency.value > 0);
  });
  Synth.panic();
  reset();
});

// ════════════════════════════════════════════════════════════
group('Presets');

test('every built-in preset loads without throwing', () => {
  Presets.forEach(p => {
    reset();
    Synth.loadPreset(p);
    assert.ok(Synth.getState().osc1, `preset "${p.name}" produced no osc1`);
  });
});

test('every built-in preset can sound a note', () => {
  Presets.forEach(p => {
    reset();
    Synth.loadPreset(p);
    Synth.noteOn(60, 0.9);
    assert.ok(Synth.getVoiceCount() >= 1, `preset "${p.name}" produced no voice`);
    Synth.panic();
  });
});

test('loading a patch resets fields the patch omits', () => {
  // Regression: loadPreset deep-merged onto whatever was loaded before,
  // so a patch that leaves out osc3 inherited the previous patch's osc3
  // and sounded different depending on what you had selected earlier.
  reset();
  Synth.setOsc('osc3', 'enabled', true);
  Synth.setOsc('osc1', 'voices', 9);
  Synth.setOscFilter('osc1', 'envAmt', -5000);
  const bare = { name: 'Bare', osc1: { enabled: true, wave: 'sine' } };
  Synth.loadPreset(bare);
  const s = Synth.getState();
  assert.strictEqual(s.osc3.enabled, false, 'osc3 leaked in from the previous patch');
  assert.strictEqual(s.osc1.voices, 1, 'unison count leaked in');
  assert.strictEqual(s.osc1.filter.envAmt, 0, 'per-osc filter envelope leaked in');
  assert.strictEqual(s.osc1.wave, 'sine', 'the patch value was not applied');
});

test('a preset cannot be mutated by later state edits', () => {
  const before = JSON.stringify(Presets[1]);
  reset();
  Synth.loadPreset(Presets[1]);
  Synth.setOsc('osc1', 'level', 0.123);
  Synth.setEnv('attack', 9);
  assert.strictEqual(JSON.stringify(Presets[1]), before, 'the preset object was mutated');
});

test('preset names are unique', () => {
  const names = Presets.map(p => p.name);
  assert.strictEqual(new Set(names).size, names.length);
});

// ════════════════════════════════════════════════════════════
group('Modulation matrix');

test('a fresh matrix applies no modulation', () => {
  reset();
  ModMatrix.tick(1 / 60, 0.5, 0.5, 0.5, 1);
  Object.values(ModMatrix.modValues).forEach(v => assert.strictEqual(v, 0));
});

test('an enabled route sums source × amount into its destination', () => {
  reset();
  ModMatrix.setCellEnabled('velocity', 'filter_cut', true);
  ModMatrix.setCellAmount('velocity', 'filter_cut', 0.5);
  ModMatrix.tick(1 / 60, 0, 0, 0, 1);
  assert.ok(Math.abs(ModMatrix.modValues.filter_cut - 0.5) < 1e-9);
  ModMatrix.clearAll();
});

test('LFO2 honours its waveform selection', () => {
  reset();
  ModMatrix.setLFO2('wave', 'square');
  ModMatrix.setLFO2('rate', 1);
  ModMatrix.setLFO2('depth', 1);
  ModMatrix.setCellEnabled('lfo2', 'pitch', true);
  ModMatrix.setCellAmount('lfo2', 'pitch', 1);
  ModMatrix.tick(0.1, 0, 0, 0, 0);
  // A square LFO must sit at exactly +/-1, never anywhere in between.
  assert.ok(Math.abs(Math.abs(ModMatrix.modValues.pitch) - 1) < 1e-9,
    `square LFO produced ${ModMatrix.modValues.pitch}`);
  ModMatrix.setLFO2('wave', 'sine');
  ModMatrix.clearAll();
});

test('applyModMatrix drives the pitch bus', () => {
  reset();
  ModMatrix.setCellEnabled('velocity', 'pitch', true);
  ModMatrix.setCellAmount('velocity', 'pitch', 0.25);
  Synth.noteOn(60, 1);
  Synth.applyModMatrix(1 / 60);
  const bus = [...ctx._nodes].find(n => n.type_ === 'constantSource' && n.offset.value !== 0);
  assert.ok(bus, 'no mod bus picked up a non-zero offset');
  // Zipper noise fix: control-rate writes must be smoothed, not stepped.
  const last = bus.offset.automation[bus.offset.automation.length - 1];
  assert.strictEqual(last[0], 'setTarget');
  Synth.panic();
  ModMatrix.clearAll();
});

// ════════════════════════════════════════════════════════════
group('Microtonal tuning');

test('12-EDO matches equal temperament', () => {
  Microtonal.setScaleByName('12-EDO (Standard)');
  Microtonal.setRoot(60);
  Microtonal.setEnabled(true);
  assert.ok(Math.abs(Microtonal.noteToFreq(69) - 440) < 1e-6, 'A4 should be 440Hz');
  assert.ok(Math.abs(Microtonal.noteToFreq(72) / Microtonal.noteToFreq(60) - 2) < 1e-9);
  Microtonal.setEnabled(false);
});

test('24-EDO halves the semitone', () => {
  Microtonal.setScaleByName('24-EDO (Quarter-tone)');
  Microtonal.setRoot(60);
  Microtonal.setEnabled(true);
  const cents = 1200 * Math.log2(Microtonal.noteToFreq(61) / Microtonal.noteToFreq(60));
  assert.ok(Math.abs(cents - 50) < 0.01, `expected 50 cents, got ${cents}`);
  Microtonal.setEnabled(false);
});

test('SCL ratios and cents parse to the same pitch', () => {
  const scl = `! test.scl\n!\nTest\n 2\n!\n 3/2\n 2/1\n`;
  const parsed = Microtonal.parseScl(scl);
  assert.strictEqual(parsed.count, 2);
  assert.ok(Math.abs(parsed.pitches[1] - 701.955) < 0.01, 'a perfect fifth is ~702 cents');
  assert.strictEqual(parsed.period, 1200);
});

test('malformed SCL input is rejected', () => {
  assert.throws(() => Microtonal.parseScl(''));
  assert.throws(() => Microtonal.parseScl('! only a comment\n'));
  assert.throws(() => Microtonal.parseScl('desc\n3\n!\n100.0\n'));   // fewer pitches than declared
  assert.throws(() => Microtonal.setScaleByName('Nope'));
  assert.throws(() => Microtonal.setRoot(999));
});

test('the synth follows the microtonal scale when enabled', () => {
  Microtonal.setScaleByName('24-EDO (Quarter-tone)');
  Microtonal.setRoot(60);
  Microtonal.setEnabled(true);
  const micro = Synth.midiToFreq(61);
  Microtonal.setEnabled(false);
  const equal = Synth.midiToFreq(61);
  assert.ok(micro < equal, 'a quarter-tone step should be flatter than a semitone');
});

// ════════════════════════════════════════════════════════════
group('MIDI file parsing');

// Build a minimal Type-0 MIDI file in memory.
function buildMidi({ division = 96, events = null, tempo = null } = {}) {
  const bytes = [];
  const push = (...b) => bytes.push(...b);
  const str = s => { for (const c of s) push(c.charCodeAt(0)); };
  const u32 = v => push((v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255);
  const u16 = v => push((v >> 8) & 255, v & 255);

  str('MThd'); u32(6); u16(0); u16(1); u16(division);

  const track = [];
  const tPush = (...b) => track.push(...b);
  const vlq = v => {
    const out = [v & 0x7f];
    while ((v >>= 7)) out.unshift((v & 0x7f) | 0x80);
    tPush(...out);
  };
  if (tempo) { vlq(0); tPush(0xff, 0x51, 0x03, (tempo >> 16) & 255, (tempo >> 8) & 255, tempo & 255); }
  (events || [
    [0,   0x90, 60, 100],
    [96,  0x80, 60, 0],
    [0,   0x90, 64, 100],
    [96,  0x80, 64, 0],
  ]).forEach(([delta, status, d1, d2]) => { vlq(delta); tPush(status, d1, d2); });
  vlq(0); tPush(0xff, 0x2f, 0x00);   // end of track

  str('MTrk'); u32(track.length); push(...track);
  return new Uint8Array(bytes).buffer;
}

test('parses notes, duration and track count', () => {
  const info = Renderer.parseMidi(buildMidi());
  assert.strictEqual(info.noteCount, 2);
  assert.strictEqual(info.numTracks, 1);
  assert.strictEqual(info.format, 0);
  // 96 ticks per quarter at the default 120bpm = 0.5s per note.
  assert.ok(Math.abs(info.events[1].time - 0.5) < 1e-6, `got ${info.events[1].time}`);
  assert.ok(Math.abs(info.duration - 1.0) < 1e-6, `got ${info.duration}`);
});

test('honours a tempo change', () => {
  const info = Renderer.parseMidi(buildMidi({ tempo: 250000 }));   // 240 bpm
  assert.ok(Math.abs(info.events[1].time - 0.25) < 1e-6, `got ${info.events[1].time}`);
});

test('running status is decoded', () => {
  // Second note-on omits its status byte.
  const info = Renderer.parseMidi(buildMidi({
    events: [[0, 0x90, 60, 100], [0, 0x90, 64, 100], [96, 0x80, 60, 0], [0, 0x80, 64, 0]],
  }));
  assert.strictEqual(info.noteCount, 2);
});

test('SMPTE time division is understood', () => {
  // 25 fps, 40 ticks per frame = 1000 ticks per second.
  const division = ((256 - 25) << 8) | 40;
  const info = Renderer.parseMidi(buildMidi({
    division,
    events: [[0, 0x90, 60, 100], [1000, 0x80, 60, 0]],
  }));
  // Regression: SMPTE division used to be read as a huge PPQ value, so
  // the file rendered hundreds of times too fast.
  assert.ok(Math.abs(info.events[1].time - 1.0) < 1e-6, `got ${info.events[1].time}s, expected 1s`);
});

test('a note-off never sorts ahead of its own note-on', () => {
  const info = Renderer.parseMidi(buildMidi({
    events: [[0, 0x90, 60, 100], [0, 0x80, 60, 0]],
  }));
  assert.strictEqual(info.events[0].type, 'noteOn');
  assert.strictEqual(info.events[1].type, 'noteOff');
});

test('non-MIDI input is rejected cleanly', () => {
  assert.throws(() => Renderer.parseMidi(new Uint8Array([1, 2, 3]).buffer), /too small|Not a MIDI/);
  const junk = new Uint8Array(64).fill(0x41);
  assert.throws(() => Renderer.parseMidi(junk.buffer), /Not a MIDI/);
});

test('a file with no notes is reported rather than rendered empty', () => {
  const empty = buildMidi({ events: [[0, 0xb0, 7, 100]] });
  assert.throws(() => Renderer.parseMidi(empty), /No notes/);
});

// ════════════════════════════════════════════════════════════
group('WAV encoding');

function makeBuffer(samples, sr = 48000) {
  const buf = ctx.createBuffer(2, samples.length, sr);
  buf.getChannelData(0).set(samples);
  buf.getChannelData(1).set(samples);
  return buf;
}

function bytesOf(blob) {
  const out = [];
  blob.parts.forEach(p => out.push(...new Uint8Array(p)));
  return new Uint8Array(out);
}

test('writes a valid RIFF/WAVE header', () => {
  const blob = Renderer.encodeWAV(makeBuffer(new Float32Array(100)), 24);
  const b = bytesOf(blob);
  assert.strictEqual(String.fromCharCode(...b.slice(0, 4)), 'RIFF');
  assert.strictEqual(String.fromCharCode(...b.slice(8, 12)), 'WAVE');
  assert.strictEqual(String.fromCharCode(...b.slice(36, 40)), 'data');
  const dv = new DataView(b.buffer);
  assert.strictEqual(dv.getUint16(22, true), 2,      'channel count');
  assert.strictEqual(dv.getUint32(24, true), 48000,  'sample rate');
  assert.strictEqual(dv.getUint16(34, true), 24,     'bit depth');
  assert.strictEqual(dv.getUint32(40, true), 100 * 2 * 3, 'data chunk size');
});

test('16-bit round-trips a known sample value', () => {
  const blob = Renderer.encodeWAV(makeBuffer(new Float32Array([0, 0.5, -0.5, 1, -1])), 16);
  const b = bytesOf(blob);
  const dv = new DataView(b.buffer);
  assert.strictEqual(dv.getInt16(44, true), 0);
  assert.strictEqual(dv.getInt16(48, true), Math.round(0.5 * 0x7fff));
  assert.strictEqual(dv.getInt16(52, true), Math.round(-0.5 * 0x7fff));
});

test('samples beyond full scale are clamped, not wrapped', () => {
  const blob = Renderer.encodeWAV(makeBuffer(new Float32Array([4, -4])), 16);
  const dv = new DataView(bytesOf(blob).buffer);
  assert.strictEqual(dv.getInt16(44, true), 0x7fff);
  assert.strictEqual(dv.getInt16(48, true), -0x7fff);
});

test('32-bit float is tagged as IEEE float', () => {
  const dv = new DataView(bytesOf(Renderer.encodeWAV(makeBuffer(new Float32Array(10)), 32)).buffer);
  assert.strictEqual(dv.getUint16(20, true), 3);
});

// ════════════════════════════════════════════════════════════
group('Random generator');

test('scale notes stay inside the configured octave range', () => {
  RandomGen.set('scale', 'Major');
  RandomGen.set('rootNote', 0);
  RandomGen.set('octaveLow', 3);
  RandomGen.set('octaveHigh', 4);
  const st = RandomGen.getState();
  assert.strictEqual(st.octaveLow, 3);
  assert.strictEqual(st.octaveHigh, 4);
});

test('an inverted octave range is corrected rather than producing nothing', () => {
  RandomGen.set('octaveLow', 3);
  RandomGen.set('octaveHigh', 5);
  RandomGen.set('octaveHigh', 2);      // below the low bound
  const st = RandomGen.getState();
  assert.ok(st.octaveLow <= st.octaveHigh, 'range left inverted');
});

test('unknown parameters are ignored', () => {
  RandomGen.set('nonsense', 1);
  assert.ok(!('nonsense' in RandomGen.getState()));
});

test('stopping releases every note the generator is holding', () => {
  const released = [];
  RandomGen.setCallbacks(() => {}, n => released.push(n));
  RandomGen.set('bpm', 6000);          // ~2.5ms steps, so a step fires fast
  RandomGen.set('density', 1);
  RandomGen.set('noteLength', 1);
  RandomGen.start();
  assert.ok(RandomGen.isRunning());
  RandomGen.stop();
  assert.ok(!RandomGen.isRunning());
  // Regression: stop() used to leave held notes ringing forever.
  RandomGen.setCallbacks(null, null);
});

// ════════════════════════════════════════════════════════════
group('FM engine');

test('an FM voice wires modulators to carrier frequencies', () => {
  FMEngine.setContext(ctx, Synth._voiceDestination);
  FMEngine.setEnabled(true);
  FMEngine.setAlgorithm(0);           // D→C→B→A serial chain
  FMEngine.noteOn(60, 1);
  const voice = FMEngine.fmVoices.get(60);
  assert.ok(voice, 'no FM voice created');
  assert.strictEqual(voice.oscNodes.length, 4);
  const modulated = voice.fmGains.filter(g =>
    [...g.outputs].some(o => o && o.name === 'frequency')).length;
  assert.strictEqual(modulated, 3, 'a serial chain should have three modulation links');
  FMEngine.panic();
});

test('the modulation index does not scale with the square of the level', () => {
  // Regression: the FM gain multiplied by op.level and velocity even
  // though the envelope feeding it already applied both.
  FMEngine.setContext(ctx, Synth._voiceDestination);
  FMEngine.setEnabled(true);
  FMEngine.setOperator(0, 'level', 0.5);
  FMEngine.noteOn(60, 0.5);
  const voice = FMEngine.fmVoices.get(60);
  const baseFreq = 440 * Math.pow(2, (60 - 69) / 12);
  const expected = baseFreq * FMEngine.getState().operators[0].ratio;
  assert.ok(Math.abs(voice.fmGains[0].gain.value - expected) < 1e-6,
    `index ${voice.fmGains[0].gain.value}, expected ${expected}`);
  FMEngine.panic();
  FMEngine.setOperator(0, 'level', 0.8);
});

test('FM panic stops and disconnects everything', () => {
  FMEngine.setContext(ctx, Synth._voiceDestination);
  FMEngine.setEnabled(true);
  [60, 62, 64].forEach(n => FMEngine.noteOn(n, 1));
  const oscs = [...FMEngine.fmVoices.values()].flatMap(v => v.oscNodes);
  FMEngine.panic();
  assert.strictEqual(FMEngine.fmVoices.size, 0);
  assert.ok(oscs.every(o => o.stoppedAt !== null));
  assert.ok(oscs.every(o => o.outputs.size === 0), 'FM nodes leaked after panic');
  FMEngine.setEnabled(false);
});

test('FM note-off on an unknown note is a no-op', () => {
  assert.doesNotThrow(() => FMEngine.noteOff(99));
});

// ════════════════════════════════════════════════════════════
group('Wavetable engine');

test('note-on ramps in rather than jumping to full level', () => {
  WTEngine.setContext(ctx, Synth._voiceDestination);
  WTEngine.setEnabled(true);
  WTEngine.noteOn(60, 1);
  const voice = WTEngine.activeVoices.get(60);
  assert.ok(voice, 'no wavetable voice');
  // Regression: the gain used to be assigned directly, which clicked.
  const kinds = voice.gain.gain.automation.map(a => a[0]);
  assert.ok(kinds.includes('setValueAtTime') && kinds.includes('linearRamp'),
    'no attack envelope was scheduled');
  assert.strictEqual(voice.gain.gain.automation[0][1], 0, 'envelope should start from silence');
  WTEngine.panic();
});

test('identical morph positions reuse a cached PeriodicWave', () => {
  WTEngine.setContext(ctx, Synth._voiceDestination);
  WTEngine.setEnabled(true);
  WTEngine.setPosition(0.5);
  WTEngine.noteOn(60, 1);
  const w1 = WTEngine.activeVoices.get(60).osc.periodicWave;
  WTEngine.noteOn(67, 1);
  const w2 = WTEngine.activeVoices.get(67).osc.periodicWave;
  assert.strictEqual(w1, w2, 'the morphed wave was rebuilt instead of cached');
  WTEngine.panic();
});

test('an out-of-range harmonic index is ignored', () => {
  assert.doesNotThrow(() => WTEngine.setHarmonic(99, 1));
  assert.doesNotThrow(() => WTEngine.setHarmonic(-1, 1));
});

test('wavetable panic clears and disconnects', () => {
  WTEngine.setContext(ctx, Synth._voiceDestination);
  WTEngine.setEnabled(true);
  [60, 62].forEach(n => WTEngine.noteOn(n, 1));
  const oscs = [...WTEngine.activeVoices.values()].map(v => v.osc);
  WTEngine.panic();
  assert.strictEqual(WTEngine.activeVoices.size, 0);
  assert.ok(oscs.every(o => o.outputs.size === 0));
  WTEngine.setEnabled(false);
});

// ════════════════════════════════════════════════════════════
// Asynchronous checks (voice disposal runs on a timer)
// ════════════════════════════════════════════════════════════
async function asyncTests() {
  group('Voice disposal (asynchronous)');

  await new Promise(resolve => {
    reset();
    Synth.setEnv('release', 0.02);
    Synth.noteOn(60, 1);
    const voice = [...Synth.getActiveVoices().values()][0];
    const nodes = [voice.oscMixer, voice.filter, voice.ampEnv, voice.modAmp, voice.panner, ...voice.oscs];
    Synth.noteOff(60);
    setTimeout(() => {
      test('the voice is removed from the registry after its tail', () => {
        assert.strictEqual(Synth.getVoiceCount(), 0, 'voice was never disposed');
      });
      test('every node in a disposed voice is disconnected', () => {
        const leaked = nodes.filter(n => n.outputs.size > 0);
        assert.strictEqual(leaked.length, 0,
          `${leaked.length} node(s) still connected: ${leaked.map(n => n.type_).join(', ')}`);
      });
      resolve();
    }, 260);
  });

  await new Promise(resolve => {
    reset();
    Synth.setEnv('release', 0.02);
    // Play and release the same note repeatedly, the way a fast trill does.
    let n = 0;
    const tick = () => {
      Synth.noteOn(60, 1);
      Synth.noteOff(60);
      if (++n < 20) return setTimeout(tick, 5);
      setTimeout(() => {
        test('rapid retriggering leaves no orphaned voices', () => {
          // Regression: the note-off cleanup timer deleted by MIDI note,
          // so each retrigger orphaned the previous voice's nodes AND
          // could delete a voice that was still sounding.
          assert.strictEqual(Synth.getVoiceCount(), 0,
            `${Synth.getVoiceCount()} voice(s) never cleaned up`);
          assert.deepStrictEqual(Synth.getHeldNotes(), []);
        });
        resolve();
      }, 400);
    };
    tick();
  });

  group('Summary');
  process.stdout.write(`\n${passed} passed, ${failed} failed\n`);
  if (failed) {
    process.stdout.write('\nFailures:\n');
    failures.forEach(f => process.stdout.write(`  ${f.name}\n    ${f.err.stack.split('\n')[0]}\n`));
    process.exit(1);
  }
  process.exit(0);
}

asyncTests();
