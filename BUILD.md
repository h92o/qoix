# QOIX Synthesizer — Build Guide

## Prerequisites

- Node.js 18+ (https://nodejs.org)
- npm 9+

## Setup

```bash
npm install
```

## Tests

Run these before building — they need no browser and take a second.

```bash
npm test               # engines + MIDI/WAV/SCL parsers, against a Web Audio mock
npm run test:browser   # real audio in Chromium; skips cleanly if it is absent
```

## Run in development

```bash
npm start
# or with DevTools open:
npm run dev
```

## Build installers

```bash
# Current platform only
npm run build

# macOS — universal binary (Intel + Apple Silicon M2)
npm run build:mac

# Windows
npm run build:win

# Linux
npm run build:linux

# All platforms (requires cross-compile tooling)
npm run build:all
```

Output goes to `dist/`.

## macOS outputs
| File | Purpose |
|------|---------|
| `QOIX Synthesizer-1.0.0-universal.dmg` | Drag-to-install for Mac users |
| `QOIX Synthesizer-1.0.0-universal-mac.zip` | For auto-updater |

## Windows outputs
| File | Purpose |
|------|---------|
| `QOIX Synthesizer Setup 1.0.0.exe` | NSIS installer |
| `QOIX Synthesizer 1.0.0.exe` | Portable (no install) |

## Linux outputs
- `.AppImage` — universal, runs anywhere
- `.deb` — Debian/Ubuntu
- `.rpm` — Fedora/RHEL

## The single-file build

```bash
npm run standalone
```

Regenerates `qoix-standalone.html` by inlining `styles.css` and every
`js/*.js` that `index.html` loads. It is a build artifact — edit the
sources and re-run, never edit the bundle directly.

## Icons (optional)

`package.json` deliberately does **not** reference icon files, so a clean
checkout builds with electron-builder's defaults. To ship real artwork,
drop these into `assets/` and add the paths back under `build.mac.icon`,
`build.win.icon`, `build.linux.icon`, `build.nsis.installerIcon` and
`build.dmg.background`:

| File | Size | Platform |
|------|------|----------|
| `icon.icns` | macOS icon bundle | macOS |
| `icon.ico` | Multi-res ICO | Windows |
| `icon.png` | 512×512 PNG | Linux |
| `dmg-background.png` | 540×380 | macOS DMG background |

Use a tool like https://www.electron.build/icons to generate from a single 1024×1024 PNG.

## Signing & Notarization (macOS)

Set these environment variables before building:
```bash
export APPLE_ID="your@email.com"
export APPLE_APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
export APPLE_TEAM_ID="XXXXXXXXXX"
```

Then build — electron-builder handles notarization automatically.

## Auto-updates

`package.json` → `build.publish` points at `h92o/qoix`. Change the `owner`
and `repo` there if you publish somewhere else, or `npm run dist` will fail
to upload. Releases pushed that way trigger auto-update in installed copies.

## Security posture of the Electron shell

The renderer runs with `contextIsolation: true` and `nodeIntegration: false`,
and reaches the main process only through the small allow-listed bridge in
`preload.js`. On top of that:

- `index.html` carries a Content-Security-Policy that permits only
  same-origin script and style — no remote code, no `eval`.
- Navigation and window-opening are both denied; `http(s)` links are handed
  to the system browser instead.
- A permission handler grants **only** MIDI and denies everything else
  (camera, microphone, geolocation, notifications). Without one, Electron's
  default grants most permissions to `file://` content.
- `read-preset-file` will only read back a path the user chose in the main
  process's own Import dialog, so a compromised renderer cannot ask for an
  arbitrary file.
