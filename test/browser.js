#!/usr/bin/env node
/* ============================================================
   QOIX browser integration test
   ============================================================
   Loads the real page in Chromium and renders audio through the
   actual Web Audio implementation. Where test/run.js checks the
   graph the engines *build*, this checks the sound they *make*:
   every effect must measurably change the signal, and the master
   bus must not clip.

       npm run test:browser

   Skips (exit 0) if Playwright or a Chromium build is not present,
   so it can sit in CI alongside the unit tests without being a
   hard dependency.
   ============================================================ */

'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const PAGE = 'file://' + path.join(ROOT, 'index.html');

function findChromium() {
  const fromEnv = process.env.CHROMIUM_PATH;
  if (fromEnv && fs.existsSync(fromEnv)) return fromEnv;
  const base = process.env.PLAYWRIGHT_BROWSERS_PATH;
  if (base && fs.existsSync(base)) {
    for (const dir of fs.readdirSync(base)) {
      if (!dir.startsWith('chromium-')) continue;
      const exe = path.join(base, dir, 'chrome-linux', 'chrome');
      if (fs.existsSync(exe)) return exe;
      const mac = path.join(base, dir, 'chrome-mac', 'Chromium.app', 'Contents', 'MacOS', 'Chromium');
      if (fs.existsSync(mac)) return mac;
    }
  }
  return null;   // let Playwright use its own default
}

let chromium;
try {
  ({ chromium } = require('playwright'));
} catch (e) {
  console.log('Playwright is not installed — skipping the browser test.');
  console.log('  npm i -D playwright && npx playwright install chromium');
  process.exit(0);
}

let passed = 0, failed = 0;
function check(name, ok, detail = '') {
  if (ok) { passed++; console.log(`  [32m✓[0m ${name}${detail ? '  ' + detail : ''}`); }
  else    { failed++; console.log(`  [31m✗[0m ${name}${detail ? '  ' + detail : ''}`); }
}

