/* ============================================================
   QOIX Synthesizer — Core Audio Engine
   ============================================================
   Signal flow

     voices ─┐
     FM/WT/Spectral engines ─┴─► voiceBus
       voiceBus ─► distortion ─┐
       voiceBus ─► dist bypass ┴─► postDist
       postDist ─► chorus (stereo, 2 taps) ─► postChorus
       postChorus ─► delay send ─► postDelay
       postDelay ─► reverb send ─► postReverb
       postReverb ─► limiter ─► safety clip ─► analyser ─► master ─► out

   Effects are crossfaded/summed with persistent gain nodes so
   every parameter is live-editable without rebuilding the graph.
   ============================================================ */

'use strict';

const Synth = (() => {

  // ── Context ───────────────────────────────────────────────
  let ctx = null;
  let masterGain = null;
  let analyser = null;
  let limiter = null;
  let safetyClip = null;

  // ── FX chain nodes (persistent) ───────────────────────────
  let voiceBus = null;
  let distortionNode = null, distortionWet = null, distortionBypass = null;
  let chorusDelayL = null, chorusDelayR = null;
  let chorusLFO = null, chorusLFOGainL = null, chorusLFOGainR = null;
  let chorusWet = null, chorusDry = null;
  let delayNode = null, delayFeedback = null, delayWet = null, delayDry = null;
  let reverbNode = null, reverbWet = null, reverbDry = null;

  // ── LFO ───────────────────────────────────────────────────
  let lfoOsc = null;
  let lfoGain = null;

  // ── Mod matrix buses (ConstantSourceNodes, persistent) ────
  // Each is summed into the AudioParams of every live voice.
  let modBusPitch     = null;   // → all osc detune  (cents)
  let modBusFilterCut = null;   // → master filter freq (Hz)
  let modBusOsc1Det   = null;   // → osc1 detune (cents)
  let modBusOsc2Det   = null;
  let modBusOsc3Det   = null;
  let modBusAmp       = null;   // → per-voice mod gain (offset around 1.0)
  let modBusPan       = null;   // → per-voice panner (-1..+1)

  // Mod matrix JS state
  let jsLFOPhase    = 0;
  let _lastNoteVal  = 0;   // 0..1
  let _lastVelVal   = 0;   // 0..1
  let _lastFilterRes = null;

  // ── Active voices ─────────────────────────────────────────
  // Keyed by a monotonically increasing voice id so that a voice
  // still in its release tail can never be clobbered by a retrigger
  // of the same MIDI note.
  const activeVoices = new Map();  // voiceId -> voice
  const heldVoices   = new Map();  // midiNote -> voiceId (sounding, key still down)
  let _nextVoiceId = 1;

  // ── Quality / performance settings ───────────────────────
  const quality = {
    maxVoices:    64,      // polyphony limit (voice stealing kicks in above this)
    fftSize:      4096,    // analyser resolution (power of 2, max 32768)
    reverbDense:  true,    // denser early-reflection IR (more CPU, better quality)
    distCurve:    1024,    // distortion waveshaper table resolution
    noiseSeconds: 4,       // seconds of noise buffer (longer = less audible loop)
    limiter:      true,    // brick-wall limiter on the master bus
  };

  // ── Default patch ─────────────────────────────────────────
  // loadPreset() resets to this before merging, so patches never
  // inherit stray settings from whatever was loaded before them.
  const DEFAULT_STATE = {
    masterVolume: 0.7,
    osc1: { enabled: true,  wave: 'sawtooth', octave: 0,  detune: 0,  level: 0.8, voices: 1, unisonSpread: 20,
            filter: { type: 'lowpass', cutoff: 18000, resonance: 0.7, lfoDepth: 0, envAmt: 0 },
            fmFrom: 'none', fmIndex: 0.5, mixMode: 'add' },
    osc2: { enabled: false, wave: 'square',   octave: 0,  detune: 7,  level: 0.5, voices: 1, unisonSpread: 20,
            filter: { type: 'lowpass', cutoff: 18000, resonance: 0.7, lfoDepth: 0, envAmt: 0 },
            fmFrom: 'none', fmIndex: 0.5, mixMode: 'add' },
    osc3: { enabled: false, wave: 'triangle', octave: -1, detune: -7, level: 0.5, voices: 1, unisonSpread: 20,
            filter: { type: 'lowpass', cutoff: 18000, resonance: 0.7, lfoDepth: 0, envAmt: 0 },
            fmFrom: 'none', fmIndex: 0.5, mixMode: 'add' },
    noise: { enabled: false, type: 'white', level: 0.2 },
    env:  { attack: 0.01, decay: 0.1, sustain: 0.7, release: 0.3 },
    fenv: { amount: 2000, attack: 0.01, decay: 0.2, sustain: 0.3, release: 0.2 },
    filter: { type: 'lowpass', cutoff: 8000, resonance: 1 },
    lfo:  { enabled: false, wave: 'sine', rate: 4, depth: 0.3, target: 'pitch' },
    dist: { enabled: false, drive: 80 },
    chorus: { enabled: false, rate: 1.5, depth: 0.003, mix: 0.5 },
    delay: { enabled: false, time: 0.375, feedback: 0.4, mix: 0.3 },
    reverb: { enabled: false, size: 2, damp: 0.5, mix: 0.2 },
  };

  const state = clone(DEFAULT_STATE);

  // ── Init ──────────────────────────────────────────────────
  function init() {
    if (ctx) return ctx;

    const Ctor = window.AudioContext || window.webkitAudioContext;
    ctx = new Ctor({ latencyHint: 'interactive' });

    masterGain = ctx.createGain();
    masterGain.gain.value = state.masterVolume;

    analyser = ctx.createAnalyser();
    analyser.fftSize = quality.fftSize;
    analyser.smoothingTimeConstant = 0.82;

    // Brick-wall limiter, then a tanh safety clip. Between them the
    // master can never hand the sound card a sample outside [-1, 1],
    // which is what used to make dense chords crackle.
    limiter = ctx.createDynamicsCompressor();
    limiter.threshold.value = -3;
    limiter.knee.value      = 0;
    limiter.ratio.value     = 20;
    limiter.attack.value    = 0.002;
    limiter.release.value   = 0.18;

    safetyClip = ctx.createWaveShaper();
    safetyClip.curve = makeSoftClipCurve(2048);
    safetyClip.oversample = '2x';

    buildEffectChain();

    limiter.connect(safetyClip);
    safetyClip.connect(analyser);
    analyser.connect(masterGain);
    masterGain.connect(ctx.destination);

    modBusPitch     = makeModBus(0);
    modBusFilterCut = makeModBus(0);
    modBusOsc1Det   = makeModBus(0);
    modBusOsc2Det   = makeModBus(0);
    modBusOsc3Det   = makeModBus(0);
    modBusAmp       = makeModBus(0);
    modBusPan       = makeModBus(0);

    if (state.lfo.enabled) startLFO();

    console.log(`[QOIX] Audio engine initialized — ${ctx.sampleRate}Hz, ${quality.maxVoices} voices, FFT ${quality.fftSize}`);
    return ctx;
  }

  function makeModBus(value) {
    const cs = ctx.createConstantSource();
    cs.offset.value = value;
    cs.start();
    return cs;
  }

  function ensureContext() {
    if (!ctx) init();
    if (ctx.state === 'suspended') ctx.resume().catch(() => {});
    return ctx;
  }

  // ── Quality setters (call before or after init) ───────────
  function setQuality(param, value) {
    quality[param] = value;
    if (param === 'fftSize' && analyser) analyser.fftSize = value;
    if (param === 'distCurve' && distortionNode) {
      distortionNode.curve = makeDistortionCurve(state.dist.drive);
    }
    if (param === 'reverbDense' && reverbNode) {
      reverbNode.buffer = buildImpulse(state.reverb.size, state.reverb.damp * 5 + 1);
    }
    if (param === 'limiter' && limiter) {
      // A ratio of 1 makes the compressor transparent, so the toggle
      // does not have to rewire the graph mid-playback.
      limiter.ratio.value     = value ? 20 : 1;
      limiter.threshold.value = value ? -3 : 0;
    }
  }

  function getQuality() { return quality; }

  // ── Curves ────────────────────────────────────────────────
  function makeDistortionCurve(amount) {
    const n = Math.max(64, quality.distCurve);
    const curve = new Float32Array(n);
    const k = Math.max(0, amount);
    for (let i = 0; i < n; i++) {
      const x = (i * 2) / (n - 1) - 1;
      curve[i] = ((Math.PI + k) * x) / (Math.PI + k * Math.abs(x));
    }
    return curve;
  }

  function makeSoftClipCurve(n) {
    const curve = new Float32Array(n);
    for (let i = 0; i < n; i++) {
      // Input range is widened to ±2 so the curve only bites on overshoot.
      const x = ((i * 2) / (n - 1) - 1) * 2;
      curve[i] = Math.tanh(x);
    }
    return curve;
  }

  // ── Reverb IR ─────────────────────────────────────────────
  function buildImpulse(duration, decay) {
    const rate = ctx.sampleRate;
    const len = Math.max(1, Math.floor(rate * clamp(duration, 0.05, 10)));
    const impulse = ctx.createBuffer(2, len, rate);

    for (let ch = 0; ch < 2; ch++) {
      const data = impulse.getChannelData(ch);
      if (quality.reverbDense) {
        const earlyEnd = Math.min(Math.floor(rate * 0.08), len); // 80ms early reflections
        for (let i = 0; i < len; i++) {
          const env = Math.pow(1 - i / len, decay);
          const early = i < earlyEnd ? (Math.random() * 2 - 1) * 1.5 : 0;
          const late  = (Math.random() * 2 - 1);
          data[i] = (early + late) * env * 0.5;
        }
      } else {
        for (let i = 0; i < len; i++) {
          data[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, decay);
        }
      }
    }
    return impulse;
  }

  // ── Build FX chain ────────────────────────────────────────
  function buildEffectChain() {
    const s = state;

    // Every voice and every auxiliary engine feeds this node.
    voiceBus = ctx.createGain();

    // ── Distortion (parallel wet/bypass so the toggle is click-free)
    distortionNode = ctx.createWaveShaper();
    distortionNode.curve = makeDistortionCurve(s.dist.drive);
    distortionNode.oversample = '4x';
    distortionWet    = ctx.createGain();
    distortionBypass = ctx.createGain();
    const postDist   = ctx.createGain();

    voiceBus.connect(distortionNode);
    voiceBus.connect(distortionBypass);
    distortionNode.connect(distortionWet);
    distortionWet.connect(postDist);
    distortionBypass.connect(postDist);

    // ── Chorus: two delay taps with quadrature LFOs, hard-panned.
    // A single mono tap summed with dry only comb-filters; this is a
    // real chorus.
    chorusDelayL = ctx.createDelay(0.2);
    chorusDelayR = ctx.createDelay(0.2);
    chorusDelayL.delayTime.value = 0.018;
    chorusDelayR.delayTime.value = 0.024;

    chorusLFO = ctx.createOscillator();
    chorusLFO.type = 'sine';
    chorusLFO.frequency.value = s.chorus.rate;
    chorusLFOGainL = ctx.createGain();
    chorusLFOGainR = ctx.createGain();
    chorusLFOGainL.gain.value =  s.chorus.depth;
    chorusLFOGainR.gain.value = -s.chorus.depth;  // inverted = 180° out of phase
    chorusLFO.connect(chorusLFOGainL);
    chorusLFO.connect(chorusLFOGainR);
    chorusLFOGainL.connect(chorusDelayL.delayTime);
    chorusLFOGainR.connect(chorusDelayR.delayTime);
    chorusLFO.start();

    const panL = ctx.createStereoPanner(); panL.pan.value = -0.7;
    const panR = ctx.createStereoPanner(); panR.pan.value =  0.7;

    chorusWet = ctx.createGain();
    chorusDry = ctx.createGain();
    const postChorus = ctx.createGain();

    postDist.connect(chorusDry);
    postDist.connect(chorusDelayL);
    postDist.connect(chorusDelayR);
    chorusDelayL.connect(panL); panL.connect(chorusWet);
    chorusDelayR.connect(panR); panR.connect(chorusWet);
    chorusDry.connect(postChorus);
    chorusWet.connect(postChorus);

    // ── Delay (send: dry stays at unity)
    delayNode = ctx.createDelay(2);
    delayNode.delayTime.value = clamp(s.delay.time, 0, 2);
    delayFeedback = ctx.createGain();
    // Feedback >= 1 self-oscillates into a runaway; cap it.
    delayFeedback.gain.value = clamp(s.delay.feedback, 0, 0.95);
    delayWet = ctx.createGain();
    delayDry = ctx.createGain();
    delayDry.gain.value = 1;
    const postDelay = ctx.createGain();

    postChorus.connect(delayDry);
    postChorus.connect(delayNode);
    delayNode.connect(delayFeedback);
    delayFeedback.connect(delayNode);
    delayNode.connect(delayWet);
    delayDry.connect(postDelay);
    delayWet.connect(postDelay);

    // ── Reverb (send)
    reverbNode = ctx.createConvolver();
    reverbNode.buffer = buildImpulse(s.reverb.size, s.reverb.damp * 5 + 1);
    reverbWet = ctx.createGain();
    reverbDry = ctx.createGain();
    reverbDry.gain.value = 1;
    const postReverb = ctx.createGain();

    postDelay.connect(reverbDry);
    postDelay.connect(reverbNode);
    reverbNode.connect(reverbWet);
    reverbDry.connect(postReverb);
    reverbWet.connect(postReverb);

    postReverb.connect(limiter);

    // Apply the enable/mix state to every wet/dry pair.
    _applyDistMix();
    _applyChorusMix();
    _applyDelayMix();
    _applyReverbMix();

    Synth._voiceDestination = voiceBus;
  }

  // ── Noise buffer ──────────────────────────────────────────
  const _noiseBuffers = {};
  function getNoiseBuffer(type) {
    if (_noiseBuffers[type]) return _noiseBuffers[type];
    const len = Math.floor(ctx.sampleRate * quality.noiseSeconds);
    const buf = ctx.createBuffer(1, len, ctx.sampleRate);
    const data = buf.getChannelData(0);
    if (type === 'white') {
      for (let i = 0; i < len; i++) data[i] = Math.random() * 2 - 1;
    } else {
      let b0 = 0, b1 = 0, b2 = 0, b3 = 0, b4 = 0, b5 = 0;
      for (let i = 0; i < len; i++) {
        const wh = Math.random() * 2 - 1;
        b0 = 0.99886 * b0 + wh * 0.0555179;
        b1 = 0.99332 * b1 + wh * 0.0750759;
        b2 = 0.96900 * b2 + wh * 0.1538520;
        b3 = 0.86650 * b3 + wh * 0.3104856;
        b4 = 0.55000 * b4 + wh * 0.5329522;
        b5 = -0.7616 * b5 - wh * 0.0168980;
        data[i] = (b0 + b1 + b2 + b3 + b4 + b5 + wh * 0.5362) * 0.11;
      }
    }
    _noiseBuffers[type] = buf;
    return buf;
  }

  // ── Voice stealing ────────────────────────────────────────
  // Prefer voices already in their release tail; only then take the
  // oldest held voice. Stealing a releasing voice is inaudible.
  function stealVoiceIfNeeded() {
    // A loop, not a single steal: lowering maxVoices while notes are
    // sounding leaves the count above the new cap by more than one.
    let guard = 0;
    while (activeVoices.size >= quality.maxVoices && guard++ < 256) {
      let victimId = null, victimTime = Infinity, victimReleasing = false;
      activeVoices.forEach((voice, id) => {
        const releasing = voice.releasing;
        // A releasing voice always beats a held one.
        if (victimReleasing && !releasing) return;
        if (releasing && !victimReleasing) {
          victimId = id; victimTime = voice.startTime; victimReleasing = true;
          return;
        }
        if (voice.startTime < victimTime) { victimId = id; victimTime = voice.startTime; }
      });
      if (victimId === null) break;
      killVoice(victimId);
    }
  }

  // ── Note on ───────────────────────────────────────────────
  function noteOn(midiNote, velocity = 1) {
    ensureContext();
    velocity = clamp(velocity, 0.001, 1);

    // Retrigger: retire the currently-held voice for this note first.
    if (heldVoices.has(midiNote)) releaseVoice(heldVoices.get(midiNote), true);
    stealVoiceIfNeeded();

    _lastNoteVal = midiNote / 127;
    _lastVelVal  = velocity;

    const freq = midiToFreq(midiNote);
    const now  = ctx.currentTime;
    const s    = state;

    // Amp envelope. Ramps need a strictly increasing time or Chrome
    // silently drops the segment, hence the epsilon floors.
    const atk = Math.max(0.001, s.env.attack);
    const dec = Math.max(0.001, s.env.decay);
    const ampEnv = ctx.createGain();
    ampEnv.gain.setValueAtTime(0, now);
    ampEnv.gain.linearRampToValueAtTime(velocity, now + atk);
    ampEnv.gain.linearRampToValueAtTime(clamp(s.env.sustain, 0, 1) * velocity, now + atk + dec);

    const oscs = [];
    const oscFilters = {};
    const oscMixer = ctx.createGain();
    // Every AudioParam connection made for this voice, so note-off can
    // tear them all down instead of leaking into the shared LFO/mod buses.
    const paramConns = [];
    const conn = (node, param) => { node.connect(param); paramConns.push({ node, param }); };

    function makeOscFilter(fState, targetNode) {
      const f = ctx.createBiquadFilter();
      f.type = fState.type;
      f.frequency.setValueAtTime(clamp(fState.cutoff, 20, 20000), now);
      f.Q.value = clamp(fState.resonance, 0.0001, 30);

      if (fState.envAmt !== 0) {
        const base = clamp(fState.cutoff, 20, 20000);
        const amt  = fState.envAmt;
        f.frequency.setValueAtTime(base, now);
        f.frequency.linearRampToValueAtTime(
          clamp(base + amt, 20, 20000), now + Math.max(0.001, s.fenv.attack));
        f.frequency.linearRampToValueAtTime(
          clamp(base + amt * s.fenv.sustain, 20, 20000),
          now + Math.max(0.001, s.fenv.attack) + Math.max(0.001, s.fenv.decay));
      }

      if (s.lfo.enabled && lfoOsc && fState.lfoDepth > 0) {
        const lfoFiltGain = ctx.createGain();
        lfoFiltGain.gain.value = fState.lfoDepth * s.lfo.depth * 5000;
        lfoOsc.connect(lfoFiltGain);
        lfoFiltGain.connect(f.frequency);
        paramConns.push({ node: lfoOsc,      param: lfoFiltGain });
        paramConns.push({ node: lfoFiltGain, param: f.frequency });
      }

      f.connect(targetNode);
      return f;
    }

    const oscGroups = { osc1: [], osc2: [], osc3: [] };
    const rawSums   = {};

    function buildUnisonOsc(oscState, group) {
      const rawSum = ctx.createGain();
      const nVoices = clamp(Math.round(oscState.voices || 1), 1, 16);
      const spread  = oscState.unisonSpread || 0;
      // Keep unison stacks at roughly constant loudness rather than
      // letting an 8-voice stack be 8x louder than a 1-voice one.
      const norm = 1 / Math.sqrt(nVoices);
      for (let v = 0; v < nVoices; v++) {
        const osc  = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.type = oscState.wave;
        osc.frequency.value = clamp(freq * Math.pow(2, oscState.octave), 0.01, ctx.sampleRate / 2);
        const spreadOffset = nVoices > 1 ? ((v / (nVoices - 1)) - 0.5) * 2 * spread : 0;
        osc.detune.value = oscState.detune + spreadOffset;
        gain.gain.value = oscState.level * norm;
        osc.connect(gain);
        gain.connect(rawSum);
        osc.start(now);
        oscs.push(osc);
        group.push(osc);
      }
      return rawSum;
    }

    if (s.osc1.enabled) rawSums.osc1 = buildUnisonOsc(s.osc1, oscGroups.osc1);
    if (s.osc2.enabled) rawSums.osc2 = buildUnisonOsc(s.osc2, oscGroups.osc2);
    if (s.osc3.enabled) rawSums.osc3 = buildUnisonOsc(s.osc3, oscGroups.osc3);

    // ── OSC-to-OSC FM routing ────────────────────────────────
    ['osc1', 'osc2', 'osc3'].forEach(tgtKey => {
      const tgtState = s[tgtKey];
      const srcKey   = tgtState.fmFrom;
      if (!srcKey || srcKey === 'none' || srcKey === tgtKey) return;
      if (!rawSums[srcKey] || !oscGroups[tgtKey].length) return;
      const fmGain = ctx.createGain();
      const baseFreq = freq * Math.pow(2, tgtState.octave);
      fmGain.gain.value = (tgtState.fmIndex || 0) * baseFreq;
      rawSums[srcKey].connect(fmGain);
      oscGroups[tgtKey].forEach(o => fmGain.connect(o.frequency));
    });

    // ── Mix mode ─────────────────────────────────────────────
    function routeOscToFilter(rawSum, oscState, filterNode) {
      const mode = oscState.mixMode || 'add';
      const carrier = rawSums.osc1;
      if (mode === 'sub') {
        const negGain = ctx.createGain();
        negGain.gain.value = -1;
        rawSum.connect(negGain);
        negGain.connect(filterNode);
      } else if (mode === 'ring' && carrier && rawSum !== carrier) {
        const ringGain = ctx.createGain();
        ringGain.gain.value = 0;
        carrier.connect(ringGain.gain);
        rawSum.connect(ringGain);
        ringGain.connect(filterNode);
      } else if (mode === 'xor' && carrier && rawSum !== carrier) {
        const negA = ctx.createGain();
        negA.gain.value = -1;
        carrier.connect(negA);
        const diff = ctx.createGain();
        rawSum.connect(diff);
        negA.connect(diff);
        const absShaper = ctx.createWaveShaper();
        absShaper.curve = ABS_CURVE;
        diff.connect(absShaper);
        absShaper.connect(filterNode);
      } else {
        rawSum.connect(filterNode);
      }
    }

    if (s.osc1.enabled) {
      oscFilters.osc1 = makeOscFilter(s.osc1.filter, oscMixer);
      rawSums.osc1.connect(oscFilters.osc1);
    }
    if (s.osc2.enabled) {
      oscFilters.osc2 = makeOscFilter(s.osc2.filter, oscMixer);
      routeOscToFilter(rawSums.osc2, s.osc2, oscFilters.osc2);
    }
    if (s.osc3.enabled) {
      oscFilters.osc3 = makeOscFilter(s.osc3.filter, oscMixer);
      routeOscToFilter(rawSums.osc3, s.osc3, oscFilters.osc3);
    }

    if (s.noise.enabled) {
      const src = ctx.createBufferSource();
      src.buffer = getNoiseBuffer(s.noise.type);
      src.loop = true;
      // Start at a random offset so every note does not replay the
      // identical noise burst.
      const off = Math.random() * src.buffer.duration;
      const gain = ctx.createGain();
      gain.gain.value = s.noise.level;
      src.connect(gain);
      gain.connect(oscMixer);
      src.start(now, off);
      oscs.push(src);
    }

    // ── Master filter ────────────────────────────────────────
    const filter = ctx.createBiquadFilter();
    filter.type = s.filter.type;
    filter.frequency.setValueAtTime(clamp(s.filter.cutoff, 20, 20000), now);
    filter.Q.value = clamp(s.filter.resonance, 0.0001, 30);

    if (s.fenv.amount !== 0) {
      const baseCutoff = clamp(s.filter.cutoff, 20, 20000);
      filter.frequency.setValueAtTime(baseCutoff, now);
      filter.frequency.linearRampToValueAtTime(
        clamp(baseCutoff + s.fenv.amount, 20, 20000), now + Math.max(0.001, s.fenv.attack));
      filter.frequency.linearRampToValueAtTime(
        clamp(baseCutoff + s.fenv.amount * s.fenv.sustain, 20, 20000),
        now + Math.max(0.001, s.fenv.attack) + Math.max(0.001, s.fenv.decay));
    }

    // Mod-matrix amp/pan stage, downstream of the envelope so it does
    // not fight the envelope automation.
    const modAmp = ctx.createGain();
    modAmp.gain.value = 1;
    const panner = ctx.createStereoPanner();

    // ── LFO routing ──────────────────────────────────────────
    if (s.lfo.enabled && lfoOsc && lfoGain) {
      const t = s.lfo.target;
      if (t === 'pitch') {
        oscs.forEach(o => { if (o.detune) conn(lfoGain, o.detune); });
      } else if (t === 'filter') {
        conn(lfoGain, filter.frequency);
      } else if (t === 'amplitude') {
        conn(lfoGain, modAmp.gain);
      } else if (t === 'pan') {
        conn(lfoGain, panner.pan);
      }
    }

    oscMixer.connect(filter);
    filter.connect(ampEnv);
    ampEnv.connect(modAmp);
    modAmp.connect(panner);
    panner.connect(voiceBus);

    // ── Mod matrix buses ─────────────────────────────────────
    const allOscNodes = [...oscGroups.osc1, ...oscGroups.osc2, ...oscGroups.osc3];
    allOscNodes.forEach(o => conn(modBusPitch, o.detune));
    oscGroups.osc1.forEach(o => conn(modBusOsc1Det, o.detune));
    oscGroups.osc2.forEach(o => conn(modBusOsc2Det, o.detune));
    oscGroups.osc3.forEach(o => conn(modBusOsc3Det, o.detune));
    conn(modBusFilterCut, filter.frequency);
    conn(modBusAmp, modAmp.gain);
    conn(modBusPan, panner.pan);

    const voiceId = _nextVoiceId++;
    activeVoices.set(voiceId, {
      id: voiceId, midiNote, velocity,
      oscs, oscMixer, oscGroups, ampEnv, modAmp, panner, filter, oscFilters,
      paramConns, startTime: now, releasing: false,
      cleanupTimer: null,
    });
    heldVoices.set(midiNote, voiceId);

    notifyUI();
  }

  // ── Note off ──────────────────────────────────────────────
  function noteOff(midiNote, immediate = false) {
    const voiceId = heldVoices.get(midiNote);
    if (voiceId === undefined) return;
    releaseVoice(voiceId, immediate);
  }

  function releaseVoice(voiceId, immediate = false) {
    const voice = activeVoices.get(voiceId);
    if (!voice || voice.releasing) return;

    voice.releasing = true;
    if (heldVoices.get(voice.midiNote) === voiceId) heldVoices.delete(voice.midiNote);

    const now  = ctx.currentTime;
    const rel  = immediate ? 0.015 : Math.max(0.005, state.env.release);
    const fRel = immediate ? 0.015 : Math.max(0.005, state.fenv.release);

    // Disconnect every param feed first so the shared LFO / mod buses
    // stop driving a voice that is on its way out.
    disconnectParams(voice);

    holdAndRamp(voice.ampEnv.gain, 0, now, rel);

    if (state.fenv.amount !== 0) {
      holdAndRamp(voice.filter.frequency, clamp(state.filter.cutoff, 20, 20000), now, fRel);
    }

    ['osc1', 'osc2', 'osc3'].forEach(key => {
      const f = voice.oscFilters[key];
      if (!f || !state[key] || state[key].filter.envAmt === 0) return;
      holdAndRamp(f.frequency, clamp(state[key].filter.cutoff, 20, 20000), now, fRel);
    });

    const stopTime = now + rel + 0.05;
    voice.oscs.forEach(o => { try { o.stop(stopTime); } catch (e) { /* already stopped */ } });

    voice.cleanupTimer = setTimeout(() => disposeVoice(voiceId), (rel + 0.15) * 1000);
    notifyUI();
  }

  // Hard-stop a voice right now (voice stealing, panic).
  // The voice leaves activeVoices immediately so its polyphony slot is
  // free for the note that displaced it; its nodes fade out over the
  // next few milliseconds and are torn down on a timer. Keeping stolen
  // voices in the registry until their fade finished meant a fast run
  // of notes could blow straight past the polyphony cap.
  function killVoice(voiceId) {
    const voice = activeVoices.get(voiceId);
    if (!voice) return;
    const now = ctx.currentTime;
    voice.releasing = true;
    activeVoices.delete(voiceId);
    if (heldVoices.get(voice.midiNote) === voiceId) heldVoices.delete(voice.midiNote);
    disconnectParams(voice);
    // A 6ms fade instead of an instant cut — an abrupt stop clicks.
    holdAndRamp(voice.ampEnv.gain, 0, now, 0.006);
    voice.oscs.forEach(o => { try { o.stop(now + 0.02); } catch (e) {} });
    if (voice.cleanupTimer) clearTimeout(voice.cleanupTimer);
    voice.cleanupTimer = setTimeout(() => disposeDetached(voice), 60);
    notifyUI();
  }

  function disposeVoice(voiceId) {
    const voice = activeVoices.get(voiceId);
    if (!voice) return;
    activeVoices.delete(voiceId);
    if (heldVoices.get(voice.midiNote) === voiceId) heldVoices.delete(voice.midiNote);
    disposeDetached(voice);
    notifyUI();
  }

  // Tear down a voice that is no longer in the registry.
  function disposeDetached(voice) {
    if (voice.cleanupTimer) { clearTimeout(voice.cleanupTimer); voice.cleanupTimer = null; }
    disconnectParams(voice);
    safeDisconnect(voice.oscMixer);
    Object.values(voice.oscFilters).forEach(safeDisconnect);
    safeDisconnect(voice.filter);
    safeDisconnect(voice.ampEnv);
    safeDisconnect(voice.modAmp);
    safeDisconnect(voice.panner);
    voice.oscs.forEach(safeDisconnect);
  }

  function disconnectParams(voice) {
    if (!voice.paramConns) return;
    voice.paramConns.forEach(({ node, param }) => {
      try { node.disconnect(param); } catch (e) { /* already gone */ }
    });
    voice.paramConns.length = 0;
  }

  function safeDisconnect(node) {
    try { node.disconnect(); } catch (e) { /* already gone */ }
  }

  // Cancel pending automation, pin the param at its current value, then
  // ramp. cancelAndHoldAtTime does this correctly mid-ramp; the manual
  // fallback is for engines that lack it.
  function holdAndRamp(param, target, now, seconds) {
    try {
      if (typeof param.cancelAndHoldAtTime === 'function') {
        param.cancelAndHoldAtTime(now);
      } else {
        const v = param.value;
        param.cancelScheduledValues(now);
        param.setValueAtTime(v, now);
      }
    } catch (e) {
      try { param.cancelScheduledValues(now); } catch (e2) {}
    }
    param.linearRampToValueAtTime(target, now + Math.max(0.001, seconds));
  }

  // ── Panic ─────────────────────────────────────────────────
  function panic() {
    if (!ctx) return;
    const now = ctx.currentTime;

    masterGain.gain.cancelScheduledValues(now);
    masterGain.gain.setValueAtTime(0, now);

    activeVoices.forEach((voice, id) => {
      if (voice.cleanupTimer) { clearTimeout(voice.cleanupTimer); voice.cleanupTimer = null; }
      disconnectParams(voice);
      voice.oscs.forEach(o => { try { o.stop(now); } catch (e) {} });
      voice.oscs.forEach(safeDisconnect);
      safeDisconnect(voice.oscMixer);
      Object.values(voice.oscFilters).forEach(safeDisconnect);
      safeDisconnect(voice.filter);
      try { voice.ampEnv.gain.cancelScheduledValues(now); } catch (e) {}
      safeDisconnect(voice.ampEnv);
      safeDisconnect(voice.modAmp);
      safeDisconnect(voice.panner);
    });
    activeVoices.clear();
    heldVoices.clear();

    // Also flush the delay line, otherwise panic leaves echoes ringing.
    if (delayFeedback) {
      const fb = delayFeedback.gain.value;
      delayFeedback.gain.setValueAtTime(0, now);
      delayFeedback.gain.setValueAtTime(fb, now + 0.25);
    }

    masterGain.gain.linearRampToValueAtTime(state.masterVolume, now + 0.05);
    notifyUI();
  }

  // ── LFO management ───────────────────────────────────────
  function startLFO() {
    if (!ctx) return;
    stopLFO();
    lfoOsc  = ctx.createOscillator();
    lfoGain = ctx.createGain();
    lfoOsc.type = state.lfo.wave;
    lfoOsc.frequency.value = clamp(state.lfo.rate, 0.01, 100);
    lfoGain.gain.value = computeLFODepth();
    lfoOsc.connect(lfoGain);
    lfoOsc.start();
  }

  function stopLFO() {
    if (lfoOsc)  { try { lfoOsc.stop(); } catch (e) {} safeDisconnect(lfoOsc); }
    if (lfoGain) safeDisconnect(lfoGain);
    lfoOsc = null;
    lfoGain = null;
  }

  function computeLFODepth() {
    const d = state.lfo.depth;
    switch (state.lfo.target) {
      case 'pitch':     return d * 200;     // cents
      case 'filter':    return d * 5000;    // Hz
      case 'amplitude': return d * 0.5;
      case 'pan':       return d;
    }
    return d;
  }

  // ── Param updates ─────────────────────────────────────────
  function setMasterVolume(v) {
    state.masterVolume = clamp(v, 0, 1);
    if (masterGain) {
      // A short ramp instead of a jump — dragging the fader used to zip.
      const now = ctx.currentTime;
      masterGain.gain.cancelScheduledValues(now);
      masterGain.gain.setTargetAtTime(state.masterVolume, now, 0.01);
    }
  }

  function setOsc(oscKey, param, value) {
    if (!state[oscKey]) return;
    state[oscKey][param] = value;
  }

  function setEnv(param, value)  { state.env[param]  = value; }
  function setFEnv(param, value) { state.fenv[param] = value; }

  function setFilter(param, value) {
    state.filter[param] = value;
    if (!ctx) return;
    // Apply to sounding voices so sweeping the cutoff is audible on
    // held notes instead of only on the next one.
    const now = ctx.currentTime;
    activeVoices.forEach(voice => {
      if (voice.releasing) return;
      if (param === 'type')      voice.filter.type = value;
      if (param === 'resonance') voice.filter.Q.value = clamp(value, 0.0001, 30);
      if (param === 'cutoff' && state.fenv.amount === 0) {
        voice.filter.frequency.setTargetAtTime(clamp(value, 20, 20000), now, 0.01);
      }
    });
  }

  function setOscFilter(oscKey, param, value) {
    if (!state[oscKey]) return;
    state[oscKey].filter[param] = value;
    if (!ctx) return;
    const now = ctx.currentTime;
    activeVoices.forEach(voice => {
      const f = voice.oscFilters && voice.oscFilters[oscKey];
      if (!f || voice.releasing) return;
      if (param === 'cutoff' && state[oscKey].filter.envAmt === 0) {
        f.frequency.setTargetAtTime(clamp(value, 20, 20000), now, 0.01);
      }
      if (param === 'resonance') f.Q.value = clamp(value, 0.0001, 30);
      if (param === 'type')      f.type = value;
    });
  }

  function setLFO(param, value) {
    state.lfo[param] = value;
    if (param === 'enabled') {
      if (!ctx) return;               // will start on init()
      if (value) startLFO(); else stopLFO();
      return;
    }
    if (!lfoOsc) return;
    if (param === 'rate')  lfoOsc.frequency.value = clamp(value, 0.01, 100);
    if (param === 'wave')  lfoOsc.type = value;
    if (param === 'depth' || param === 'target') lfoGain.gain.value = computeLFODepth();
    // The target decides which AudioParam the LFO is patched into, and
    // that is wired per voice, so existing voices have to be re-patched.
    if (param === 'target') repatchLFOTargets();
  }

  function repatchLFOTargets() {
    if (!lfoGain) return;
    const target = state.lfo.target;
    activeVoices.forEach(voice => {
      if (voice.releasing) return;
      // Drop only this voice's LFO connections, keep its mod-bus ones.
      voice.paramConns = voice.paramConns.filter(({ node, param }) => {
        if (node !== lfoGain) return true;
        try { node.disconnect(param); } catch (e) {}
        return false;
      });
      const add = param => {
        try { lfoGain.connect(param); voice.paramConns.push({ node: lfoGain, param }); } catch (e) {}
      };
      if (target === 'pitch')          voice.oscs.forEach(o => { if (o.detune) add(o.detune); });
      else if (target === 'filter')    add(voice.filter.frequency);
      else if (target === 'amplitude') add(voice.modAmp.gain);
      else if (target === 'pan')       add(voice.panner.pan);
    });
  }

  function setDistortion(param, value) {
    state.dist[param] = value;
    if (!distortionNode) return;
    if (param === 'drive') distortionNode.curve = makeDistortionCurve(value);
    _applyDistMix();
  }

  function _applyDistMix() {
    if (!distortionWet) return;
    const on = !!state.dist.enabled;
    // The shaper adds a lot of level; trim the wet path so switching
    // distortion on does not jump the output by ~10dB.
    const makeup = 1 / (1 + Math.log10(1 + Math.max(0, state.dist.drive) / 10));
    setSmooth(distortionWet.gain,    on ? makeup : 0);
    setSmooth(distortionBypass.gain, on ? 0 : 1);
  }

  function setChorus(param, value) {
    state.chorus[param] = value;
    if (!chorusLFO) return;
    if (param === 'rate') chorusLFO.frequency.value = clamp(value, 0.01, 20);
    if (param === 'depth') {
      const d = clamp(value, 0, 0.05);
      chorusLFOGainL.gain.value =  d;
      chorusLFOGainR.gain.value = -d;
    }
    if (param === 'mix' || param === 'enabled') _applyChorusMix();
  }

  function _applyChorusMix() {
    if (!chorusWet) return;
    const mix = state.chorus.enabled ? clamp(state.chorus.mix, 0, 1) : 0;
    // A true crossfade. Summing wet on top of a full-level dry is what
    // used to make the chorus sound like a comb filter.
    setSmooth(chorusWet.gain, mix);
    setSmooth(chorusDry.gain, 1 - mix);
  }

  function setDelay(param, value) {
    state.delay[param] = value;
    if (param === 'time' && delayNode) {
      delayNode.delayTime.setTargetAtTime(clamp(value, 0, 2), ctx.currentTime, 0.02);
    }
    if (param === 'feedback' && delayFeedback) {
      setSmooth(delayFeedback.gain, clamp(value, 0, 0.95));
    }
    if (param === 'mix' || param === 'enabled') _applyDelayMix();
  }

  function _applyDelayMix() {
    if (!delayWet) return;
    setSmooth(delayWet.gain, state.delay.enabled ? clamp(state.delay.mix, 0, 1) : 0);
  }

  function setReverb(param, value) {
    state.reverb[param] = value;
    if ((param === 'size' || param === 'damp') && reverbNode) {
      reverbNode.buffer = buildImpulse(state.reverb.size, state.reverb.damp * 5 + 1);
    }
    if (param === 'mix' || param === 'enabled') _applyReverbMix();
  }

  function _applyReverbMix() {
    if (!reverbWet) return;
    setSmooth(reverbWet.gain, state.reverb.enabled ? clamp(state.reverb.mix, 0, 1) : 0);
  }

  function setSmooth(param, target) {
    if (!ctx) { param.value = target; return; }
    param.setTargetAtTime(target, ctx.currentTime, 0.01);
  }

  // ── Mod matrix application (called each animation frame) ──
  function applyModMatrix(dt) {
    if (!ctx || !modBusPitch || typeof ModMatrix === 'undefined') return;

    if (state.lfo.enabled) {
      jsLFOPhase += state.lfo.rate * dt * Math.PI * 2;
      // Wrap so the phase never loses float precision in a long session.
      if (jsLFOPhase > Math.PI * 2) jsLFOPhase %= Math.PI * 2;
    }
    const lfo1Val = state.lfo.enabled ? Math.sin(jsLFOPhase) : 0;

    // Envelope follower from the newest held voice.
    let envVal = 0;
    let newest = null;
    activeVoices.forEach(v => {
      if (v.releasing) return;
      if (!newest || v.startTime > newest.startTime) newest = v;
    });
    if (newest) {
      const age = ctx.currentTime - newest.startTime;
      const { attack, decay, sustain } = state.env;
      if      (age < attack)         envVal = attack > 0 ? age / attack : 1;
      else if (age < attack + decay) envVal = 1 - (1 - sustain) * (age - attack) / Math.max(1e-6, decay);
      else                           envVal = sustain;
    }

    ModMatrix.tick(dt, lfo1Val, envVal, _lastNoteVal, _lastVelVal);

    const mv  = ModMatrix.modValues;
    const now = ctx.currentTime;
    const getRange = id => (ModMatrix.DESTINATIONS.find(d => d.id === id) || {}).defaultRange || 1;

    // setTargetAtTime instead of setValueAtTime: stepping a control
    // signal once per animation frame is what produced zipper noise.
    const smooth = 0.012;
    modBusPitch    .offset.setTargetAtTime(mv.pitch      * getRange('pitch') * 100, now, smooth);
    modBusFilterCut.offset.setTargetAtTime(mv.filter_cut * getRange('filter_cut'),  now, smooth);
    modBusOsc1Det  .offset.setTargetAtTime(mv.osc1_det   * getRange('osc1_det'),    now, smooth);
    modBusOsc2Det  .offset.setTargetAtTime(mv.osc2_det   * getRange('osc2_det'),    now, smooth);
    modBusOsc3Det  .offset.setTargetAtTime(mv.osc3_det   * getRange('osc3_det'),    now, smooth);
    modBusAmp      .offset.setTargetAtTime(clamp(mv.amp  * getRange('amp'), -1, 1), now, smooth);
    modBusPan      .offset.setTargetAtTime(clamp(mv.pan  * getRange('pan'), -1, 1), now, smooth);

    // Resonance has no dedicated bus (Q takes no connections in all
    // engines), so write it per voice — but only when it moves.
    const targetRes = clamp(state.filter.resonance + mv.filter_res * getRange('filter_res'), 0.1, 30);
    if (_lastFilterRes === null || Math.abs(targetRes - _lastFilterRes) > 0.01) {
      _lastFilterRes = targetRes;
      activeVoices.forEach(voice => { voice.filter.Q.value = targetRes; });
    }

    if (lfoOsc && mv.lfo1_rate !== 0) {
      lfoOsc.frequency.setTargetAtTime(
        clamp(state.lfo.rate + mv.lfo1_rate * getRange('lfo1_rate'), 0.01, 30), now, smooth);
    }

    // Hand the remaining destinations to the engines that own them.
    if (typeof WTEngine !== 'undefined' && WTEngine.setPositionMod) WTEngine.setPositionMod(mv.wt_pos);
    if (typeof FMEngine !== 'undefined' && FMEngine.setIndexMod)    FMEngine.setIndexMod(mv.fm_index);
  }

  // ── Load preset ───────────────────────────────────────────
  function loadPreset(preset) {
    // Reset to defaults first. Without this, a patch that omits (say)
    // osc3 or a per-osc filter inherits it from whatever was loaded
    // before, so the same preset sounds different depending on history.
    deepMerge(state, clone(DEFAULT_STATE));
    if (preset) deepMerge(state, preset);

    if (ctx) {
      if (state.lfo.enabled) {
        if (!lfoOsc) startLFO();
        else {
          lfoOsc.frequency.value = clamp(state.lfo.rate, 0.01, 100);
          lfoOsc.type = state.lfo.wave;
          lfoGain.gain.value = computeLFODepth();
        }
      } else {
        stopLFO();
      }

      _applyDistMix();
      if (distortionNode) distortionNode.curve = makeDistortionCurve(state.dist.drive);
      setChorus('rate',  state.chorus.rate);
      setChorus('depth', state.chorus.depth);
      _applyChorusMix();
      setDelay('time',     state.delay.time);
      setDelay('feedback', state.delay.feedback);
      _applyDelayMix();
      if (reverbNode) reverbNode.buffer = buildImpulse(state.reverb.size, state.reverb.damp * 5 + 1);
      _applyReverbMix();
      setMasterVolume(state.masterVolume);
    }
  }

  function resetState() { loadPreset(null); }

  // ── Helpers ───────────────────────────────────────────────
  const ABS_CURVE = (() => {
    const c = new Float32Array(512);
    for (let i = 0; i < 512; i++) c[i] = Math.abs((i / 511) * 2 - 1);
    return c;
  })();

  function midiToFreq(note) {
    if (typeof Microtonal !== 'undefined' && Microtonal.getState().enabled) {
      return Microtonal.noteToFreq(note);
    }
    return 440 * Math.pow(2, (note - 69) / 12);
  }

  function clamp(v, lo, hi) {
    v = Number(v);
    if (!isFinite(v)) return lo;
    return Math.max(lo, Math.min(hi, v));
  }

  function clone(o) {
    return JSON.parse(JSON.stringify(o));
  }

  function deepMerge(target, source) {
    for (const key of Object.keys(source)) {
      const v = source[key];
      if (Array.isArray(v)) {
        target[key] = v.slice();
      } else if (v && typeof v === 'object') {
        if (!target[key] || typeof target[key] !== 'object') target[key] = {};
        deepMerge(target[key], v);
      } else {
        target[key] = v;
      }
    }
    return target;
  }

  function notifyUI() {
    if (typeof UI !== 'undefined' && UI && UI.updateActiveNotes) UI.updateActiveNotes();
  }

  function getState() { return state; }
  function getDefaultState() { return clone(DEFAULT_STATE); }
  function getAnalyser() { return analyser; }
  function getActiveVoices() { return activeVoices; }
  function getHeldNotes() { return [...heldVoices.keys()].sort((a, b) => a - b); }
  function getVoiceCount() { return activeVoices.size; }
  function _getContext() { return ctx; }

  return {
    init, ensureContext,
    noteOn, noteOff, panic,
    setMasterVolume,
    setOsc, setEnv, setFEnv,
    setFilter, setOscFilter, setLFO, applyModMatrix,
    setDistortion, setChorus, setDelay, setReverb,
    loadPreset, resetState,
    getState, getDefaultState, getAnalyser, getActiveVoices, getHeldNotes, getVoiceCount,
    midiToFreq, _getContext,
    setQuality, getQuality,
    _voiceDestination: null,
  };

})();

if (typeof module !== 'undefined' && module.exports) module.exports = Synth;
