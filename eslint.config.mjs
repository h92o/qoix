/* Flat ESLint config. The browser sources are plain scripts that share
   module-level singletons through globals, which is why every engine is
   declared here rather than imported. */

const browserGlobals = {
  window: 'readonly', document: 'readonly', navigator: 'readonly',
  console: 'readonly', localStorage: 'readonly', performance: 'readonly',
  setTimeout: 'readonly', clearTimeout: 'readonly',
  setInterval: 'readonly', clearInterval: 'readonly',
  requestAnimationFrame: 'readonly', cancelAnimationFrame: 'readonly',
  Blob: 'readonly', URL: 'readonly', FileReader: 'readonly',
  alert: 'readonly', prompt: 'readonly', confirm: 'readonly',
  AudioContext: 'readonly', OfflineAudioContext: 'readonly',
  ResizeObserver: 'readonly', module: 'writable',
};

// The engines, as they see each other at runtime.
const qoixGlobals = Object.fromEntries(
  ['Synth','UI','Presets','FMEngine','WTEngine','ModMatrix','RandomGen',
   'Renderer','Recorder','SpectralFFT','Microtonal'].map(n => [n, 'readonly'])
);

const nodeGlobals = {
  require: 'readonly', module: 'writable', process: 'readonly',
  __dirname: 'readonly', global: 'writable', Buffer: 'readonly',
  console: 'readonly', setTimeout: 'readonly', clearTimeout: 'readonly',
};

const rules = {
  'no-undef': 'error',
  'no-unused-vars': ['warn', { args: 'none', caughtErrors: 'none', varsIgnorePattern: '^_' }],
  // builtinGlobals off: each engine file legitimately declares the same
  // name this config lists as a shared global.
  'no-redeclare': ['error', { builtinGlobals: false }],
  'no-dupe-keys': 'error',
  'no-dupe-args': 'error',
  'no-unreachable': 'error',
  'no-const-assign': 'error',
  'no-self-assign': 'error',
  'no-cond-assign': 'error',
  'no-fallthrough': 'error',
  'no-func-assign': 'error',
  'use-isnan': 'error',
  'valid-typeof': 'error',
  eqeqeq: ['warn', 'smart'],
};

export default [
  { ignores: ['node_modules/**', 'dist/**', 'build/**', 'qoix-standalone.html'] },
  {
    files: ['js/**/*.js'],
    languageOptions: {
      ecmaVersion: 2022, sourceType: 'script',
      globals: { ...browserGlobals, ...qoixGlobals },
    },
    rules,
  },
  {
    files: ['main.js', 'preload.js', 'tools/**/*.js', 'test/**/*.js'],
    languageOptions: {
      ecmaVersion: 2022, sourceType: 'script',
      globals: { ...nodeGlobals, ...browserGlobals, ...qoixGlobals },
    },
    rules,
  },
  {
    files: ['eslint.config.mjs'],
    languageOptions: { ecmaVersion: 2022, sourceType: 'module' },
    rules,
  },
];
