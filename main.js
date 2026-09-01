/* ============================================================
   QOIX Synthesizer — Electron Main Process
   ============================================================ */

'use strict';

const { app, BrowserWindow, Menu, shell, ipcMain, dialog, session } = require('electron');
const path  = require('path');
const fs    = require('fs');
const isDev = process.argv.includes('--dev');

// ── Window bounds persistence ──────────────────────────────
// Remember where the window was, so the app does not reopen at 1440x900
// in the top-left corner every single launch.
const STATE_FILE = () => path.join(app.getPath('userData'), 'window-state.json');

function loadWindowState() {
  try {
    const st = JSON.parse(fs.readFileSync(STATE_FILE(), 'utf8'));
    if (Number.isFinite(st.width) && Number.isFinite(st.height)) return st;
  } catch (e) { /* first run, or unreadable — fall through to defaults */ }
  return null;
}

function saveWindowState(win) {
  if (!win || win.isDestroyed()) return;
  try {
    const bounds = win.isMaximized() || win.isFullScreen()
      ? (win.__normalBounds || win.getBounds())
      : win.getBounds();
    fs.writeFileSync(STATE_FILE(), JSON.stringify({
      ...bounds,
      maximized: win.isMaximized(),
    }), 'utf8');
  } catch (e) { /* not worth bothering the user about */ }
}

// ── Single instance lock ───────────────────────────────────
const gotLock = app.requestSingleInstanceLock();
if (!gotLock) { app.quit(); process.exit(0); }

let mainWindow = null;

// ── Create window ──────────────────────────────────────────
function createWindow() {
  const saved = loadWindowState();

  mainWindow = new BrowserWindow({
    width:           saved ? saved.width  : 1440,
    height:          saved ? saved.height : 900,
    ...(saved && Number.isFinite(saved.x) ? { x: saved.x, y: saved.y } : {}),
    minWidth:        800,
    minHeight:       600,
    title:           'QOIX Synthesizer',
    backgroundColor: '#0c0d11',
    titleBarStyle:   process.platform === 'darwin' ? 'hiddenInset' : 'default',
    trafficLightPosition: { x: 16, y: 16 },
    show:            false,   // show after ready-to-show
    icon:            path.join(__dirname, 'assets', getIconName()),
    webPreferences: {
      preload:              path.join(__dirname, 'preload.js'),
      contextIsolation:     true,
      nodeIntegration:      false,
      sandbox:              false,   // the preload needs ipcRenderer
      // Web Audio: allow audio autoplay without user gesture in desktop
      autoplayPolicy:       'no-user-gesture-required',
      // 'experimentalFeatures' was set here for Web MIDI, which it does
      // not actually gate — MIDI is granted by the permission handler
      // below. Leaving it on exposed unrelated unstable web platform
      // features for no benefit.
      spellcheck:           false,
      backgroundThrottling: false,   // keep audio steady when unfocused
    },
  });

  // Absolute path: loadFile() resolves relative to the process working
  // directory, so launching from anywhere but the app folder failed.
  mainWindow.loadFile(path.join(__dirname, 'index.html'));

  // Show once fully rendered (no white flash)
  mainWindow.once('ready-to-show', () => {
    if (saved && saved.maximized) mainWindow.maximize();
    mainWindow.show();
    if (isDev) mainWindow.webContents.openDevTools({ mode: 'detach' });
  });

  // Track the un-maximized geometry so restoring lands where you left it.
  const remember = () => {
    if (!mainWindow.isMaximized() && !mainWindow.isFullScreen()) {
      mainWindow.__normalBounds = mainWindow.getBounds();
    }
  };
  mainWindow.on('resize', remember);
  mainWindow.on('move', remember);
  mainWindow.on('close', () => saveWindowState(mainWindow));

  // ── Navigation guards ────────────────────────────────────
  // Nothing in this app should ever navigate or open a window. Anything
  // that tries is either a bug or hostile; send external links to the
  // system browser instead.
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (/^https?:/.test(url)) shell.openExternal(url);
    return { action: 'deny' };
  });
  mainWindow.webContents.on('will-navigate', (event, url) => {
    if (url !== mainWindow.webContents.getURL()) {
      event.preventDefault();
      if (/^https?:/.test(url)) shell.openExternal(url);
    }
  });
  mainWindow.webContents.on('render-process-gone', (_e, details) => {
    console.error('[QOIX] Renderer process gone:', details.reason);
  });

  mainWindow.on('closed', () => { mainWindow = null; });
}

