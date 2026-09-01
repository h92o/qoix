/* ============================================================
   QOIX Synthesizer — FM Engine (DX7-style 4-Operator)
   ============================================================
   Terminology:
     Carrier  = operator whose output goes to audio output
     Modulator= operator whose output modulates a carrier's freq
     Ratio    = frequency multiplier relative to base note
     Index    = modulation depth (how much modulator affects carrier)

   Algorithms (4 operators: A=1, B=2, C=3, D=4):
     0: A(B(C(D)))         — serial chain
     1: A(B(C)+D)          — C+D mod B mod A
     2: A(B)+C(D)          — two parallel 2-op stacks
     3: A(B+C+D)           — A modulated by B,C,D parallel
     4: A+B(C(D))          — A carrier + B<-C<-D chain
     5: A+B+C(D)           — three carriers, D mods C
     6: A(B)+C+D           — A<-B, C and D are carriers
     7: A+B+C+D            — all carriers (additive)
   ============================================================ */

'use strict';

const FMEngine = (() => {

  // ── Default state ─────────────────────────────────────────
  const defaultState = {
    enabled: false,
    algorithm: 2,
    operators: [
      { ratio: 1,   level: 0.8, attack: 0.01, decay: 0.2, sustain: 0.7, release: 0.3, feedback: 0 },
      { ratio: 2,   level: 0.6, attack: 0.01, decay: 0.15,sustain: 0.5, release: 0.3, feedback: 0 },
      { ratio: 3,   level: 0.4, attack: 0.005,decay: 0.1, sustain: 0.3, release: 0.2, feedback: 0 },
      { ratio: 0.5, level: 0.5, attack: 0.01, decay: 0.25,sustain: 0.4, release: 0.4, feedback: 0 },
    ],
    globalFeedback: 0,
  };

  let state = JSON.parse(JSON.stringify(defaultState));

  // ── Algorithms: array of {carriers:[], mods:[{from,to}]} ──
  const ALGORITHMS = [
    // 0: D→C→B→A (serial)
    { carriers: [0], mods: [{from:3,to:2},{from:2,to:1},{from:1,to:0}] },
    // 1: D→C, D→B, B+C→A
    { carriers: [0], mods: [{from:3,to:2},{from:3,to:1},{from:2,to:0},{from:1,to:0}] },
    // 2: C→A output, D→B output (two 2-op stacks)
    { carriers: [0,1], mods: [{from:2,to:0},{from:3,to:1}] },
    // 3: B+C+D all mod A
    { carriers: [0], mods: [{from:1,to:0},{from:2,to:0},{from:3,to:0}] },
    // 4: A carrier, D→C→B and B→A (A+serial)
    { carriers: [0,3], mods: [{from:3,to:2},{from:2,to:1},{from:1,to:0}] },
    // 5: A+B carriers, D→C and C mods B
    { carriers: [0,1,2], mods: [{from:3,to:2},{from:2,to:1}] },
    // 6: A←B, C, D all carriers
    { carriers: [0,2,3], mods: [{from:1,to:0}] },
    // 7: all carriers (additive FM)
    { carriers: [0,1,2,3], mods: [] },
  ];

  // Algorithm display strings for UI
  const ALGORITHM_LABELS = [
    'D→C→B→A', 'D→C+B→A', 'C→A | D→B', 'B+C+D→A',
    'A + D→C→B', 'A+B + D→C', 'A←B | C | D', 'A+B+C+D',
  ];

  // ── Active FM voices ──────────────────────────────────────
  const fmVoices = new Map();

  // ── Context reference (set from outside) ─────────────────
  let _ctx = null;
  let _destination = null;
  let _indexMod = 0;   // mod-matrix FM Index offset, -1..+1

  function setContext(ctx, destination) {
    _ctx = ctx;
    _destination = destination;
  }

  function setIndexMod(v) { _indexMod = v || 0; }

  function safeDisconnect(node) { try { node.disconnect(); } catch (e) {} }

  // ── Note on ───────────────────────────────────────────────
  function noteOn(midiNote, velocity = 1, filter) {
    if (!_ctx || !_destination || !state.enabled) return;
    if (fmVoices.has(midiNote)) noteOff(midiNote, true);

    const baseFreq = (typeof Microtonal !== 'undefined' && Microtonal.getState().enabled)
      ? Microtonal.noteToFreq(midiNote)
      : 440 * Math.pow(2, (midiNote - 69) / 12);
    const now = _ctx.currentTime;
    const algo = ALGORITHMS[state.algorithm];
    const ops = state.operators;

    // Create oscillators and gain nodes for each operator
    const oscNodes = [];
    const envGains = [];
    const fmGains  = [];  // gain for FM signal (before adding to carrier freq)

    for (let i = 0; i < 4; i++) {
      const op = ops[i];
      const osc = _ctx.createOscillator();
      osc.type = 'sine';
      osc.frequency.value = baseFreq * op.ratio;

      // Amplitude envelope. Zero-length ramps are dropped by some
      // engines, so floor the segment times.
      const atk = Math.max(0.001, op.attack);
      const dec = Math.max(0.001, op.decay);
      const envGain = _ctx.createGain();
      envGain.gain.setValueAtTime(0, now);
      envGain.gain.linearRampToValueAtTime(op.level * velocity, now + atk);
      envGain.gain.linearRampToValueAtTime(
        op.level * op.sustain * velocity,
        now + atk + dec
      );

      // FM output gain. envGain already carries op.level and velocity,
      // so this stage must NOT apply them again — doing so made the
      // modulation index scale with the square of the level, which is
      // why small level changes swung the timbre so violently.
      const fmGain = _ctx.createGain();
      fmGain.gain.value = baseFreq * op.ratio * Math.max(0, 1 + _indexMod);

      osc.connect(envGain);
      envGain.connect(fmGain);

      osc.start(now);
      oscNodes.push(osc);
      envGains.push(envGain);
      fmGains.push(fmGain);
    }

    // Wire modulations according to algorithm
    // Modulator output → modulate carrier frequency param
    algo.mods.forEach(({from, to}) => {
      fmGains[from].connect(oscNodes[to].frequency);
    });

    // Carriers → filter or destination
    const mixGain = _ctx.createGain();
    mixGain.gain.value = 1 / Math.max(algo.carriers.length, 1);

    algo.carriers.forEach(i => {
      envGains[i].connect(mixGain);
    });

    // Connect to filter if provided, else direct to destination
    const dest = filter || _destination;
    mixGain.connect(dest);

    fmVoices.set(midiNote, { oscNodes, envGains, fmGains, mixGain, startTime: now, cleanupTimer: null });
  }

  // ── Note off ──────────────────────────────────────────────
  function noteOff(midiNote, immediate = false) {
    const voice = fmVoices.get(midiNote);
    if (!voice || !_ctx) return;

    const now = _ctx.currentTime;
    let maxRel = 0.02;

    voice.oscNodes.forEach((osc, i) => {
      const op = state.operators[i];
      const rel = immediate ? 0.02 : Math.max(0.005, op.release);
      if (rel > maxRel) maxRel = rel;
      const g = voice.envGains[i].gain;
      try {
        if (typeof g.cancelAndHoldAtTime === 'function') g.cancelAndHoldAtTime(now);
        else { const v = g.value; g.cancelScheduledValues(now); g.setValueAtTime(v, now); }
      } catch (e) { try { g.cancelScheduledValues(now); } catch (e2) {} }
      g.linearRampToValueAtTime(0, now + rel);
      try { osc.stop(now + rel + 0.05); } catch(e) {}
    });

    // Keep the voice tracked until the tail is done, then tear the nodes
    // down. Deleting the entry immediately (as this used to) orphaned
    // every node in the voice and leaked them for the life of the page.
    fmVoices.delete(midiNote);
    if (voice.cleanupTimer) clearTimeout(voice.cleanupTimer);
    voice.cleanupTimer = setTimeout(() => disposeVoice(voice), (maxRel + 0.15) * 1000);
  }

  function disposeVoice(voice) {
    if (voice.cleanupTimer) { clearTimeout(voice.cleanupTimer); voice.cleanupTimer = null; }
    voice.oscNodes.forEach(safeDisconnect);
    voice.envGains.forEach(safeDisconnect);
    voice.fmGains.forEach(safeDisconnect);
    safeDisconnect(voice.mixGain);
  }

  // ── Panic ─────────────────────────────────────────────────
  function panic() {
    if (!_ctx) { fmVoices.clear(); return; }
    const now = _ctx.currentTime;
    fmVoices.forEach(voice => {
      voice.envGains.forEach(g => {
        try { g.gain.cancelScheduledValues(now); g.gain.setValueAtTime(0, now); } catch (e) {}
      });
      voice.oscNodes.forEach(o => { try { o.stop(now); } catch (e) {} });
      disposeVoice(voice);
    });
    fmVoices.clear();
  }

  // ── State setters ─────────────────────────────────────────
  function setEnabled(v) { state.enabled = !!v; if (!v) panic(); }
  function setAlgorithm(v) {
    const i = parseInt(v, 10);
    if (i >= 0 && i < ALGORITHMS.length) state.algorithm = i;
  }
  function setOperator(opIdx, param, value) {
    if (!state.operators[opIdx]) return;
    state.operators[opIdx][param] = parseFloat(value);
  }

  function getState() { return state; }
  function loadState(s) { state = JSON.parse(JSON.stringify(s)); }
  function getAlgorithmLabels() { return ALGORITHM_LABELS; }
  function getAlgorithms() { return ALGORITHMS; }

  return {
    setContext, noteOn, noteOff, panic,
    setEnabled, setAlgorithm, setOperator, setIndexMod,
    getState, loadState,
    getAlgorithmLabels, getAlgorithms,
    get fmVoices() { return fmVoices; },
  };

})();

if (typeof module !== 'undefined' && module.exports) module.exports = FMEngine;
