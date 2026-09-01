/* ============================================================
   QOIX Synthesizer — Random Note Generator
   ============================================================
   Generates random notes within a key/scale at a given tempo.
   Can produce single notes, chords, or walking-bass patterns.
   ============================================================ */

'use strict';

const RandomGen = (() => {

  // Scale definitions (intervals from root in semitones)
  const SCALES = {
    'Chromatic':      [0,1,2,3,4,5,6,7,8,9,10,11],
    'Major':          [0,2,4,5,7,9,11],
    'Natural Minor':  [0,2,3,5,7,8,10],
    'Harmonic Minor': [0,2,3,5,7,8,11],
    'Dorian':         [0,2,3,5,7,9,10],
    'Phrygian':       [0,1,3,5,7,8,10],
    'Lydian':         [0,2,4,6,7,9,11],
    'Mixolydian':     [0,2,4,5,7,9,10],
    'Pentatonic Maj': [0,2,4,7,9],
    'Pentatonic Min': [0,3,5,7,10],
    'Blues':          [0,3,5,6,7,10],
    'Whole Tone':     [0,2,4,6,8,10],
    'Diminished':     [0,2,3,5,6,8,9,11],
    'Augmented':      [0,3,4,7,8,11],
    'Japanese':       [0,1,5,7,8],
  };

  const ROOT_NAMES = ['C','C#','D','D#','E','F','F#','G','G#','A','A#','B'];

  const state = {
    enabled: false,
    bpm: 120,
    rootNote: 0,           // 0=C, 1=C#, etc.
    scale: 'Major',
    octaveLow: 3,
    octaveHigh: 5,
    noteLength: 0.5,       // fraction of step (0.1 = staccato, 1 = legato)
    density: 0.8,          // probability a step triggers (0..1)
    mode: 'single',        // 'single' | 'chord' | 'arp' | 'walk'
    chordSize: 3,          // notes in chord
    swing: 0,              // swing amount 0..1
    stepDiv: 8,            // steps per bar (8 = 8th notes, 16 = 16th notes)
  };

  let _timer = null;
  let _stepIndex = 0;
  let _arpNotes = [];
  let _arpIdx = 0;
  let _onNoteOn = null;
  let _onNoteOff = null;
  let _lastNote = null;
  let _nextStepAt = 0;              // absolute ms of the next step
  const _sounding = new Set();      // notes this generator currently holds
  const _offTimers = new Set();     // pending note-off timers

  function now() { return (typeof performance !== 'undefined' ? performance.now() : Date.now()); }

  // Length of one step in ms at the current tempo/division.
  function stepMs() {
    return (60000 / Math.max(1, state.bpm)) / (Math.max(1, state.stepDiv) / 4);
  }

  // Swing delays the off-beats and pulls the following beat back by the
  // same amount, so the bar length is unchanged. The old version only
  // ever added delay, which made the whole sequence run flat.
  function swingOffset(stepIdx) {
    const amt = Math.max(0, Math.min(1, state.swing)) * 0.33;
    return (stepIdx % 2 === 1 ? 1 : -1) * stepMs() * amt;
  }

  function getScaleNotes() {
    const intervals = SCALES[state.scale] || SCALES['Major'];
    const notes = [];
    for (let oct = state.octaveLow; oct <= state.octaveHigh; oct++) {
      intervals.forEach(interval => {
        const midi = (oct + 1) * 12 + state.rootNote + interval;
        if (midi >= 21 && midi <= 108) notes.push(midi);
      });
    }
    return [...new Set(notes)].sort((a,b) => a - b);
  }

  function pickRandom(arr) {
    return arr[Math.floor(Math.random() * arr.length)];
  }

  function step() {
    if (!state.enabled) return;

    const len = stepMs();

    // Probability gate
    if (Math.random() > state.density) {
      _stepIndex++;
      scheduleNext();
      return;
    }

    const noteLen = Math.max(20, len * state.noteLength);
    const notes = getScaleNotes();
    if (!notes.length) { _stepIndex++; scheduleNext(); return; }

    let toPlay = [];

    switch (state.mode) {
      case 'single':
        toPlay = [pickRandom(notes)];
        break;

      case 'chord': {
        // Random chord: root + stacked thirds within scale
        const root = pickRandom(notes);
        toPlay = [root];
        let cursor = root;
        for (let i = 1; i < state.chordSize; i++) {
          // Find next scale note ~3-5 semitones up
          const candidates = notes.filter(n => n > cursor && n - cursor >= 3 && n - cursor <= 7);
          if (!candidates.length) break;
          cursor = candidates[Math.floor(Math.random() * Math.min(candidates.length, 2))];
          toPlay.push(cursor);
        }
        break;
      }

      case 'arp': {
        // Arp through a fixed chord
        if (_arpNotes.length === 0 || _stepIndex % (state.chordSize * 2) === 0) {
          const root = pickRandom(notes.filter(n => n % 12 === state.rootNote));
          _arpNotes = [];
          let cursor = root || notes[0];
          for (let i = 0; i < state.chordSize; i++) {
            _arpNotes.push(cursor);
            const next = notes.filter(n => n > cursor && n - cursor >= 3 && n - cursor <= 7);
            if (next.length) cursor = next[0]; else break;
          }
          _arpIdx = 0;
        }
        if (_arpNotes.length) {
          toPlay = [_arpNotes[_arpIdx % _arpNotes.length]];
          _arpIdx++;
        }
        break;
      }

      case 'walk': {
        // Walking bass: step-wise motion with occasional leaps
        if (_lastNote === null) _lastNote = notes[Math.floor(notes.length / 2)];
        const neighbors = notes.filter(n => Math.abs(n - _lastNote) <= 4 && n !== _lastNote);
        const leapTargets = notes.filter(n => Math.abs(n - _lastNote) > 4 && Math.abs(n - _lastNote) <= 10);
        const leap = Math.random() < 0.15 && leapTargets.length;
        const pool = leap ? leapTargets : (neighbors.length ? neighbors : notes);
        const next = pickRandom(pool);
        _lastNote = next;
        toPlay = [next];
        break;
      }
    }

    // Play. De-duplicate: a chord that picks the same pitch twice would
    // otherwise have its first copy cut short by the second note-off.
    toPlay = [...new Set(toPlay)];
    toPlay.forEach(n => {
      _sounding.add(n);
      if (_onNoteOn) _onNoteOn(n, 0.7 + Math.random() * 0.25);
    });

    // Schedule note off
    const offTimer = setTimeout(() => {
      _offTimers.delete(offTimer);
      toPlay.forEach(n => releaseOne(n));
    }, noteLen);
    _offTimers.add(offTimer);

    _stepIndex++;
    scheduleNext();
  }

  function releaseOne(n) {
    if (!_sounding.has(n)) return;
    _sounding.delete(n);
    if (_onNoteOff) _onNoteOff(n);
  }

  // Absolute-time scheduling. Chaining setTimeout(stepLength) accumulates
  // every timer's overshoot, so the old sequencer drifted audibly flat
  // within a few bars; anchoring to _nextStepAt keeps it on the grid.
  function scheduleNext() {
    _nextStepAt += stepMs();
    const target = _nextStepAt + swingOffset(_stepIndex);
    _timer = setTimeout(step, Math.max(1, target - now()));
  }

  function start() {
    if (_timer) stop();
    state.enabled = true;
    _stepIndex = 0;
    _arpNotes = [];
    _arpIdx = 0;
    _lastNote = null;
    _nextStepAt = now();
    scheduleNext();
  }

  function stop() {
    state.enabled = false;
    clearTimeout(_timer);
    _timer = null;
    _offTimers.forEach(t => clearTimeout(t));
    _offTimers.clear();
    // Release anything still held, or stopping mid-note leaves it ringing.
    [..._sounding].forEach(releaseOne);
  }

  function isRunning() { return state.enabled; }

  function setCallbacks(onOn, onOff) {
    _onNoteOn = onOn;
    _onNoteOff = onOff;
  }

  function set(param, value) {
    if (!(param in state)) return;
    state[param] = value;
    if ((param === 'bpm' || param === 'stepDiv') && state.enabled) {
      // Re-anchor the grid to now so a tempo change takes effect on the
      // next step instead of waiting out the already-scheduled interval.
      clearTimeout(_timer);
      _nextStepAt = now();
      scheduleNext();
    }
    if (param === 'octaveLow'  && state.octaveHigh < value) state.octaveHigh = value;
    if (param === 'octaveHigh' && state.octaveLow  > value) state.octaveLow  = value;
  }

  function getScaleNames() { return Object.keys(SCALES); }
  function getRootNames() { return ROOT_NAMES; }
  function getState() { return state; }

  return {
    start, stop, set, setCallbacks, isRunning,
    getScaleNames, getRootNames, getState,
  };

})();

if (typeof module !== 'undefined' && module.exports) module.exports = RandomGen;
