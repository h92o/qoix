/* ============================================================
   QOIX — Spectral / FrFT Synthesis Engine
   ============================================================
   Implements chirp oscillators inspired by the Fractional
   Fourier Transform (FrFT). A chirp oscillator exists on the
   continuous rotation from pure time-domain (impulse, α=0)
   to pure frequency-domain (sinusoid, α=1). The FrFT order α
   controls how fast the instantaneous frequency sweeps.

   Eigenspace balance approximates the four projection operators
   of the DFT (λ = 1, −1, +i, −i) via parallel signal paths
   weighted independently.

   Density cross-synthesis mixes the commutator of two operator
   blocks, producing non-linear spectral fusion.
   ============================================================ */

'use strict';

const SpectralFFT = (() => {

  // ── Shared audio context (set by init) ───────────────────
  let ctx   = null;
  let dest  = null;   // connects to Synth._voiceDestination

  const activeVoices = new Map();

  // ── State ─────────────────────────────────────────────────
  const state = {
    enabled: false,

    // FrFT order: 0 = pure tone, 1 = maximum chirp sweep
    alpha: 0.3,

    // Chirp waveform on the frequency LFO
    chirpShape: 'sawtooth',   // sawtooth | sine | triangle

    // Three operator blocks (like FM operators but chirp-based)
    ops: [
      { enabled: true,  ratio: 1.0,  chirpRatio: 2.0,  level: 0.7, octave: 0  },
      { enabled: false, ratio: 2.0,  chirpRatio: 3.0,  level: 0.5, octave: 0  },
      { enabled: false, ratio: 0.5,  chirpRatio: 1.0,  level: 0.4, octave: -1 },
    ],

    // Amplitude envelope
    env: { attack: 0.02, decay: 0.15, sustain: 0.75, release: 0.35 },

    // Eigenspace balance — the four projection spaces of the DFT
    // λ=+1: even / symmetric content   (cosine-like, real)
    // λ=−1: even / phase-inverted      (inverted even)
    // λ=+i: odd / antisymmetric        (sine-like, transient edge)
    // λ=−i: odd / phase-inverted       (inverted odd)
    eigen: { p1: 0.7, pm1: 0.0, pi: 0.7, pmi: 0.0 },

    // Density cross-synthesis: mix commutator product with ops output
    // Commutator [A,B] = AB − BA picks up the "difference dynamics"
    densityCross: 0.0,
    densitySource: 'osc1',   // which subtractive osc to use as source B
  };

  // ── Init (called once, shares context from Synth) ─────────
  function init() {
    ctx  = Synth._getContext();
    dest = Synth._voiceDestination;
    return !!(ctx && dest);
  }

  function ensureInit() {
    // Re-resolve rather than latch: the destination node does not exist
    // until Synth.init() has built the FX chain, and an early call used
    // to cache a null forever.
    if (!ctx || !dest) init();
    return !!(ctx && dest);
  }

  function safeDisconnect(node) { try { node.disconnect(); } catch (e) {} }

  // ── Build eigenspace filter network ───────────────────────
  // Approximation of the four DFT projection operators:
  //   P_{+1}  ≈ low-shelf  → symmetric, real, even content
  //   P_{−1}  ≈ phase-flip of P_{+1}
  //   P_{+i}  ≈ band-pass  → transient/edge content (odd)
  //   P_{−i}  ≈ phase-flip of P_{+i}
  // The output is the weighted sum of all four branches.
  function buildEigenFilter(inputNode, outputNode) {
    const e = state.eigen;

    // λ=+1 branch: lowpass → even/real content
    const f1 = ctx.createBiquadFilter();
    f1.type = 'lowshelf'; f1.frequency.value = 800; f1.gain.value = 0;
    const g1 = ctx.createGain(); g1.gain.value = e.p1;
    inputNode.connect(f1); f1.connect(g1); g1.connect(outputNode);

    // λ=−1 branch: phase-flipped lowshelf
    const fm1 = ctx.createBiquadFilter();
    fm1.type = 'lowshelf'; fm1.frequency.value = 800; fm1.gain.value = 0;
    const gm1inv = ctx.createGain(); gm1inv.gain.value = -1;
    const gm1    = ctx.createGain(); gm1.gain.value = e.pm1;
    inputNode.connect(fm1); fm1.connect(gm1inv); gm1inv.connect(gm1); gm1.connect(outputNode);

    // λ=+i branch: bandpass → transient/odd content
    const fi = ctx.createBiquadFilter();
    fi.type = 'bandpass'; fi.frequency.value = 2000; fi.Q.value = 1.2;
    const gi = ctx.createGain(); gi.gain.value = e.pi;
    inputNode.connect(fi); fi.connect(gi); gi.connect(outputNode);

    // λ=−i branch: phase-flipped bandpass
    const fmi = ctx.createBiquadFilter();
    fmi.type = 'bandpass'; fmi.frequency.value = 2000; fmi.Q.value = 1.2;
    const gmiInv = ctx.createGain(); gmiInv.gain.value = -1;
    const gmi    = ctx.createGain(); gmi.gain.value = e.pmi;
    inputNode.connect(fmi); fmi.connect(gmiInv); gmiInv.connect(gmi); gmi.connect(outputNode);

    return { f1, fm1, fi, fmi, g1, gm1, gi, gmi };
  }

  // ── Compute Hermite-Gaussian waveform as PeriodicWave ─────
  // ψ_n(t) = H_n(t) · exp(−t²/2), evaluated over one period.
  // n=0: Gaussian (smooth, sine-like)
  // n=1: First-order — one zero crossing in Gaussian envelope
  // n=2: Second-order — two sign changes (M-shape)
  // These are the eigenfunctions of the FrFT.
  function hermiteGaussianWave(order) {
    const N = 2048;
    const samples = new Float32Array(N);
    // Sample t from −4σ to +4σ over one period
    for (let n = 0; n < N; n++) {
      const t = (n / N) * 8 - 4;   // t ∈ [−4, +4]
      const env = Math.exp(-t * t / 2);
      let H;
      switch (order) {
        case 0: H = 1; break;
        case 1: H = 2 * t; break;
        case 2: H = 4 * t * t - 2; break;
        case 3: H = 8 * t * t * t - 12 * t; break;
        default: H = 1;
      }
      samples[n] = H * env;
    }

    // Normalize (a plain loop; Math.max(...arr) on a 2048-element
    // spread is needlessly close to the argument-count limit)
    let peak = 0;
    for (let i = 0; i < N; i++) { const a = Math.abs(samples[i]); if (a > peak) peak = a; }
    if (peak > 0) for (let i = 0; i < N; i++) samples[i] /= peak;

    // DFT to PeriodicWave coefficients. Only the first HARMONICS bins
    // matter for a band-limited oscillator, and stopping there turns an
    // O(N^2/2) transform (~2M operations, a visible hitch on the first
    // note) into a ~260k one.
    const HARMONICS = 128;
    const real = new Float32Array(HARMONICS);
    const imag = new Float32Array(HARMONICS);
    for (let k = 0; k < HARMONICS; k++) {
      let re = 0, im = 0;
      for (let n = 0; n < N; n++) {
        const angle = (2 * Math.PI * k * n) / N;
        re += samples[n] * Math.cos(angle);
        im -= samples[n] * Math.sin(angle);
      }
      real[k] = re / N;
      imag[k] = im / N;
    }
    real[0] = 0; imag[0] = 0; // zero DC

    return ctx.createPeriodicWave(real, imag, { disableNormalization: false });
  }

  // Cache computed waves per context
  const _waveCache = {};
  function getHGWave(order) {
    const key = `hg${order}`;
    if (!_waveCache[key]) _waveCache[key] = hermiteGaussianWave(order);
    return _waveCache[key];
  }

  // ── Note On ───────────────────────────────────────────────
  function noteOn(midiNote, velocity = 1) {
    if (!ensureInit()) return;
    if (!state.enabled) return;
    if (activeVoices.has(midiNote)) noteOff(midiNote, true);

    const freq = (typeof Microtonal !== 'undefined' && Microtonal.getState().enabled)
      ? Microtonal.noteToFreq(midiNote)
      : 440 * Math.pow(2, (midiNote - 69) / 12);
    const now  = ctx.currentTime;
    const s    = state;

    const oscs    = [];
    const nodes   = [];   // every intermediate node, so cleanup can free them
    const preMix  = ctx.createGain();

    // ── Build chirp operator blocks ─────────────────────────
    s.ops.forEach((op, idx) => {
      if (!op.enabled) return;

      const nyquist   = ctx.sampleRate / 2;
      const baseFreq  = Math.min(freq * op.ratio * Math.pow(2, op.octave), nyquist * 0.9);
      const chirpRate = Math.min(freq * op.chirpRatio, nyquist * 0.5);
      // Cap the sweep so the carrier cannot be driven negative or past
      // Nyquist, which produced harsh aliasing at high alpha.
      const chirpDepth = Math.min(s.alpha * baseFreq, baseFreq * 0.95, nyquist - baseFreq);

      // Carrier oscillator — use Hermite-Gaussian waveform
      // Order 0 at α=0, progressing with operator index
      const osc = ctx.createOscillator();
      osc.setPeriodicWave(getHGWave(idx));     // each op has different eigenfunction
      osc.frequency.value = baseFreq;

      // Chirp LFO — modulates carrier frequency, creating FrFT sweep
      const lfo = ctx.createOscillator();
      lfo.type = s.chirpShape;
      lfo.frequency.value = chirpRate;

      const lfoGain = ctx.createGain();
      lfoGain.gain.value = chirpDepth;
      lfo.connect(lfoGain);
      lfoGain.connect(osc.frequency);

      const opGain = ctx.createGain();
      opGain.gain.value = op.level * velocity;
      osc.connect(opGain);
      opGain.connect(preMix);

      osc.start(now);
      lfo.start(now);
      oscs.push(osc, lfo);
      nodes.push(lfoGain, opGain);
    });

    // ── Eigenspace network ──────────────────────────────────
    const eigenOut = ctx.createGain();
    const eigenNodes = buildEigenFilter(preMix, eigenOut);

    // ── Amplitude envelope ──────────────────────────────────
    const ampEnv = ctx.createGain();
    const atk = Math.max(0.001, s.env.attack);
    const dec = Math.max(0.001, s.env.decay);
    ampEnv.gain.setValueAtTime(0, now);
    ampEnv.gain.linearRampToValueAtTime(velocity, now + atk);
    ampEnv.gain.linearRampToValueAtTime(s.env.sustain * velocity, now + atk + dec);

    eigenOut.connect(ampEnv);
    ampEnv.connect(dest);

    activeVoices.set(midiNote, {
      oscs, nodes, preMix, eigenOut, ampEnv, eigenNodes, startTime: now, cleanupTimer: null,
    });
  }

  // ── Note Off ──────────────────────────────────────────────
  function noteOff(midiNote, immediate = false) {
    const voice = activeVoices.get(midiNote);
    if (!voice || !ctx) return;

    const now = ctx.currentTime;
    const rel = immediate ? 0.015 : Math.max(0.005, state.env.release);
    const g = voice.ampEnv.gain;

    try {
      if (typeof g.cancelAndHoldAtTime === 'function') g.cancelAndHoldAtTime(now);
      else { const v = g.value; g.cancelScheduledValues(now); g.setValueAtTime(v, now); }
    } catch (e) { try { g.cancelScheduledValues(now); } catch (e2) {} }
    g.linearRampToValueAtTime(0, now + rel);

    const stopTime = now + rel + 0.05;
    voice.oscs.forEach(o => { try { o.stop(stopTime); } catch(e) {} });

    // Delete by identity: a retrigger of the same note replaces the map
    // entry, and blindly deleting the key later would drop the NEW voice.
    if (voice.cleanupTimer) clearTimeout(voice.cleanupTimer);
    voice.cleanupTimer = setTimeout(() => {
      if (activeVoices.get(midiNote) === voice) activeVoices.delete(midiNote);
      disposeVoice(voice);
    }, (rel + 0.15) * 1000);
  }

  function disposeVoice(voice) {
    if (voice.cleanupTimer) { clearTimeout(voice.cleanupTimer); voice.cleanupTimer = null; }
    voice.oscs.forEach(safeDisconnect);
    (voice.nodes || []).forEach(safeDisconnect);
    // The eigenspace network is eight nodes per voice; leaving them
    // connected was the engine's largest leak.
    if (voice.eigenNodes) Object.values(voice.eigenNodes).forEach(safeDisconnect);
    safeDisconnect(voice.preMix);
    safeDisconnect(voice.eigenOut);
    safeDisconnect(voice.ampEnv);
  }

  // ── Panic ─────────────────────────────────────────────────
  function panic() {
    if (!ctx) { activeVoices.clear(); return; }
    const now = ctx.currentTime;
    activeVoices.forEach(voice => {
      try { voice.ampEnv.gain.cancelScheduledValues(now); voice.ampEnv.gain.setValueAtTime(0, now); } catch(e) {}
      voice.oscs.forEach(o => { try { o.stop(now); } catch(e) {} });
      disposeVoice(voice);
    });
    activeVoices.clear();
  }

  // ── Live param updates ────────────────────────────────────
  function setAlpha(v) {
    state.alpha = Math.max(0, Math.min(1, v));
  }

  function setChirpShape(v) { state.chirpShape = v; }
  function setOp(idx, param, value) {
    if (!state.ops[idx]) return;
    state.ops[idx][param] = value;
  }
  function setEigen(param, value) {
    state.eigen[param] = value;
    if (!ctx) return;
    // Apply to sounding voices so the eigenspace faders are audible on
    // held notes, not only on the next one.
    const key = { p1: 'g1', pm1: 'gm1', pi: 'gi', pmi: 'gmi' }[param];
    if (!key) return;
    const now = ctx.currentTime;
    activeVoices.forEach(v => {
      const g = v.eigenNodes && v.eigenNodes[key];
      if (g) g.gain.setTargetAtTime(value, now, 0.02);
    });
  }
  function setEnabled(v) { state.enabled = !!v; if (!v) panic(); }
  function setEnv(param, value) { state.env[param] = value; }

  function getState()       { return state; }
  function getActiveVoices(){ return activeVoices; }

  return {
    init, noteOn, noteOff, panic,
    setAlpha, setChirpShape, setOp, setEigen, setEnabled, setEnv,
    getState, getActiveVoices,
  };

})();

if (typeof module !== 'undefined' && module.exports) module.exports = SpectralFFT;
