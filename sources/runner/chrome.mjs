// Launches a headless Chromium-based browser with the DevTools protocol enabled.
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const CANDIDATES = [
  process.env.QYD_CHROME,
  'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
  'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
  path.join(process.env.LOCALAPPDATA ?? '', 'Google', 'Chrome', 'Application', 'chrome.exe'),
  'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
  'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
  '/usr/bin/google-chrome',
  '/usr/bin/chromium',
  '/usr/bin/chromium-browser',
  '/usr/bin/microsoft-edge',
];

/** The first installed browser (QYD_CHROME wins), or null. */
export function findChrome() {
  for (const c of CANDIDATES) {
    if (c && fs.existsSync(c)) return c;
  }
  return null;
}

/**
 * Starts the browser with a fresh profile and resolves `{ wsUrl, kill }` once DevTools listens.
 * The profile directory is deleted by kill().
 */
export function launchChrome({ executable = findChrome(), headless = true, args = [], timeoutMs = 20000 } = {}) {
  if (!executable) throw new Error('no Chrome/Edge found; set QYD_CHROME=<path to chrome.exe>');
  const userDataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'qyd-runner-'));
  const argv = [
    '--remote-debugging-port=0',
    '--remote-allow-origins=*',
    `--user-data-dir=${userDataDir}`,
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-background-networking',
    '--disable-component-update',
    '--disable-sync',
    '--disable-translate',
    '--disable-features=Translate,OptimizationHints,MediaRouter',
    '--mute-audio',
    '--window-size=1000,800',
    ...(headless ? ['--headless=new', '--disable-gpu'] : []),
    ...args,
    'about:blank',
  ];
  const child = spawn(executable, argv, { stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true });
  let stderr = '';
  const kill = () => {
    try {
      child.kill();
    } catch {}
    setTimeout(() => fs.rm(userDataDir, { recursive: true, force: true }, () => {}), 500);
  };
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      kill();
      reject(new Error(`browser did not start within ${timeoutMs} ms\n${stderr.slice(-2000)}`));
    }, timeoutMs);
    child.stderr.on('data', (d) => {
      stderr += d.toString();
      const m = stderr.match(/DevTools listening on (ws:\/\/[^\s]+)/);
      if (m) {
        clearTimeout(timer);
        resolve({ wsUrl: m[1], kill, process: child, userDataDir, executable });
      }
    });
    child.on('exit', (code) => {
      clearTimeout(timer);
      reject(new Error(`browser exited with code ${code}\n${stderr.slice(-2000)}`));
    });
    child.on('error', (e) => {
      clearTimeout(timer);
      reject(e);
    });
  });
}
