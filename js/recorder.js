/* ============================================================
   QOIX Synthesizer — Session Recorder
   ============================================================
   Records live note events + synth state snapshot.
   Plays back the session with the original patch settings.
   Save/load sessions as JSON files.
   ============================================================ */

'use strict';

const Recorder = (() => {

  let _recording  = false;
  let _playing     = false;
  let _startTime   = 0;
  let _events      = [];
  let _patchState  = null;
  let _playTimer   = null;
  let _playIndex   = 0;
  let _playStart   = 0;
  let _sessionName = 'Session';
  let _onUpdate    = null;   // callback for UI refresh
  let _onNoteOn    = null;   // supplied by the UI so playback drives every engine
  let _onNoteOff   = null;

  // The UI owns the note routing (subtractive + FM + wavetable + spectral
  // + key highlighting). Without these the recorder used to play back
  // through the subtractive engine only, so a session recorded with FM
  // or wavetable on came back sounding like a different patch.
  function setNoteCallbacks(onOn, onOff) {
    _onNoteOn  = onOn;
    _onNoteOff = onOff;
  }

  function emitNoteOn(note, velocity) {
    if (_onNoteOn) _onNoteOn(note, velocity);
    else Synth.noteOn(note, velocity);
    if (typeof UI !== 'undefined' && UI._setPianoKeyExternal) UI._setPianoKeyExternal(note, true);
  }

  function emitNoteOff(note) {
    if (_onNoteOff) _onNoteOff(note);
    else Synth.noteOff(note);
    if (typeof UI !== 'undefined' && UI._setPianoKeyExternal) UI._setPianoKeyExternal(note, false);
  }

  function setUpdateCallback(fn) { _onUpdate = fn; }
  function _notify() { if (_onUpdate) _onUpdate(); }

  // ── Record ────────────────────────────────────────────────
  function startRecording() {
    if (_recording) return;
    _recording  = true;
    _events     = [];
    _startTime  = performance.now() / 1000;
    // Snapshot current synth settings at the moment recording starts
    _patchState = JSON.parse(JSON.stringify(Synth.getState()));
    _notify();
    console.log('[Recorder] Recording started');
  }

  function stopRecording() {
    if (!_recording) return;
    _recording = false;
    _notify();
    console.log(`[Recorder] Stopped — ${_events.length} events, ${getDuration().toFixed(2)}s`);
  }

  // Called by UI's playNote / releaseNote wrappers
  function recordNoteOn(midiNote, velocity) {
    if (!_recording) return;
    _events.push({ type: 'noteOn', note: midiNote, velocity, time: _elapsed() });
  }

  function recordNoteOff(midiNote) {
    if (!_recording) return;
    _events.push({ type: 'noteOff', note: midiNote, time: _elapsed() });
  }

  function _elapsed() {
    return performance.now() / 1000 - _startTime;
  }

  // ── Playback ──────────────────────────────────────────────
  // Playback runs a single rolling timer over a sorted event list rather
  // than arming one setTimeout per event — a ten-minute session with a
  // few thousand notes used to queue a few thousand live timers.
  const LOOKAHEAD_MS = 25;

  function startPlayback() {
    if (_playing || _events.length === 0) return;
    _playing = true;

    // Restore the patch from when recording started
    if (_patchState) Synth.loadPreset(_patchState);
    if (typeof UI !== 'undefined' && UI.syncUI) UI.syncUI();

    _events.sort((a, b) => a.time - b.time);
    _playIndex = 0;
    _playStart = performance.now();
    _pump();

    _notify();
    console.log('[Recorder] Playback started');
  }

  function _pump() {
    if (!_playing) return;
    const elapsed = (performance.now() - _playStart) / 1000;

    while (_playIndex < _events.length && _events[_playIndex].time <= elapsed + LOOKAHEAD_MS / 1000) {
      const ev = _events[_playIndex++];
      if (ev.type === 'noteOn') emitNoteOn(ev.note, ev.velocity);
      else                      emitNoteOff(ev.note);
    }

    if (_playIndex >= _events.length) {
      // Let the release tail ring out before tearing down.
      _playTimer = setTimeout(stopPlayback, 1500);
      return;
    }
    const nextIn = Math.max(1, (_events[_playIndex].time - elapsed) * 1000 - LOOKAHEAD_MS);
    _playTimer = setTimeout(_pump, Math.min(nextIn, 200));
  }

  function stopPlayback() {
    if (!_playing) return;
    _playing = false;
    clearTimeout(_playTimer);
    _playTimer = null;
    _playIndex = 0;
    Synth.panic();
    if (typeof UI !== 'undefined' && UI.clearAllPianoKeys) UI.clearAllPianoKeys();
    _notify();
    console.log('[Recorder] Playback stopped');
  }

  // ── Session info ──────────────────────────────────────────
  function getDuration() {
    if (_events.length === 0) return 0;
    return _events[_events.length - 1].time;
  }

  function getNoteCount() {
    return _events.filter(e => e.type === 'noteOn').length;
  }

  function isRecording() { return _recording; }
  function isPlaying()   { return _playing; }
  function hasSession()  { return _events.length > 0; }

  // ── Save / Load ───────────────────────────────────────────
  function saveSession(name) {
    const session = {
      version: 1,
      name: name || _sessionName,
      created: new Date().toISOString(),
      duration: getDuration(),
      noteCount: getNoteCount(),
      synthState: _patchState,
      events: _events,
    };
    const json = JSON.stringify(session, null, 2);
    const blob = new Blob([json], { type: 'application/json' });
    const url  = URL.createObjectURL(blob);
    const a    = document.createElement('a');
    a.href     = url;
    a.download = (name || 'qoix-session').replace(/\s+/g, '-') + '.json';
    a.click();
    URL.revokeObjectURL(url);
  }

  function loadSession(json) {
    const session = typeof json === 'string' ? JSON.parse(json) : json;
    if (!Array.isArray(session.events) || !session.synthState) {
      throw new Error('Invalid session file');
    }
    // Reject anything that is not a well-formed event, rather than
    // letting a malformed file throw mid-playback.
    _events = session.events.filter(e =>
      e && (e.type === 'noteOn' || e.type === 'noteOff') &&
      Number.isFinite(e.note) && Number.isFinite(e.time)
    ).sort((a, b) => a.time - b.time);
    _patchState = session.synthState;
    _sessionName = session.name || 'Session';
    _recording  = false;
    _playing    = false;
    _notify();
    console.log(`[Recorder] Session loaded: "${_sessionName}", ${_events.length} events, ${getDuration().toFixed(2)}s`);
    return session;
  }

  return {
    startRecording, stopRecording,
    recordNoteOn, recordNoteOff,
    startPlayback, stopPlayback,
    isRecording, isPlaying, hasSession,
    getDuration, getNoteCount,
    saveSession, loadSession,
    setUpdateCallback, setNoteCallbacks,
  };

})();

if (typeof module !== 'undefined' && module.exports) module.exports = Recorder;