// ── Permissions ────────────────────────────────────────────
// Allow only MIDI; deny camera, microphone, geolocation, notifications
// and everything else outright. Without a handler Electron's default
// silently grants most permissions to file:// content.
function applyPermissionPolicy() {
  const ALLOWED = new Set(['midi', 'midiSysex']);
  session.defaultSession.setPermissionRequestHandler((_wc, permission, callback) => {
    callback(ALLOWED.has(permission));
  });
  session.defaultSession.setPermissionCheckHandler((_wc, permission) => ALLOWED.has(permission));
}

function getIconName() {
  if (process.platform === 'darwin')  return 'icon.icns';
  if (process.platform === 'win32')   return 'icon.ico';
  return 'icon.png';
}

// ── Second instance → focus existing window ───────────────
app.on('second-instance', () => {
  if (mainWindow) {
    if (mainWindow.isMinimized()) mainWindow.restore();
    mainWindow.focus();
  }
});

// ── App menu ───────────────────────────────────────────────
function buildMenu() {
  const isMac = process.platform === 'darwin';

  const template = [
    // App menu (macOS only)
    ...(isMac ? [{
      label: app.name,
      submenu: [
        { role: 'about' },
        { type: 'separator' },
        { role: 'services' },
        { type: 'separator' },
        { role: 'hide' },
        { role: 'hideOthers' },
        { role: 'unhide' },
        { type: 'separator' },
        { role: 'quit' },
      ],
    }] : []),

    // File
    {
      label: 'File',
      submenu: [
        {
          label: 'Export Preset…',
          accelerator: 'CmdOrCtrl+S',
          click: () => mainWindow?.webContents.send('menu:export-preset'),
        },
        {
          label: 'Import Preset…',
          accelerator: 'CmdOrCtrl+O',
          click: async () => {
            const { canceled, filePaths } = await dialog.showOpenDialog(mainWindow, {
              title:      'Import QOIX Preset',
              filters:    [{ name: 'QOIX Preset', extensions: ['qoix', 'json'] }],
              properties: ['openFile'],
            });
            if (!canceled && filePaths[0]) {
              allowedReadPaths.add(filePaths[0]);
              mainWindow?.webContents.send('menu:import-preset', filePaths[0]);
            }
          },
        },
        { type: 'separator' },
        isMac ? { role: 'close' } : { role: 'quit' },
      ],
    },

    // Edit
    {
      label: 'Edit',
      submenu: [
        { role: 'undo' },
        { role: 'redo' },
        { type: 'separator' },
        { role: 'cut' },
        { role: 'copy' },
        { role: 'paste' },
        { role: 'selectAll' },
      ],
    },

    // Synth
    {
      label: 'Synth',
      submenu: [
        {
          label: 'Panic (All Notes Off)',
          accelerator: 'CmdOrCtrl+.',
          click: () => mainWindow?.webContents.send('menu:panic'),
        },
        { type: 'separator' },
        {
          label: 'Octave Up',
          accelerator: 'CmdOrCtrl+Up',
          click: () => mainWindow?.webContents.send('menu:octave-up'),
        },
        {
          label: 'Octave Down',
          accelerator: 'CmdOrCtrl+Down',
          click: () => mainWindow?.webContents.send('menu:octave-down'),
        },
        { type: 'separator' },
        {
          label:        'Start Random Generator',
          accelerator:  'CmdOrCtrl+G',
          click:        () => mainWindow?.webContents.send('menu:rand-start'),
        },
        {
          label:        'Stop Random Generator',
          accelerator:  'CmdOrCtrl+Shift+G',
          click:        () => mainWindow?.webContents.send('menu:rand-stop'),
        },
      ],
    },

    // View
    {
      label: 'View',
      submenu: [
        { role: 'reload' },
        { role: 'forceReload' },
        { type: 'separator' },
        { role: 'resetZoom' },
        { role: 'zoomIn' },
        { role: 'zoomOut' },
        { type: 'separator' },
        { role: 'togglefullscreen' },
        ...(isDev ? [{ type: 'separator' }, { role: 'toggleDevTools' }] : []),
      ],
    },

    // Help
    {
      role: 'help',
      submenu: [
        {
          label: 'QOIX Website',
          click: () => shell.openExternal('https://qoix.app'),
        },
        {
          label: 'Keyboard Shortcuts',
          accelerator: 'CmdOrCtrl+/',
          click: () => mainWindow?.webContents.send('menu:show-shortcuts'),
        },
        { type: 'separator' },
        {
          label: 'About QOIX',
          click: () => dialog.showMessageBox(mainWindow, {
            type:    'info',
            title:   'QOIX Synthesizer',
            message: 'QOIX Synthesizer',
            detail:  `Version ${app.getVersion()}\n\nFM Synthesis · Wavetable · Oxford Harmonic\nMod Matrix · Random Generator\n\nBuilt with Web Audio API + Electron`,
            icon:    path.join(__dirname, 'assets', getIconName()),
          }),
        },
      ],
    },
  ];

  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

// ── IPC handlers ───────────────────────────────────────────

// Only paths the user picked in a main-process dialog may be read back.
// Otherwise a compromised renderer could ask for any file on disk.
const allowedReadPaths = new Set();

// Renderer → Main: save preset file
ipcMain.handle('save-preset-file', async (event, payload) => {
  const name = String((payload && payload.name) || 'preset');
  const data = payload && payload.data;
  if (!data || typeof data !== 'object') return { ok: false, error: 'Nothing to save' };
  try {
    const { canceled, filePath } = await dialog.showSaveDialog(mainWindow, {
      title:       'Save QOIX Preset',
      defaultPath: `${name.replace(/[^a-z0-9]/gi, '_') || 'preset'}.qoix`,
      filters:     [{ name: 'QOIX Preset', extensions: ['qoix'] }],
    });
    if (canceled || !filePath) return { ok: false };
    fs.writeFileSync(filePath, JSON.stringify(data, null, 2), 'utf8');
    return { ok: true, filePath };
  } catch (e) {
    // Previously an unwritable location threw inside the handler and the
    // renderer's await rejected with an opaque IPC error.
    return { ok: false, error: e.message };
  }
});

// Renderer → Main: read preset file
ipcMain.handle('read-preset-file', async (event, filePath) => {
  if (typeof filePath !== 'string' || !allowedReadPaths.has(filePath)) {
    return { ok: false, error: 'That file was not opened through the Import dialog' };
  }
  try {
    const raw = fs.readFileSync(filePath, 'utf8');
    const data = JSON.parse(raw);
    if (!data || typeof data !== 'object' || Array.isArray(data)) {
      return { ok: false, error: 'Not a QOIX preset file' };
    }
    return { ok: true, data };
  } catch (e) {
    return { ok: false, error: e.message };
  }
});

// ── Lifecycle ──────────────────────────────────────────────
app.whenReady().then(() => {
  applyPermissionPolicy();
  buildMenu();
  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

// Belt and braces: refuse to attach a preload or enable Node in any
// web content this app did not create itself.
app.on('web-contents-created', (_event, contents) => {
  contents.on('will-attach-webview', (event, webPreferences) => {
    delete webPreferences.preload;
    webPreferences.nodeIntegration = false;
    event.preventDefault();
  });
});
