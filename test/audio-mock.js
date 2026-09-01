/* ============================================================
   Minimal Web Audio API mock
   ============================================================
   Enough of the API surface for the QOIX engines to run under
   Node, and enough bookkeeping to assert on what they built:
   every node records its connections, every AudioParam records
   its automation calls, and nodes are counted so leaks show up.
   ============================================================ */

'use strict';

let nodeSerial = 0;

class AudioParam {
  constructor(value = 0, name = 'param') {
    this.value = value;
    this.name = name;
    this.automation = [];
    this.inputs = new Set();
  }
  setValueAtTime(v, t)              { this.value = v; this.automation.push(['setValueAtTime', v, t]); return this; }
  linearRampToValueAtTime(v, t)     { this.value = v; this.automation.push(['linearRamp', v, t]); return this; }
  exponentialRampToValueAtTime(v, t){ this.value = v; this.automation.push(['expRamp', v, t]); return this; }
  setTargetAtTime(v, t, c)          { this.value = v; this.automation.push(['setTarget', v, t, c]); return this; }
  cancelScheduledValues(t)          { this.automation.push(['cancel', t]); return this; }
  cancelAndHoldAtTime(t)            { this.automation.push(['cancelAndHold', t]); return this; }
}

class AudioNode {
  constructor(ctx, type) {
    this.context = ctx;
    this.type_ = type;
    this.id = ++nodeSerial;
    this.outputs = new Set();     // AudioNode | AudioParam
    this.disposed = false;
    ctx._nodes.add(this);
  }
  connect(target) {
    this.outputs.add(target);
    if (target instanceof AudioParam) target.inputs.add(this);
    return target;
  }
  disconnect(target) {
    if (target === undefined) {
      this.outputs.forEach(t => { if (t instanceof AudioParam) t.inputs.delete(this); });
      this.outputs.clear();
    } else {
      if (!this.outputs.has(target)) throw new Error('not connected');
      this.outputs.delete(target);
      if (target instanceof AudioParam) target.inputs.delete(this);
    }
  }
  // Test helper: is there any path from here to `target`?
  reaches(target, seen = new Set()) {
    if (this === target) return true;
    if (seen.has(this)) return false;
    seen.add(this);
    for (const out of this.outputs) {
      if (out === target) return true;
      if (out instanceof AudioNode && out.reaches(target, seen)) return true;
    }
    return false;
  }
}

class GainNode extends AudioNode {
  constructor(ctx) { super(ctx, 'gain'); this.gain = new AudioParam(1, 'gain'); }
}

class OscillatorNode extends AudioNode {
  constructor(ctx) {
    super(ctx, 'oscillator');
    this.frequency = new AudioParam(440, 'frequency');
    this.detune = new AudioParam(0, 'detune');
    this.type = 'sine';
    this.started = false;
    this.stoppedAt = null;
  }
  start(t = 0) {
    if (this.started) throw new Error('already started');
    this.started = true; this.startedAt = t;
    this.context._started++;
  }
  stop(t = 0) {
    if (!this.started) throw new Error('not started');
    if (this.stoppedAt !== null) throw new Error('already stopped');
    this.stoppedAt = t;
    this.context._stopped++;
  }
  setPeriodicWave(w) { this.periodicWave = w; }
}

class BufferSourceNode extends AudioNode {
  constructor(ctx) {
    super(ctx, 'bufferSource');
    this.buffer = null; this.loop = false;
    this.playbackRate = new AudioParam(1, 'playbackRate');
    this.detune = null;
    this.started = false; this.stoppedAt = null;
  }
  start(t = 0, off = 0) {
    if (this.started) throw new Error('already started');
    this.started = true; this.offset = off; this.context._started++;
  }
  stop(t = 0) {
    if (!this.started) throw new Error('not started');
    if (this.stoppedAt !== null) throw new Error('already stopped');
    this.stoppedAt = t; this.context._stopped++;
  }
}

class BiquadFilterNode extends AudioNode {
  constructor(ctx) {
    super(ctx, 'biquad');
    this.type = 'lowpass';
    this.frequency = new AudioParam(350, 'frequency');
    this.Q = new AudioParam(1, 'Q');
    this.gain = new AudioParam(0, 'gain');
    this.detune = new AudioParam(0, 'detune');
  }
}

class DelayNode extends AudioNode {
  constructor(ctx, max) { super(ctx, 'delay'); this.maxDelayTime = max; this.delayTime = new AudioParam(0, 'delayTime'); }
}