(async () => {
  const exe = findChromium();
  let browser;
  try {
    browser = await chromium.launch({
      ...(exe ? { executablePath: exe } : {}),
      args: ['--autoplay-policy=no-user-gesture-required', '--no-sandbox'],
    });
  } catch (e) {
    console.log('Could not launch Chromium — skipping the browser test.');
    console.log('  ' + e.message.split('\n')[0]);
    process.exit(0);
  }

  const page = await browser.newPage();
  const pageErrors = [];
  page.on('pageerror', e => pageErrors.push(e.message));
  page.on('console', m => { if (m.type() === 'error') pageErrors.push('console: ' + m.text()); });

  await page.goto(PAGE, { waitUntil: 'load' });
  await page.waitForTimeout(500);

  console.log('\n[1mPage load[0m');
  check('loads with no page or console errors', pageErrors.length === 0,
    pageErrors.length ? pageErrors[0] : '');

  const boot = await page.evaluate(() => ({
    keys: document.querySelectorAll('.key').length,
    tabs: document.querySelectorAll('.tab-btn').length,
    presets: Presets.length,
    canvases: [...document.querySelectorAll('canvas')].every(c => c.width > 0 && c.height > 0),
  }));
  check('the piano, tabs and presets are built', boot.keys > 50 && boot.tabs > 5 && boot.presets > 10,
    `${boot.keys} keys, ${boot.tabs} tabs, ${boot.presets} presets`);
  check('every canvas has a real backing store', boot.canvases);

  console.log('\n[1mLive audio[0m');
  const live = await page.evaluate(async () => {
    Synth.ensureContext();
    const an = Synth.getAnalyser();
    const buf = new Float32Array(an.fftSize);
    const peak = () => { an.getFloatTimeDomainData(buf); let m = 0; for (const v of buf) m = Math.max(m, Math.abs(v)); return m; };
    const wait = ms => new Promise(r => setTimeout(r, ms));

    await wait(250);
    const silence = peak();
    [60, 64, 67].forEach(n => Synth.noteOn(n, 0.9));
    await wait(350);
    const sounding = peak();
    const held = Synth.getHeldNotes().length;
    [60, 64, 67].forEach(n => Synth.noteOff(n));
    const heldAfter = Synth.getHeldNotes().length;
    Synth.panic();
    await wait(150);
    return { silence, sounding, held, heldAfter, afterPanic: peak(), state: Synth._getContext().state };
  });
  check('the audio context runs', live.state === 'running');
  check('holding a chord produces signal', live.sounding > 0.05, `peak ${live.sounding.toFixed(3)}`);
  check('held notes are reported while down and cleared on release',
    live.held === 3 && live.heldAfter === 0);
  check('panic silences the output', live.afterPanic < 0.02, `peak ${live.afterPanic.toFixed(4)}`);

  console.log('\n[1mEvery effect and routing option changes the sound[0m');
  const fx = await page.evaluate(async () => {
    async function renderWith(mutate) {
      const st = JSON.parse(JSON.stringify(Synth.getState()));
      mutate(st);
      const ev = [{ type: 'noteOn', note: 60, velocity: 1, time: 0 },
                  { type: 'noteOff', note: 60, time: 0.6 }];
      const res = await Renderer.render(ev, st, { sampleRate: 22050, bitDepth: 16, tailSeconds: 0.4 }, null);
      return res.audioBuffer.getChannelData(0);
    }
    const differs = (a, b) => {
      for (let i = 0; i < a.length; i++) if (Math.abs(a[i] - b[i]) > 1e-7) return true;
      return false;
    };
    Synth.loadPreset(Presets[0]);
    const dry = await renderWith(() => {});
    const out = {};
    out.distortion = differs(dry, await renderWith(s => { s.dist.enabled = true; s.dist.drive = 200; }));
    out.chorus     = differs(dry, await renderWith(s => { s.chorus.enabled = true; s.chorus.mix = 1; }));
    out.delay      = differs(dry, await renderWith(s => { s.delay.enabled = true; s.delay.mix = 0.8; s.delay.time = 0.1; }));
    out.reverb     = differs(dry, await renderWith(s => { s.reverb.enabled = true; s.reverb.mix = 0.8; }));
    out.unison     = differs(dry, await renderWith(s => { s.osc1.voices = 7; s.osc1.unisonSpread = 30; }));
    out.ringMod    = differs(dry, await renderWith(s => { s.osc2.enabled = true; s.osc2.mixMode = 'ring'; }));
    out.oscFM      = differs(dry, await renderWith(s => { s.osc2.enabled = true; s.osc1.fmFrom = 'osc2'; s.osc1.fmIndex = 1; }));
    out.noise      = differs(dry, await renderWith(s => { s.noise.enabled = true; s.noise.level = 0.5; }));
    return out;
  });
  Object.entries(fx).forEach(([name, ok]) => check(`${name} is audible in the render`, ok));

  console.log('\n[1mMaster bus headroom[0m');
  const head = await page.evaluate(async () => {
    const chord = [];
    for (let n = 48; n < 72; n++) {
      chord.push({ type: 'noteOn', note: n, velocity: 1, time: 0 },
                 { type: 'noteOff', note: n, time: 0.5 });
    }
    const st = JSON.parse(JSON.stringify(Synth.getState()));
    st.masterVolume = 1; st.osc1.level = 1;
    const peakOf = b => { const c = b.getChannelData(0); let m = 0; for (let i = 0; i < c.length; i++) m = Math.max(m, Math.abs(c[i])); return m; };
    const on  = await Renderer.render(chord, st, { sampleRate: 22050, bitDepth: 16, tailSeconds: 0.3, limiter: true }, null);
    const off = await Renderer.render(chord, st, { sampleRate: 22050, bitDepth: 16, tailSeconds: 0.3, limiter: false }, null);
    return { limited: peakOf(on.audioBuffer), unlimited: peakOf(off.audioBuffer) };
  });
  check('a 24-note chord stays inside full scale with the limiter',
    head.limited <= 1.0, `peak ${head.limited.toFixed(3)}`);
  check('the limiter is doing real work', head.unlimited > 1.5,
    `unlimited peak would be ${head.unlimited.toFixed(2)} (${(20 * Math.log10(head.unlimited)).toFixed(1)} dBFS)`);

  console.log('\n[1mOffline render[0m');
  const render = await page.evaluate(async () => {
    const bytes = [];
    const push = (...b) => bytes.push(...b);
    const str = s => { for (const c of s) push(c.charCodeAt(0)); };
    const u32 = v => push((v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255);
    const u16 = v => push((v >> 8) & 255, v & 255);
    str('MThd'); u32(6); u16(0); u16(1); u16(96);
    const tr = []; const tp = (...b) => tr.push(...b);
    tp(0x00, 0x90, 60, 100); tp(0x60, 0x80, 60, 0);
    tp(0x00, 0x90, 64, 100); tp(0x60, 0x80, 64, 0);
    tp(0x00, 0xff, 0x2f, 0x00);
    str('MTrk'); u32(tr.length); push(...tr);

    const info = Renderer.parseMidi(new Uint8Array(bytes).buffer);
    const steps = [];
    const res = await Renderer.render(info.events, Synth.getState(),
      { sampleRate: 22050, bitDepth: 16, tailSeconds: 0.5 }, pct => steps.push(pct));
    const c = res.audioBuffer.getChannelData(0);
    let peak = 0; for (let i = 0; i < c.length; i++) peak = Math.max(peak, Math.abs(c[i]));
    return { notes: info.noteCount, duration: info.duration, bytes: res.wavBlob.size, peak, steps };
  });
  check('parses a MIDI file and renders it', render.notes === 2 && render.bytes > 1000,
    `${render.notes} notes, ${render.bytes} byte WAV`);
  check('the rendered file contains audio', render.peak > 0.05, `peak ${render.peak.toFixed(3)}`);
  check('progress is reported in steps, not one jump',
    new Set(render.steps).size > 4, `${new Set(render.steps).size} distinct updates`);

  console.log('\n[1mPreset switching[0m');
  const presets = await page.evaluate(() => {
    const failures = [];
    Presets.forEach(p => {
      try {
        Synth.loadPreset(p); UI.syncUI(); Synth.noteOn(60, 0.8); Synth.panic();
      } catch (e) { failures.push(`${p.name}: ${e.message}`); }
    });
    // The UI must actually follow the patch.
    Synth.loadPreset(Presets.find(p => /Supersaw/.test(p.name)));
    UI.syncUI();
    const voices = document.getElementById('osc1-voices').value;
    const wave = document.querySelector('[data-osc="1"] .wb.active');
    Synth.loadPreset(Presets[0]); UI.syncUI();
    const backToInit = document.getElementById('osc1-voices').value;
    return { failures, voices, wave: wave && wave.dataset.wave, backToInit };
  });
  check('every preset loads, syncs and plays', presets.failures.length === 0,
    presets.failures[0] || '');
  check('the UI follows the loaded patch', presets.voices === '7' && presets.wave === 'sawtooth',
    `unison ${presets.voices}, wave ${presets.wave}`);
  check('switching back resets patch-specific controls', presets.backToInit === '1',
    `unison ${presets.backToInit}`);

  await browser.close();

  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})().catch(err => {
  console.error(err);
  process.exit(1);
});
