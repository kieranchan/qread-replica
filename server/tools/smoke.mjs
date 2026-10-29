// End-to-end smoke test against a deployed server. Admin actions (invite/vip codes, cleanup) go through
// the qread-admin wrapper over SSH, so no secret is printed or stored.
//   QREAD_SSH_TARGET=user@host node tools/smoke.mjs https://qread.forfine.me [ssh-target] [ssh-key]
import { execFileSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const base = (process.argv[2] ?? 'http://127.0.0.1:8920').replace(/\/+$/, '');
const target = process.argv[3] ?? process.env.QREAD_SSH_TARGET;
if (!target) throw new Error('give the ssh target as argv[3] or set QREAD_SSH_TARGET (user@host)');
const key = process.argv[4] ?? path.join(os.homedir(), '.ssh', 'id_ed25519_td2');
const admin = (...args) => execFileSync('ssh', ['-i', key, '-o', 'BatchMode=yes', '-o', 'LogLevel=ERROR', target, 'qread-admin', ...args], { encoding: 'utf8' }).trim();
const post = async (p, body) => (await fetch(base + p, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })).json();
let n = 0;
const check = (name, cond, extra = '') => {
  n++;
  console.log(`${cond ? 'ok  ' : 'FAIL'} ${name}${cond ? '' : ' ' + extra}`);
  if (!cond) process.exitCode = 1;
};

const name = 'smoke' + crypto.randomBytes(4).toString('hex');
const pw = crypto.randomBytes(9).toString('base64url');
try {
  check('healthz', (await (await fetch(base + '/healthz')).json()).ok === true);
  const browserPage = await fetch(base + '/static/browser.html');
  check('browser page (阅读模式 parser) is served', browserPage.status === 200);
  try {
    // the served copy should be the app's built-in page (node tools/browser_page.mjs + qread-admin set-static browser after edits)
    const dart = fs.readFileSync(new URL('../../app/lib/util/source/browser_source_page.dart', import.meta.url), 'utf8');
    const builtIn = dart.slice(dart.indexOf("r'''") + 4, dart.indexOf("'''", dart.indexOf("r'''") + 4)).trim();
    check('browser page is the current built-in one (else re-export and set-static browser)', (await browserPage.text()).trim() === builtIn);
  } catch (e) {
    check('browser page compared with the app source', false, String(e));
  }
  const invite = admin('make-codes', 'invite', '--valid-days', '1');
  check('register with invite', (await post('/register', { username: name, email: `${name}@example.invalid`, password: pw, code: invite })).code === 0);
  check('register again with the same invite is refused', (await post('/register', { username: name + 'x', email: `${name}x@example.invalid`, password: pw, code: invite })).code !== 0);
  const login = await post('/login', { username: name, password: pw, platform: 'smoke', model: 'node', appid: 'smoke-1' });
  check('login', login.code === 0 && typeof login.data?.id === 'string' && login.data.vip === '' && login.data.isvip === false, JSON.stringify(login));
  const t = { tockenid: login.data.id, appid: 'smoke-1' };
  check('cloud closed for non-members', (await post('/getEtag', t)).code === -3);
  const vipCode = admin('make-codes', 'vip', '7');
  const red = await post('/redeem', { ...t, code: vipCode });
  check('redeem activation code', red.code === 0, JSON.stringify(red));
  check('canOpenCloud', (await post('/canOpenCloud', t)).code === 0);
  check('getUserInfo isvip', (await post('/getUserInfo', t)).data?.isvip === true);
  const body = JSON.stringify([{ bookUrl: 'smoke', name: '冒烟' }]);
  const boundary = '----smoke';
  const mp = `--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="b.json"\r\n\r\n${body}\r\n--${boundary}--\r\n`;
  const up = await (await fetch(`${base}/setItemJsonFile?${new URLSearchParams({ ...t, item: 'books', t: String(Date.now()) })}`, { method: 'POST', headers: { 'Content-Type': `multipart/form-data; boundary=${boundary}` }, body: mp })).json();
  check('upload bookshelf', up.code === 0, JSON.stringify(up));
  check('etag = md5', (await post('/getEtag', t)).data === crypto.createHash('md5').update(body).digest('hex'));
  check('list round trip', (await post('/getBooks', t)).data === body);
  // reading position (the app's 进度同步确认 reads it back with getpos)
  check('getpos nothing stored', (await post('/getpos', { ...t, book: 'smoke-book' })).code === -5);
  check('autopos', (await post('/autopos', { ...t, st: '0', book: 'smoke-book', index: 3, pos: 0.25, title: '第四章', bid: '', t: Date.now() })).code === 0);
  const pos = await post('/getpos', { ...t, book: 'smoke-book' });
  check('getpos record', pos.code === 0 && pos.data?.index === 3 && pos.data?.pos === 0.25 && pos.data?.appid === 'smoke-1', JSON.stringify(pos));
  // the WebDAV book repository: OPTIONS is open, a session token opens the user's store
  check('dav options', (await fetch(`${base}/dav/`, { method: 'OPTIONS' })).status === 200);
  check('dav needs auth', (await fetch(`${base}/dav/`, { method: 'PROPFIND', headers: { Depth: '1' } })).status === 401);
  const davAuth = { Authorization: 'Basic ' + Buffer.from(`${name}:${t.tockenid}`).toString('base64') };
  check('dav propfind with token', (await fetch(`${base}/dav/`, { method: 'PROPFIND', headers: { ...davAuth, Depth: '1' } })).status === 207);
  check('dav mkcol + put + get', await (async () => {
    await fetch(`${base}/dav/books`, { method: 'MKCOL', headers: davAuth });
    const put = await fetch(`${base}/dav/books/smoke.txt`, { method: 'PUT', headers: davAuth, body: 'smoke' });
    const get = await fetch(`${base}/dav/books/smoke.txt`, { headers: davAuth });
    return [201, 204].includes(put.status) && (await get.text()) === 'smoke';
  })());
  // device backup (书架备份): openAuto hands out the upload url, the app PUTs its shelf, 备份导入 finds it through getBookSelf
  const open = await post('/openAuto', { ...t, st: '0' });
  check('openAuto upload url', open.code === 0 && /\/autobackup\/[0-9a-f]{32}$/.test(open.data ?? ''), JSON.stringify(open));
  const put = await fetch(open.data, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body });
  check('backup upload', put.status === 200);
  const where = await post('/getBookSelf', { ...t, appid: t.appid });
  check('getBookSelf download', where.code === 0 && (await (await fetch(where.data)).text()) === body, JSON.stringify(where));
  check('会员中心 page', (await fetch(`${base}/vip?tockenid=${t.tockenid}`)).status === 200);
  check('theme categories', (await (await fetch(base + '/public/categories')).json()).code === 200);
  check('logout', (await post('/logout', t)).code === 0);
  check('token dead after logout', (await post('/getUserInfo', t)).code === -2);
} finally {
  try {
    admin('delete-user', name);
    console.log('cleanup: smoke user deleted');
  } catch (e) {
    console.log('cleanup failed for', name);
    process.exitCode = 1;
  }
}
console.log(`${n} checks`);