class ConvolverNode extends AudioNode {
  constructor(ctx) { super(ctx, 'convolver'); this.buffer = null; this.normalize = true; }
}

class WaveShaperNode extends AudioNode {
  constructor(ctx) { super(ctx, 'waveShaper'); this.curve = null; this.oversample = 'none'; }
}

class StereoPannerNode extends AudioNode {
  constructor(ctx) { super(ctx, 'stereoPanner'); this.pan = new AudioParam(0, 'pan'); }
}

class ConstantSourceNode extends AudioNode {
  constructor(ctx) {
    super(ctx, 'constantSource');
    this.offset = new AudioParam(0, 'offset');
    this.started = false;
  }
  start() { this.started = true; }
  stop()  { this.started = false; }
}

class DynamicsCompressorNode extends AudioNode {
  constructor(ctx) {
    super(ctx, 'compressor');
    this.threshold = new AudioParam(-24, 'threshold');
    this.knee = new AudioParam(30, 'knee');
    this.ratio = new AudioParam(12, 'ratio');
    this.attack = new AudioParam(0.003, 'attack');
    this.release = new AudioParam(0.25, 'release');
    this.reduction = 0;
  }
}

class AnalyserNode extends AudioNode {
  constructor(ctx) {
    super(ctx, 'analyser');
    this._fftSize = 2048;
    this.smoothingTimeConstant = 0.8;
  }
  get fftSize() { return this._fftSize; }
  set fftSize(v) {
    if ((v & (v - 1)) !== 0 || v < 32 || v > 32768) throw new Error('bad fftSize ' + v);
    this._fftSize = v;
  }
  get frequencyBinCount() { return this._fftSize / 2; }
  getFloatTimeDomainData(a) { a.fill(0); }
  getByteFrequencyData(a)   { a.fill(0); }
}

class AudioBuffer {
  constructor(nCh, len, sr) {
    this.numberOfChannels = nCh;
    this.length = len;
    this.sampleRate = sr;
    this.duration = len / sr;
    this._data = [];
    for (let i = 0; i < nCh; i++) this._data.push(new Float32Array(len));
  }
  getChannelData(i) { return this._data[i]; }
}

class AudioContext {
  constructor() {
    this.sampleRate = 48000;
    this.baseLatency = 0.005;
    this.state = 'running';
    this.currentTime = 0;
    this.destination = null;
    this._nodes = new Set();
    this._started = 0;
    this._stopped = 0;
    this.destination = new GainNode(this);
    this.destination.type_ = 'destination';
  }
  resume() { this.state = 'running'; return Promise.resolve(); }
  suspend() { this.state = 'suspended'; return Promise.resolve(); }
  close()  { this.state = 'closed'; return Promise.resolve(); }

  createGain()               { return new GainNode(this); }
  createOscillator()         { return new OscillatorNode(this); }
  createBufferSource()       { return new BufferSourceNode(this); }
  createBiquadFilter()       { return new BiquadFilterNode(this); }
  createDelay(max = 1)       { return new DelayNode(this, max); }
  createConvolver()          { return new ConvolverNode(this); }
  createWaveShaper()         { return new WaveShaperNode(this); }
  createStereoPanner()       { return new StereoPannerNode(this); }
  createConstantSource()     { return new ConstantSourceNode(this); }
  createDynamicsCompressor() { return new DynamicsCompressorNode(this); }
  createAnalyser()           { return new AnalyserNode(this); }
  createBuffer(n, l, sr)     { return new AudioBuffer(n, l, sr); }
  createPeriodicWave(real, imag) {
    if (real.length !== imag.length) throw new Error('real/imag length mismatch');
    return { real, imag, __periodicWave: true };
  }

  // ── Test helpers ────────────────────────────────────────
  advance(seconds) { this.currentTime += seconds; }
  liveNodeCount()  { return this._nodes.size; }
  // Nodes still feeding something — a leak is a node that survives a
  // note with outgoing connections nobody ever tore down.
  connectedNodeCount() {
    let n = 0;
    this._nodes.forEach(node => { if (node.outputs.size > 0) n++; });
    return n;
  }
}

function install(globalObj = global) {
  globalObj.AudioContext = AudioContext;
  globalObj.webkitAudioContext = AudioContext;
  globalObj.AudioParam = AudioParam;
  globalObj.window = globalObj.window || globalObj;
  globalObj.window.AudioContext = AudioContext;
  return AudioContext;
}

module.exports = { install, AudioContext, AudioParam, AudioNode };
