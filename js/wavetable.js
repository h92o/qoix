/* ============================================================
   QOIX Synthesizer — Wavetable Oscillator
   ============================================================
   Two modes:
     1. Wavetable  — scan through a bank of named single-cycle
                     waveforms. Position and morph-speed param.
     2. Oxford     — OSCar-style additive harmonic oscillator.
                     Directly set amplitude of harmonics 1–16.
   ============================================================ */

'use strict';

const WTEngine = (() => {

  // ── Wavetable bank ────────────────────────────────────────
  // Each entry is a set of harmonic amplitudes; the oscillator is
  // band-limited by PeriodicWave, so no sample table is needed.
  function buildTable(harmonicAmps) {
    // harmonicAmps[0] = amplitude of 1st harmonic (fundamental), etc.
    const real = new Float32Array(harmonicAmps.length + 1);
    const imag = new Float32Array(harmonicAmps.length + 1);
    real[0] = 0; imag[0] = 0;
    harmonicAmps.forEach((amp, i) => {
      imag[i + 1] = amp;
    });
    return { real, imag };
  }

  // Named wavetable positions (harmonic amplitude arrays)
  const WAVETABLE_BANK = {
    'Sine': buildTable([1]),
    'Triangle': buildTable([1, 0, -1/9, 0, 1/25, 0, -1/49, 0, 1/81]),
    'Square': buildTable([1, 0, 1/3, 0, 1/5, 0, 1/7, 0, 1/9, 0, 1/11]),
    'Sawtooth': buildTable([1, 1/2, 1/3, 1/4, 1/5, 1/6, 1/7, 1/8, 1/9, 1/10, 1/11, 1/12]),
    'Ramp': buildTable([-1, 1/2, -1/3, 1/4, -1/5, 1/6, -1/7, 1/8]),
    'Pulse 25%': buildTable([1, -0.5, 0, 0.5, -1, 0.5, 0, -0.5, 1, -0.5]),
    'Half Sine': buildTable([0.6366, 0, -0.2122, 0, 0.1273, 0, -0.0909, 0, 0.0707]),
    'Vocal Ah': buildTable([1, 0.6, 0.4, 0.8, 0.5, 0.3, 0.1, 0.2, 0.05, 0.1, 0.02]),
    'Vocal Eh': buildTable([1, 0.9, 0.3, 0.4, 0.6, 0.2, 0.3, 0.1, 0.2, 0.05]),
    'Vocal Oh': buildTable([1, 0.3, 0.5, 0.1, 0.2, 0.05, 0.1, 0.02, 0.05]),
    'Cello': buildTable([1, 0.85, 0.7, 0.55, 0.4, 0.3, 0.2, 0.15, 0.1, 0.07, 0.04, 0.02]),
    'Brass': buildTable([1, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2, 0.1, 0.05, 0.02]),
    'Reed': buildTable([1, 0, 0.7, 0, 0.4, 0, 0.2, 0, 0.1, 0, 0.05]),
    'Glass': buildTable([0.5, 0, 0, 0.8, 0, 0, 0.3, 0, 0, 0.1, 0, 0, 0.05]),
    'Bell 1': buildTable([1, 0, 0.5, 0, 0, 0.3, 0, 0, 0.15, 0, 0, 0, 0.07]),
    'Bell 2': buildTable([0.8, 0, 0, 0.6, 0, 0, 0.4, 0, 0, 0, 0.2, 0, 0, 0.1]),
    'Formant': buildTable([0.2, 0.5, 1.0, 0.8, 0.4, 0.1, 0.05, 0.3, 0.6, 0.4, 0.2, 0.1]),
    'Organ 1': buildTable([1, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1]),
    'Organ 2': buildTable([1, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1]),
    'Chiptune': buildTable([1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1]),
  };

  const TABLE_NAMES = Object.keys(WAVETABLE_BANK);

  // ── Oxford (OSCar) harmonic oscillator ───────────────────
  // 16 harmonics, freely settable
  const DEFAULT_OXFORD_HARMONICS = new Float32Array(16).fill(0);
  DEFAULT_OXFORD_HARMONICS[0] = 1.0; // fundamental

  // ── State ─────────────────────────────────────────────────
  const state = {
    enabled: false,
    mode: 'wavetable',         // 'wavetable' | 'oxford'
    // Wavetable mode
    tableA: 'Sine',
    tableB: 'Sawtooth',
    position: 0,               // 0=tableA, 1=tableB
    positionMod: 0,            // LFO modulation amount for position
    // Oxford mode
    harmonics: Array.from(DEFAULT_OXFORD_HARMONICS),
    // Shared
    level: 0.7,
    octave: 0,
    detune: 0,
    // Amplitude envelope. Without one, every note started and stopped
    // at full level, which clicked audibly on each key press.
    env: { attack: 0.005, decay: 0.08, sustain: 0.85, release: 0.12 },
  };

  // ── Context ───────────────────────────────────────────────
  let _ctx = null;
  let _destination = null;
  const activeVoices = new Map();

  // Cached PeriodicWave objects per context
  const _waveCache = new Map();
  let _positionMod = 0;   // mod-matrix WT Position offset, -1..+1

  function setContext(ctx, destination) {
    _ctx = ctx;
    _destination = destination;
    _waveCache.clear();
  }

  function setPositionMod(v) {
    const next = v || 0;
    if (next === _positionMod) return;
    _positionMod = next;
    updateWaveform();
  }

  // Morph position including any mod-matrix offset.
  function effectivePosition() {
    return Math.max(0, Math.min(1, state.position + _positionMod));
  }

  function safeDisconnect(node) { try { node.disconnect(); } catch (e) {} }

  function getOxfordWave() {
    // Cache on the harmonic values themselves: dragging one fader used
    // to rebuild a PeriodicWave for every live voice on every input
    // event, which is the single most expensive thing this engine did.
    const key = 'ox:' + state.harmonics.map(h => h.toFixed(3)).join(',');
    if (_waveCache.has(key)) return _waveCache.get(key);
    const n = state.harmonics.length;
    const real = new Float32Array(n + 1);
    const imag = new Float32Array(n + 1);
    state.harmonics.forEach((amp, i) => { imag[i + 1] = amp; });
    const wave = _ctx.createPeriodicWave(real, imag, { disableNormalization: false });
    _cacheWave(key, wave);
    return wave;
  }

  // Bounded LRU-ish cache: morph position is continuous, so an unbounded
  // map would grow without limit while the user drags the slider.
  const MAX_CACHE = 128;
  function _cacheWave(key, wave) {
    if (_waveCache.size >= MAX_CACHE) {
      const oldest = _waveCache.keys().next().value;
      _waveCache.delete(oldest);
    }
    _waveCache.set(key, wave);
  }

  // ── Morphed wave (linear interpolation between A and B) ──
  function getMorphedWave(pos) {
    // Quantise to 1/256 so a slider drag reuses cached waves instead of
    // allocating a fresh PeriodicWave on every pixel of travel.
    pos = Math.round(Math.max(0, Math.min(1, pos)) * 256) / 256;
    const tA = WAVETABLE_BANK[state.tableA];
    const tB = WAVETABLE_BANK[state.tableB];
    if (!tA || !tB) return null;
    const key = `wt:${state.tableA}|${state.tableB}|${pos}`;
    if (_waveCache.has(key)) return _waveCache.get(key);
    const len = Math.max(tA.imag.length, tB.imag.length);
    const real = new Float32Array(len);
    const imag = new Float32Array(len);
    for (let i = 0; i < len; i++) {
      const a = i < tA.imag.length ? tA.imag[i] : 0;
      const b = i < tB.imag.length ? tB.imag[i] : 0;
      imag[i] = a * (1 - pos) + b * pos;
    }
    const wave = _ctx.createPeriodicWave(real, imag, { disableNormalization: false });
    _cacheWave(key, wave);
    return wave;
  }

  // ── Note on ───────────────────────────────────────────────
  function noteOn(midiNote, velocity = 1) {
    if (!_ctx || !state.enabled) return;
    if (activeVoices.has(midiNote)) noteOff(midiNote, true);

    const baseFreq = (typeof Microtonal !== 'undefined' && Microtonal.getState().enabled)
      ? Microtonal.noteToFreq(midiNote)
      : 440 * Math.pow(2, (midiNote - 69) / 12);
    const freq = baseFreq * Math.pow(2, state.octave);
    const now = _ctx.currentTime;

    const osc = _ctx.createOscillator();

    // Set waveform
    if (state.mode === 'oxford') {
      osc.setPeriodicWave(getOxfordWave());
    } else {
      const wave = getMorphedWave(effectivePosition());
      if (wave) osc.setPeriodicWave(wave);
    }

    osc.frequency.value = Math.max(0.01, Math.min(freq, _ctx.sampleRate / 2));
    osc.detune.value = state.detune;

    const gain = _ctx.createGain();
    const e = state.env;
    const peak = state.level * velocity;
    const atk = Math.max(0.001, e.attack);
    const dec = Math.max(0.001, e.decay);
    gain.gain.setValueAtTime(0, now);
    gain.gain.linearRampToValueAtTime(peak, now + atk);
    gain.gain.linearRampToValueAtTime(peak * e.sustain, now + atk + dec);

    osc.connect(gain);
    gain.connect(_destination);
    osc.start(now);

    activeVoices.set(midiNote, { osc, gain, velocity, cleanupTimer: null });
  }

  // ── Note off ──────────────────────────────────────────────
  function noteOff(midiNote, immediate = false) {
    const voice = activeVoices.get(midiNote);
    if (!voice || !_ctx) return;
    const now = _ctx.currentTime;
    const rel = immediate ? 0.015 : Math.max(0.005, state.env.release);
    const g = voice.gain.gain;
    try {
      if (typeof g.cancelAndHoldAtTime === 'function') g.cancelAndHoldAtTime(now);
      else { const v = g.value; g.cancelScheduledValues(now); g.setValueAtTime(v, now); }
    } catch (e) { try { g.cancelScheduledValues(now); } catch (e2) {} }
    g.linearRampToValueAtTime(0, now + rel);
    try { voice.osc.stop(now + rel + 0.05); } catch(e) {}
    activeVoices.delete(midiNote);
    if (voice.cleanupTimer) clearTimeout(voice.cleanupTimer);
    voice.cleanupTimer = setTimeout(() => {
      safeDisconnect(voice.osc);
      safeDisconnect(voice.gain);
    }, (rel + 0.15) * 1000);
  }

  function panic() {
    if (!_ctx) { activeVoices.clear(); return; }
    const now = _ctx.currentTime;
    activeVoices.forEach(voice => {
      try { voice.gain.gain.cancelScheduledValues(now); voice.gain.gain.setValueAtTime(0, now); } catch (e) {}
      try { voice.osc.stop(now); } catch (e) {}
      if (voice.cleanupTimer) clearTimeout(voice.cleanupTimer);
      safeDisconnect(voice.osc);
      safeDisconnect(voice.gain);
    });
    activeVoices.clear();
  }

  // ── Update live voices with new waveform ─────────────────
  function updateWaveform() {
    if (!_ctx || activeVoices.size === 0) return;
    // Compute the wave once and share it across voices rather than
    // rebuilding it per voice.
    const wave = state.mode === 'oxford' ? getOxfordWave() : getMorphedWave(effectivePosition());
    if (!wave) return;
    activeVoices.forEach(({ osc }) => osc.setPeriodicWave(wave));
  }

  // ── State setters ─────────────────────────────────────────
  function setEnabled(v) { state.enabled = !!v; if (!v) panic(); }
  function setEnv(param, value) { state.env[param] = parseFloat(value); }
  function setMode(m) { state.mode = m; updateWaveform(); }
  function setTableA(n) { state.tableA = n; updateWaveform(); }
  function setTableB(n) { state.tableB = n; updateWaveform(); }
  function setPosition(v) { state.position = parseFloat(v); updateWaveform(); }
  function setHarmonic(idx, v) {
    if (idx < 0 || idx >= state.harmonics.length) return;
    state.harmonics[idx] = parseFloat(v);
    updateWaveform();
  }
  function setLevel(v) {
    state.level = parseFloat(v);
    if (!_ctx) return;
    const now = _ctx.currentTime;
    // Scale by each voice's own velocity, and ramp: the old version
    // slammed every voice to the raw level and threw velocity away.
    activeVoices.forEach(voice => {
      const target = state.level * (voice.velocity || 1) * state.env.sustain;
      voice.gain.gain.setTargetAtTime(target, now, 0.02);
    });
  }
  function setOctave(v) { state.octave = parseInt(v, 10) || 0; }
  function setDetune(v) {
    state.detune = parseFloat(v);
    activeVoices.forEach(({ osc }) => { osc.detune.value = state.detune; });
  }

  function getState() { return state; }
  function getTableNames() { return TABLE_NAMES; }

  function loadState(s) {
    Object.assign(state, s);
    if (Array.isArray(s.harmonics)) state.harmonics = s.harmonics.slice();
    if (s.env) state.env = Object.assign({}, state.env, s.env);
    _waveCache.clear();
    updateWaveform();
  }

  return {
    setContext, noteOn, noteOff, panic,
    setEnabled, setMode, setTableA, setTableB,
    setPosition, setHarmonic, setLevel, setOctave, setDetune,
    setEnv, setPositionMod,
    getState, getTableNames, loadState,
    get activeVoices() { return activeVoices; },
  };

})();

if (typeof module !== 'undefined' && module.exports) module.exports = WTEngine;
