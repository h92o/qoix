/* ============================================================
   QOIX Synthesizer — Offline MIDI Renderer
   ============================================================
   Parses standard MIDI files (.mid) and renders them using the
   current synth patch at a user-selected sample rate via
   OfflineAudioContext — no realtime constraint, no dropouts.
   Exports 16/24-bit PCM or 32-bit float WAV.

   The voice builder here mirrors js/synth.js (unison, per-osc
   filters, osc-to-osc FM, mix modes, microtonal tuning, master
   limiter) so that a rendered file sounds like what you heard.
   ============================================================ */

'use strict';

const Renderer = (() => {

  // ══════════════════════════════════════════════════════════
  //  MIDI BINARY PARSER
  // ══════════════════════════════════════════════════════════
  function parseMidi(arrayBuffer) {
    const raw = new Uint8Array(arrayBuffer);
    const dv  = new DataView(arrayBuffer);
    let pos   = 0;

    const readU8  = () => raw[pos++];
    const readU16 = () => { const v = dv.getUint16(pos); pos += 2; return v; };
    const readU32 = () => { const v = dv.getUint32(pos); pos += 4; return v; };
    const readStr = n => { let s = ''; for (let i=0;i<n;i++) s += String.fromCharCode(raw[pos++]); return s; };

    // Variable-length quantity (used for delta times and meta lengths)
    function readVLQ() {
      let val = 0, byte, guard = 0;
      do {
        byte = readU8();
        val = (val << 7) | (byte & 0x7f);
      } while ((byte & 0x80) && ++guard < 4);
      return val;
    }

    if (raw.length < 14) throw new Error('File is too small to be a MIDI file');
    if (readStr(4) !== 'MThd') throw new Error('Not a MIDI file (missing MThd header)');
    const headerLen = readU32();
    const format    = readU16();
    const numTracks = readU16();
    const divisionRaw = readU16();
    pos += Math.max(0, headerLen - 6);  // tolerate an over-long header chunk

    // Division is either ticks-per-quarter-note, or (when bit 15 is set)
    // SMPTE frames: -framesPerSecond in the high byte, ticks per frame in
    // the low byte. The old parser treated SMPTE files as absurdly high
    // PPQ values and rendered them hundreds of times too fast.
    let ticksPerQuarter = divisionRaw;
    let smpteTicksPerSecond = 0;
    if (divisionRaw & 0x8000) {
      const fps = 256 - (divisionRaw >> 8);       // two's complement of the frame rate
      const ticksPerFrame = divisionRaw & 0xff;
      smpteTicksPerSecond = fps * ticksPerFrame;
      ticksPerQuarter = 0;
    }
    if (!smpteTicksPerSecond && !ticksPerQuarter) {
      throw new Error('MIDI file declares an invalid time division');
    }

    const allEvents = [];

    for (let t = 0; t < numTracks; t++) {
      if (pos + 8 > raw.length) break;             // truncated file: use what we have
      if (readStr(4) !== 'MTrk') throw new Error('Expected an MTrk track chunk');
      const trackLen  = readU32();
      const trackEnd  = Math.min(pos + trackLen, raw.length);
      let   tick      = 0;
      let   lastStatus = 0;

      while (pos < trackEnd) {
        tick += readVLQ();
        if (pos >= trackEnd) break;

        let status = raw[pos];
        if (status & 0x80) {
          pos++;
          // System messages cancel running status; they must not become
          // the running status themselves.
          if (status < 0xf0) lastStatus = status;
        } else {
          status = lastStatus;
          if (!status) { pos++; continue; }        // no running status to resume
        }

        const type = status & 0xf0;

        if (type === 0x90 || type === 0x80) {
          const note = readU8(), vel = readU8();
          const on   = type === 0x90 && vel > 0;
          allEvents.push({ tick, order: allEvents.length, type: on ? 'noteOn' : 'noteOff', note, velocity: vel / 127 });
        } else if (type === 0xa0) { readU8(); readU8();               // poly aftertouch
        } else if (type === 0xb0) { readU8(); readU8();               // CC
        } else if (type === 0xc0) { readU8();                         // program change
        } else if (type === 0xd0) { readU8();                         // channel pressure
        } else if (type === 0xe0) { readU8(); readU8();               // pitch bend
        } else if (status === 0xff) {                                 // meta event
          const meta = readU8();
          const len  = readVLQ();
          if (meta === 0x51 && len === 3) {                           // set tempo
            const uspb = (readU8()<<16) | (readU8()<<8) | readU8();
            allEvents.push({ tick, order: allEvents.length, type: 'tempo', uspb });
          } else { pos += len; }
        } else if (status === 0xf0 || status === 0xf7) {              // sysex
          pos += readVLQ();
        } else { pos++; }
      }
      pos = trackEnd;
    }

    // Stable sort by tick: events at the same tick must keep the order
    // they were read in, or a note-off can overtake its own note-on.
    allEvents.sort((a, b) => a.tick - b.tick || a.order - b.order);

    // ── Tick → seconds ──
    let tickToSec;
    if (smpteTicksPerSecond) {
      tickToSec = tick => tick / smpteTicksPerSecond;   // absolute time; tempo events don't apply
    } else {
      const tempoMap = [{ tick: 0, time: 0, uspb: 500000 }]; // default 120 BPM
      allEvents.filter(e => e.type === 'tempo').forEach(e => {
        const last = tempoMap[tempoMap.length - 1];
        if (e.tick < last.tick) return;
        const time = last.time + ((e.tick - last.tick) / ticksPerQuarter) * (last.uspb / 1e6);
        tempoMap.push({ tick: e.tick, time, uspb: e.uspb });
      });
      tickToSec = tick => {
        // Binary search rather than a linear scan per event.
        let lo = 0, hi = tempoMap.length - 1;
        while (lo < hi) {
          const mid = (lo + hi + 1) >> 1;
          if (tempoMap[mid].tick <= tick) lo = mid; else hi = mid - 1;
        }
        const ref = tempoMap[lo];
        return ref.time + ((tick - ref.tick) / ticksPerQuarter) * (ref.uspb / 1e6);
      };
    }

    const events = allEvents
      .filter(e => e.type === 'noteOn' || e.type === 'noteOff')
      .map(e => ({ type: e.type, note: e.note, velocity: e.velocity, tick: e.tick, time: tickToSec(e.tick) }));

    const lastTick  = allEvents.length ? allEvents[allEvents.length - 1].tick : 0;
    const duration  = tickToSec(lastTick);
    const noteCount = events.filter(e => e.type === 'noteOn').length;

    if (!noteCount) throw new Error('No notes found in this MIDI file');

    return { events, duration, noteCount, format, numTracks };
  }

  // ══════════════════════════════════════════════════════════
  //  WAV ENCODER
  // ══════════════════════════════════════════════════════════
  function writeWavHeader(dv, nCh, sr, bitDepth, dataSize) {
    const bps = bitDepth === 32 ? 4 : bitDepth === 16 ? 2 : 3;
    const isFloat = bitDepth === 32;
    const ws = (off, s) => { for (let i=0;i<s.length;i++) dv.setUint8(off+i, s.charCodeAt(i)); };
    ws(0,  'RIFF'); dv.setUint32(4, 36 + dataSize, true);
    ws(8,  'WAVE'); ws(12, 'fmt ');
    dv.setUint32(16, 16, true);
    dv.setUint16(20, isFloat ? 3 : 1, true);  // 3=IEEE float, 1=PCM
    dv.setUint16(22, nCh, true);
    dv.setUint32(24, sr, true);
    dv.setUint32(28, sr * nCh * bps, true);
    dv.setUint16(32, nCh * bps, true);
    dv.setUint16(34, bitDepth, true);
    ws(36, 'data'); dv.setUint32(40, dataSize, true);
  }

  // Interleave and quantise [from, to) frames into the output buffer.
  function encodeRange(channels, dv, u8, startFrame, endFrame, byteOffset, bitDepth) {
    const nCh = channels.length;
    const isFloat = bitDepth === 32;
    let p = byteOffset;
    for (let i = startFrame; i < endFrame; i++) {
      for (let ch = 0; ch < nCh; ch++) {
        // Channel arrays are hoisted out of the loop — fetching
        // getChannelData() per sample made encoding a 3-minute render
        // take longer than the render itself.
        let s = channels[ch][i];
        s = s > 1 ? 1 : s < -1 ? -1 : s;
        if (isFloat) { dv.setFloat32(p, s, true); p += 4; }
        else if (bitDepth === 24) {
          const v = Math.round(s * 0x7fffff);
          u8[p] = v & 0xff; u8[p+1] = (v >> 8) & 0xff; u8[p+2] = (v >> 16) & 0xff; p += 3;
        } else {
          dv.setInt16(p, Math.round(s * 0x7fff), true); p += 2;
        }
      }
    }
    return p;
  }

  function encodeWAV(audioBuffer, bitDepth = 24) {
    const nCh   = audioBuffer.numberOfChannels;
    const sr    = audioBuffer.sampleRate;
    const nSamp = audioBuffer.length;
    const bps   = bitDepth === 32 ? 4 : bitDepth === 16 ? 2 : 3;
    const dataSize = nSamp * nCh * bps;
    const ab  = new ArrayBuffer(44 + dataSize);
    const dv  = new DataView(ab);
    const u8  = new Uint8Array(ab);

    writeWavHeader(dv, nCh, sr, bitDepth, dataSize);
    const channels = [];
    for (let ch = 0; ch < nCh; ch++) channels.push(audioBuffer.getChannelData(ch));
    encodeRange(channels, dv, u8, 0, nSamp, 44, bitDepth);

    return new Blob([ab], { type: 'audio/wav' });
  }

  // Same output, encoded in slices with a yield between them so a long
  // render does not freeze the window while the WAV is written.
  async function encodeWAVChunked(audioBuffer, bitDepth = 24, onProgress = null) {
    const nCh   = audioBuffer.numberOfChannels;
    const sr    = audioBuffer.sampleRate;
    const nSamp = audioBuffer.length;
    const bps   = bitDepth === 32 ? 4 : bitDepth === 16 ? 2 : 3;
    const dataSize = nSamp * nCh * bps;
    const ab  = new ArrayBuffer(44 + dataSize);
    const dv  = new DataView(ab);
    const u8  = new Uint8Array(ab);

    writeWavHeader(dv, nCh, sr, bitDepth, dataSize);
    const channels = [];
    for (let ch = 0; ch < nCh; ch++) channels.push(audioBuffer.getChannelData(ch));

    const CHUNK = sr * 5;    // five seconds of audio per slice
    let byteOffset = 44;
    for (let start = 0; start < nSamp; start += CHUNK) {
      const end = Math.min(start + CHUNK, nSamp);
      byteOffset = encodeRange(channels, dv, u8, start, end, byteOffset, bitDepth);
      if (onProgress) onProgress(end / nSamp);
      await new Promise(r => setTimeout(r, 0));
    }
    return new Blob([ab], { type: 'audio/wav' });
  }

  // ══════════════════════════════════════════════════════════
  //  OFFLINE SYNTH RENDERER
  // ══════════════════════════════════════════════════════════
  async function render(midiEvents, synthState, options = {}, onProgress = null) {
    const {
      sampleRate  = 48000,
      bitDepth    = 24,
      tailSeconds = 5,   // reverb + release decay tail after last note
      limiter     = true,
    } = options;

    if (!midiEvents || !midiEvents.length) throw new Error('Nothing to render');

    const s = synthState;
    const lastEventTime = midiEvents.reduce((m, e) => Math.max(m, e.time), 0);
    const totalSec      = lastEventTime + Math.max(0, tailSeconds);
    const totalSamp     = Math.ceil(sampleRate * totalSec);

    if (onProgress) onProgress(0, 'Building audio context…');

    const offCtx = new OfflineAudioContext(2, totalSamp, sampleRate);

    // ── Helpers ──────────────────────────────────────────────
    const clamp = (v, lo, hi) => {
      v = Number(v);
      if (!isFinite(v)) return lo;
      return Math.max(lo, Math.min(hi, v));
    };
    // Honour the microtonal scale, so a rendered file is in the same
    // tuning as what was played live.
    const m2f = n => (typeof Microtonal !== 'undefined' && Microtonal.getState().enabled)
      ? Microtonal.noteToFreq(n)
      : 440 * Math.pow(2, (n - 69) / 12);
    const nyquist = sampleRate / 2;

    function distCurve(amount) {
      const n = 1024, c = new Float32Array(n);
      const k = Math.max(0, amount);
      for (let i=0; i<n; i++) {
        const x = (i*2)/(n-1) - 1;
        c[i] = ((Math.PI + k) * x) / (Math.PI + k * Math.abs(x));
      }
      return c;
    }

    function softClipCurve() {
      const n = 2048, c = new Float32Array(n);
      for (let i=0; i<n; i++) c[i] = Math.tanh(((i*2)/(n-1) - 1) * 2);
      return c;
    }

    function makeImpulse(dur, decay) {
      const len = Math.max(1, Math.floor(sampleRate * clamp(dur, 0.05, 10)));
      const buf = offCtx.createBuffer(2, len, sampleRate);
      for (let ch=0; ch<2; ch++) {
        const d = buf.getChannelData(ch);
        const earlyEnd = Math.min(Math.floor(sampleRate * 0.08), len);
        for (let i=0; i<len; i++) {
          const env = Math.pow(1 - i/len, decay);
          d[i] = ((i < earlyEnd ? (Math.random()*2-1)*1.5 : 0) + (Math.random()*2-1)) * env * 0.5;
        }
      }
      return buf;
    }

    // ── Master ──
    const masterGain = offCtx.createGain();
    masterGain.gain.value = s.masterVolume;

    // Match the live chain's limiter + safety clip so a render cannot
    // clip where realtime playback did not.
    let masterIn = masterGain;
    if (limiter) {
      const comp = offCtx.createDynamicsCompressor();
      comp.threshold.value = -3;
      comp.knee.value      = 0;
      comp.ratio.value     = 20;
      comp.attack.value    = 0.002;
      comp.release.value   = 0.18;
      const clip = offCtx.createWaveShaper();
      clip.curve = softClipCurve();
      clip.oversample = '2x';
      comp.connect(clip);
      clip.connect(masterGain);
      masterIn = comp;
    }
    masterGain.connect(offCtx.destination);

    // ── Effect chain ──
    const voiceDest = offCtx.createGain(); // where voices connect

    // Distortion split, with the same makeup trim as the live engine.
    const distNode   = offCtx.createWaveShaper();
    distNode.curve   = distCurve(s.dist.drive);
    distNode.oversample = '4x';
    const distWet    = offCtx.createGain();
    const distBypass = offCtx.createGain();
    const distOn     = !!s.dist.enabled;
    distWet.gain.value    = distOn ? 1 / (1 + Math.log10(1 + Math.max(0, s.dist.drive) / 10)) : 0;
    distBypass.gain.value = distOn ? 0 : 1;
    const postDist = offCtx.createGain();
    voiceDest.connect(distNode);
    voiceDest.connect(distBypass);
    distNode.connect(distWet);
    distWet.connect(postDist);
    distBypass.connect(postDist);

    // Chorus: stereo, two taps in phase opposition, true dry/wet crossfade.
    const chorusMix = s.chorus.enabled ? clamp(s.chorus.mix, 0, 1) : 0;
    const cDelayL = offCtx.createDelay(0.2); cDelayL.delayTime.value = 0.018;
    const cDelayR = offCtx.createDelay(0.2); cDelayR.delayTime.value = 0.024;
    const chorusLFO = offCtx.createOscillator();
    chorusLFO.frequency.value = clamp(s.chorus.rate, 0.01, 20);
    const cLFOGainL = offCtx.createGain(); cLFOGainL.gain.value =  clamp(s.chorus.depth, 0, 0.05);
    const cLFOGainR = offCtx.createGain(); cLFOGainR.gain.value = -clamp(s.chorus.depth, 0, 0.05);
    chorusLFO.connect(cLFOGainL); cLFOGainL.connect(cDelayL.delayTime);
    chorusLFO.connect(cLFOGainR); cLFOGainR.connect(cDelayR.delayTime);
    chorusLFO.start(0);
    const cPanL = offCtx.createStereoPanner(); cPanL.pan.value = -0.7;
    const cPanR = offCtx.createStereoPanner(); cPanR.pan.value =  0.7;
    const chorusWet = offCtx.createGain(); chorusWet.gain.value = chorusMix;
    const chorusDry = offCtx.createGain(); chorusDry.gain.value = 1 - chorusMix;
    const postChorus = offCtx.createGain();
    postDist.connect(chorusDry); postDist.connect(cDelayL); postDist.connect(cDelayR);
    cDelayL.connect(cPanL); cPanL.connect(chorusWet);
    cDelayR.connect(cPanR); cPanR.connect(chorusWet);
    chorusDry.connect(postChorus); chorusWet.connect(postChorus);

    // Delay
    const delayNode = offCtx.createDelay(2);
    delayNode.delayTime.value = clamp(s.delay.time, 0, 2);
    const delayFB  = offCtx.createGain(); delayFB.gain.value = clamp(s.delay.feedback, 0, 0.95);
    const delayWet = offCtx.createGain(); delayWet.gain.value = s.delay.enabled ? clamp(s.delay.mix, 0, 1) : 0;
    const delayDry = offCtx.createGain(); delayDry.gain.value = 1;
    const postDelay = offCtx.createGain();
    delayNode.connect(delayFB); delayFB.connect(delayNode); delayNode.connect(delayWet);
    postChorus.connect(delayDry); postChorus.connect(delayNode);
    delayDry.connect(postDelay); delayWet.connect(postDelay);

    // Reverb
    const revNode = offCtx.createConvolver();
    revNode.buffer = makeImpulse(s.reverb.size, s.reverb.damp * 5 + 1);
    const revWet = offCtx.createGain(); revWet.gain.value = s.reverb.enabled ? clamp(s.reverb.mix, 0, 1) : 0;
    const revDry = offCtx.createGain(); revDry.gain.value = 1;
    const postRev = offCtx.createGain();
    postDelay.connect(revDry); postDelay.connect(revNode);
    revNode.connect(revWet);
    revDry.connect(postRev); revWet.connect(postRev);
    postRev.connect(masterIn);

    // ── LFO ──
    let lfoOsc = null, lfoGain = null;
    if (s.lfo.enabled) {
      lfoOsc = offCtx.createOscillator();
      lfoGain = offCtx.createGain();
      lfoOsc.type = s.lfo.wave;
      lfoOsc.frequency.value = clamp(s.lfo.rate, 0.01, 100);
      const d = s.lfo.depth;
      lfoGain.gain.value = { pitch: d*200, filter: d*5000, amplitude: d*0.5, pan: d }[s.lfo.target] ?? d;
      lfoOsc.connect(lfoGain); lfoOsc.start(0);
    }

    // ── Noise buffer ──
    const _noiseBufs = {};
    function noiseBuf(type) {
      // Cache per type. The old version cached one buffer under whatever
      // type was asked for first, so a patch that switched from white to
      // pink kept rendering white.
      if (_noiseBufs[type]) return _noiseBufs[type];
      const len = Math.floor(sampleRate * 4);
      const buf = offCtx.createBuffer(1, len, sampleRate);
      const d   = buf.getChannelData(0);
      if (type === 'white') {
        for (let i=0; i<len; i++) d[i] = Math.random()*2-1;
      } else {
        let b0=0,b1=0,b2=0,b3=0,b4=0,b5=0;
        for (let i=0; i<len; i++) {
          const w=Math.random()*2-1;
          b0=0.99886*b0+w*0.0555179; b1=0.99332*b1+w*0.0750759;
          b2=0.96900*b2+w*0.1538520; b3=0.86650*b3+w*0.3104856;
          b4=0.55000*b4+w*0.5329522; b5=-0.7616*b5-w*0.0168980;
          d[i] = (b0+b1+b2+b3+b4+b5+w*0.5362)*0.11;
        }
      }
      return (_noiseBufs[type] = buf);
    }

    const ABS_CURVE = (() => {
      const c = new Float32Array(512);
      for (let i = 0; i < 512; i++) c[i] = Math.abs((i / 511) * 2 - 1);
      return c;
    })();

    // ── Note scheduling ──────────────────────────────────────
    const liveNotes = new Map(); // midiNote → voice

    function noteOn(midiNote, velocity, t) {
      if (liveNotes.has(midiNote)) noteOff(midiNote, t); // retrigger
      velocity = clamp(velocity, 0.001, 1);
      const freq = m2f(midiNote);
      const atk = Math.max(0.001, s.env.attack);
      const dec = Math.max(0.001, s.env.decay);

      const ampEnv = offCtx.createGain();
      ampEnv.gain.setValueAtTime(0, t);
      ampEnv.gain.linearRampToValueAtTime(velocity, t + atk);
      ampEnv.gain.linearRampToValueAtTime(clamp(s.env.sustain, 0, 1) * velocity, t + atk + dec);

      const oscMixer = offCtx.createGain();
      const allOscs  = [];

      function makeOscFilt(fs) {
        const f = offCtx.createBiquadFilter();
        f.type = fs.type;
        f.frequency.setValueAtTime(clamp(fs.cutoff, 20, 20000), t);
        f.Q.value = clamp(fs.resonance, 0.0001, 30);
        if (fs.envAmt !== 0) {
          const base = clamp(fs.cutoff, 20, 20000);
          f.frequency.setValueAtTime(base, t);
          f.frequency.linearRampToValueAtTime(clamp(base + fs.envAmt, 20, 20000), t + Math.max(0.001, s.fenv.attack));
          f.frequency.linearRampToValueAtTime(clamp(base + fs.envAmt * s.fenv.sustain, 20, 20000),
            t + Math.max(0.001, s.fenv.attack) + Math.max(0.001, s.fenv.decay));
        }
        if (lfoOsc && fs.lfoDepth > 0) {
          const sc = offCtx.createGain(); sc.gain.value = fs.lfoDepth * s.lfo.depth * 5000;
          lfoOsc.connect(sc); sc.connect(f.frequency);
        }
        f.connect(oscMixer);
        return f;
      }

      // Unison group, summed pre-filter so FM and mix modes can tap it.
      function buildOscs(oscState) {
        const rawSum = offCtx.createGain();
        const group = [];
        const nV = clamp(Math.round(oscState.voices || 1), 1, 16);
        const sp = oscState.unisonSpread || 0;
        const norm = 1 / Math.sqrt(nV);
        for (let v=0; v<nV; v++) {
          const osc  = offCtx.createOscillator();
          const gain = offCtx.createGain();
          osc.type = oscState.wave;
          osc.frequency.value = clamp(freq * Math.pow(2, oscState.octave), 0.01, nyquist);
          osc.detune.value = oscState.detune + (nV > 1 ? ((v/(nV-1))-0.5)*2*sp : 0);
          gain.gain.value = oscState.level * norm;
          osc.connect(gain); gain.connect(rawSum); osc.start(t);
          allOscs.push(osc); group.push(osc);
          if (lfoOsc && s.lfo.target === 'pitch') lfoGain.connect(osc.detune);
        }
        return { rawSum, group };
      }

      const built = {};
      ['osc1','osc2','osc3'].forEach(k => { if (s[k] && s[k].enabled) built[k] = buildOscs(s[k]); });

      // Osc-to-osc FM (missing from the old renderer, so any patch using
      // it rendered as a plain unmodulated tone).
      ['osc1','osc2','osc3'].forEach(tgtKey => {
        const tgt = s[tgtKey];
        if (!tgt || !built[tgtKey]) return;
        const srcKey = tgt.fmFrom;
        if (!srcKey || srcKey === 'none' || srcKey === tgtKey || !built[srcKey]) return;
        const fmGain = offCtx.createGain();
        fmGain.gain.value = (tgt.fmIndex || 0) * freq * Math.pow(2, tgt.octave);
        built[srcKey].rawSum.connect(fmGain);
        built[tgtKey].group.forEach(o => fmGain.connect(o.frequency));
      });

      // Mix modes (also missing before: sub/ring/xor all rendered as add).
      function routeToFilter(rawSum, oscState, filterNode) {
        const mode = oscState.mixMode || 'add';
        const carrier = built.osc1 && built.osc1.rawSum;
        if (mode === 'sub') {
          const neg = offCtx.createGain(); neg.gain.value = -1;
          rawSum.connect(neg); neg.connect(filterNode);
        } else if (mode === 'ring' && carrier && rawSum !== carrier) {
          const ring = offCtx.createGain(); ring.gain.value = 0;
          carrier.connect(ring.gain); rawSum.connect(ring); ring.connect(filterNode);
        } else if (mode === 'xor' && carrier && rawSum !== carrier) {
          const neg = offCtx.createGain(); neg.gain.value = -1;
          carrier.connect(neg);
          const diff = offCtx.createGain();
          rawSum.connect(diff); neg.connect(diff);
          const abs = offCtx.createWaveShaper(); abs.curve = ABS_CURVE;
          diff.connect(abs); abs.connect(filterNode);
        } else {
          rawSum.connect(filterNode);
        }
      }

      if (built.osc1) built.osc1.rawSum.connect(makeOscFilt(s.osc1.filter));
      if (built.osc2) routeToFilter(built.osc2.rawSum, s.osc2, makeOscFilt(s.osc2.filter));
      if (built.osc3) routeToFilter(built.osc3.rawSum, s.osc3, makeOscFilt(s.osc3.filter));

      if (s.noise.enabled) {
        const src = offCtx.createBufferSource();
        src.buffer = noiseBuf(s.noise.type); src.loop = true;
        const ng = offCtx.createGain(); ng.gain.value = s.noise.level;
        src.connect(ng); ng.connect(oscMixer);
        src.start(t, Math.random() * src.buffer.duration);
        allOscs.push(src);
      }

      // Master filter
      const masterFilt = offCtx.createBiquadFilter();
      masterFilt.type = s.filter.type;
      masterFilt.frequency.setValueAtTime(clamp(s.filter.cutoff, 20, 20000), t);
      masterFilt.Q.value = clamp(s.filter.resonance, 0.0001, 30);
      if (s.fenv.amount !== 0) {
        const base = clamp(s.filter.cutoff, 20, 20000);
        masterFilt.frequency.setValueAtTime(base, t);
        masterFilt.frequency.linearRampToValueAtTime(clamp(base + s.fenv.amount, 20, 20000), t + Math.max(0.001, s.fenv.attack));
        masterFilt.frequency.linearRampToValueAtTime(clamp(base + s.fenv.amount * s.fenv.sustain, 20, 20000),
          t + Math.max(0.001, s.fenv.attack) + Math.max(0.001, s.fenv.decay));
      }

      const panner = offCtx.createStereoPanner();
      if (lfoOsc && s.lfo.target === 'filter')    lfoGain.connect(masterFilt.frequency);
      if (lfoOsc && s.lfo.target === 'amplitude') lfoGain.connect(ampEnv.gain);
      if (lfoOsc && s.lfo.target === 'pan')       lfoGain.connect(panner.pan);

      oscMixer.connect(masterFilt);
      masterFilt.connect(ampEnv);
      ampEnv.connect(panner);
      panner.connect(voiceDest);

      liveNotes.set(midiNote, { oscs: allOscs, ampEnv, masterFilt, velocity, noteOnTime: t });
    }

    function noteOff(midiNote, t) {
      const voice = liveNotes.get(midiNote);
      if (!voice) return;
      const rel  = Math.max(0.005, s.env.release);
      const fRel = Math.max(0.005, s.fenv.release);

      // Release from wherever the envelope actually is. Assuming the
      // sustain level made short notes — released during attack or decay
      // — jump to full sustain and click.
      const age = Math.max(0, t - voice.noteOnTime);
      const atk = Math.max(0.001, s.env.attack);
      const dec = Math.max(0.001, s.env.decay);
      const sus = clamp(s.env.sustain, 0, 1);
      let level;
      if      (age < atk)       level = voice.velocity * (age / atk);
      else if (age < atk + dec) level = voice.velocity * (1 - (1 - sus) * (age - atk) / dec);
      else                      level = voice.velocity * sus;

      voice.ampEnv.gain.cancelScheduledValues(t);
      voice.ampEnv.gain.setValueAtTime(level, t);
      voice.ampEnv.gain.linearRampToValueAtTime(0, t + rel);

      if (s.fenv.amount !== 0) {
        voice.masterFilt.frequency.cancelScheduledValues(t);
        voice.masterFilt.frequency.setValueAtTime(
          clamp(s.filter.cutoff + s.fenv.amount * s.fenv.sustain, 20, 20000), t);
        voice.masterFilt.frequency.linearRampToValueAtTime(clamp(s.filter.cutoff, 20, 20000), t + fRel);
      }

      const stopAt = t + rel + 0.1;
      voice.oscs.forEach(o => { try { o.stop(stopAt); } catch(e){} });
      liveNotes.delete(midiNote);
    }

    // ── Schedule all events ──
    if (onProgress) onProgress(6, 'Scheduling MIDI events…');
    midiEvents.forEach(ev => {
      if (ev.type === 'noteOn')  noteOn (ev.note, ev.velocity, ev.time);
      if (ev.type === 'noteOff') noteOff(ev.note, ev.time);
    });
    // Release any notes still held at the end of the file
    [...liveNotes.keys()].forEach(note => noteOff(note, lastEventTime));

    // ── Render, reporting progress from inside the offline graph ──
    if (onProgress) onProgress(10, 'Rendering…');
    if (onProgress && typeof offCtx.suspend === 'function') {
      const STEPS = 12;
      for (let i = 1; i < STEPS; i++) {
        const at = (totalSec * i) / STEPS;
        // suspend() resolves when the render reaches that point; resume()
        // lets it continue. Without this the bar sat at 10% for the whole
        // render and then jumped to 90%.
        offCtx.suspend(at).then(() => {
          onProgress(10 + Math.round((i / STEPS) * 65), 'Rendering…');
          offCtx.resume();
        }).catch(() => {});
      }
    }

    const rendered = await offCtx.startRendering();
    if (onProgress) onProgress(75, 'Encoding WAV…');

    const wavBlob = await encodeWAVChunked(rendered, bitDepth, frac => {
      if (onProgress) onProgress(75 + Math.round(frac * 24), 'Encoding WAV…');
    });
    if (onProgress) onProgress(100, 'Done');

    return { wavBlob, audioBuffer: rendered, sampleRate, bitDepth, duration: totalSec };
  }

  return { parseMidi, render, encodeWAV, encodeWAVChunked };

})();

if (typeof module !== 'undefined' && module.exports) module.exports = Renderer;
