// Admin CLI (runs on the server, talks to the SQLite file directly; there is no HTTP admin surface).
//   node src/admin.mjs <command> [args]        env: QREAD_DATA_DIR / QREAD_DB as for the server
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadConfig } from './config.mjs';
import { openDb } from './db.mjs';
import { Service } from './service.mjs';
import { fmtDate } from './util.mjs';
import { parseUpdate, updateFile } from './userapi.mjs';
import { libraryAdapter, decodeText } from './luis/adapters/library.mjs';
import { ensureLuisSchema } from './luis/engine.mjs';

const HELP = `qread admin
  create-user <username> <email> [--password P | --random] [--days N]
  set-password <user> [--password P | --random]
  grant <user> <days>            add days (negative removes); revoke <user> removes membership
  disable <user> | enable <user> | delete-user <user>   (delete-user removes the account and all its cloud data)
  make-codes vip <days> [--count N] [--note T] [--valid-days D]      activation codes (QR-XXXX-XXXX-XXXX)
  make-codes invite [--count N] [--valid-days D] [--days N]          6-digit registration codes (optionally with free days)
  list-users | list-codes [--unused]
  list-diag [--limit N] [--full]       self-check reports sent by the app (failures are always shown)
  add-category <name>
  add-theme --name N [--category C] [--zip F] [--layout F] [--image F] [--author A] [--mode day|night] [--version V] [--desc T] [--id ID]
  set-static <down|qq|browser> <file>
  set-source <name> <file.html> | list-sources      host a 时光源 page at <base>/tsy/<name>.html (sources/<name>/dist/source.html)
  luis-add-book <file.txt> --name N [--author A] [--intro T] [--tags T] [--category C] [--cover URL] [--status S]
                                 路易斯书库 (members): a TXT split into chapters;  luis-list-books | luis-remove-book <id> | luis-cache-clear | set-static browser <file.html>   (browser: the 阅读模式 parser page, served at /static/browser.html)
  set-update <file.json> | set-update --clear | show-update
                                 release for check_update: {"version":"1.0.1","build":2,"notes":"…","url":"https://…","platform":"ios"}
`;

function parseArgs(argv) {
  const pos = [];
  const opt = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const k = a.slice(2);
      const next = argv[i + 1];
      if (next === undefined || next.startsWith('--')) opt[k] = true;
      else {
        opt[k] = next;
        i++;
      }
    } else pos.push(a);
  }
  return { pos, opt };
}

export function run(argv, { cfg = loadConfig(), out = console.log } = {}) {
  const { pos, opt } = parseArgs(argv);
  const [cmd, ...a] = pos;
  const db = openDb(cfg.dbPath);
  const svc = new Service(db, cfg);
  const user = (n) => {
    const u = svc.findUser(n);
    if (!u) throw new Error(`no such user: ${n}`);
    return u;
  };
  const password = () => (opt.password && opt.password !== true ? String(opt.password) : crypto.randomBytes(12).toString('base64url'));
  try {
    switch (cmd) {
      case 'create-user': {
        const pw = password();
        const u = svc.createUser({ username: a[0], email: a[1], password: pw, days: Number(opt.days ?? 0) });
        out(JSON.stringify({ id: u.id, username: u.username, email: u.email, password: opt.password ? '(as given)' : pw }));
        break;
      }
      case 'set-password': {
        const pw = password();
        svc.setPassword(user(a[0]).id, pw);
        out(JSON.stringify({ user: a[0], password: opt.password ? '(as given)' : pw }));
        break;
      }
      case 'grant': {
        const u = user(a[0]);
        out(`vip until ${fmtDate(svc.addDays(u.id, Number(a[1]), 'admin', 'cli'))}`);
        break;
      }
      case 'revoke':
        svc.revokeVip(user(a[0]).id);
        out('revoked');
        break;
      case 'disable':
      case 'enable':
        svc.db.prepare('UPDATE users SET disabled = ? WHERE id = ?').run(cmd === 'disable' ? 1 : 0, user(a[0]).id);
        if (cmd === 'disable') svc.db.prepare('DELETE FROM tokens WHERE user_id = ?').run(user(a[0]).id);
        out(cmd + 'd');
        break;
      case 'delete-user': {
        const u = user(a[0]);
        svc.db.prepare('DELETE FROM reads WHERE user_id = ?').run(u.id);
        svc.db.prepare('DELETE FROM users WHERE id = ?').run(u.id); // tokens, blobs, devices cascade
        out('deleted');
        break;
      }
      case 'make-codes': {
        const kind = a[0];
        const codes = svc.makeCodes({ kind, count: Number(opt.count ?? 1), days: Number(kind === 'vip' ? a[1] : opt.days ?? 0), note: String(opt.note ?? ''), validDays: Number(opt['valid-days'] ?? 0) });
        for (const c of codes) out(c);
        break;
      }
      case 'list-users':
        for (const u of db.prepare('SELECT id, username, email, vip_until, disabled, created_at FROM users ORDER BY id').all()) {
          out(`${u.id}\t${u.username}\t${u.email}\tvip:${fmtDate(u.vip_until) || '-'}\t${u.disabled ? 'disabled' : ''}\tcreated:${fmtDate(u.created_at)}`);
        }
        break;
      case 'list-codes':
        for (const c of db.prepare(`SELECT id, kind, days, note, created_at, valid_until, used_by, used_at FROM codes ${opt.unused ? 'WHERE used_at IS NULL' : ''} ORDER BY id`).all()) {
          out(`${c.id}\t${c.kind}\t${c.days}d\t${c.note}\tcreated:${fmtDate(c.created_at)}\t${c.valid_until ? 'valid-until:' + fmtDate(c.valid_until) : ''}\t${c.used_at ? 'used by ' + c.used_by + ' on ' + fmtDate(c.used_at) : 'unused'}`);
        }
        break;
      case 'list-diag': {
        const rows = db.prepare('SELECT d.id, d.at, d.appid, d.body, u.username FROM diag_reports d JOIN users u ON u.id = d.user_id ORDER BY d.id DESC LIMIT ?').all(Number(opt.limit ?? 5));
        for (const r of rows) {
          const b = JSON.parse(r.body);
          const bad = b.results.filter((x) => !x.ok);
          out(`#${r.id} ${new Date(r.at).toISOString()} ${r.username} ${b.platform}/${b.model} ${b.app} ok:${b.results.length - bad.length} fail:${bad.length}`);
          for (const x of opt.full ? b.results : bad) out(`    ${x.ok ? 'ok  ' : 'FAIL'} ${x.name} ${x.detail}`);
        }
        break;
      }
      case 'add-category': {
        const r = db.prepare('INSERT OR IGNORE INTO categories(name) VALUES (?)').run(a[0]);
        out(`category ${a[0]} id=${r.changes ? r.lastInsertRowid : db.prepare('SELECT id FROM categories WHERE name = ?').get(a[0]).id}`);
        break;
      }
      case 'add-theme': {
        if (!opt.name) throw new Error('--name required');
        const dir = path.join(cfg.dataDir, 'themes', 'files');
        fs.mkdirSync(dir, { recursive: true });
        const id = String(opt.id ?? crypto.randomBytes(8).toString('hex'));
        const put = (f) => {
          if (!f || f === true) return '';
          const name = `${id}-${path.basename(String(f))}`.replace(/[^A-Za-z0-9._\-]/g, '_');
          fs.copyFileSync(String(f), path.join(dir, name));
          return `/public/files/${name}`;
        };
        let cat = null;
        if (opt.category) {
          db.prepare('INSERT OR IGNORE INTO categories(name) VALUES (?)').run(String(opt.category));
          cat = db.prepare('SELECT id FROM categories WHERE name = ?').get(String(opt.category)).id;
        }
        const now = new Date().toISOString();
        db.prepare('INSERT INTO themes(id,name,description,category_id,zip_path,layout_path,image_path,version,author,theme_mode,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)')
          .run(id, String(opt.name), String(opt.desc ?? ''), cat, put(opt.zip), put(opt.layout), put(opt.image), String(opt.version ?? '1.0.0'), String(opt.author ?? ''), String(opt.mode ?? 'day'), now, now);
        out(`theme ${id}`);
        break;
      }
      case 'set-static': {
        if (!['down', 'qq', 'browser'].includes(a[0])) throw new Error('down, qq or browser');
        if (!a[1]) throw new Error('set-static <name> <file>');
        const text = fs.readFileSync(a[1], 'utf8');
        let name = `${a[0]}.json`;
        if (a[0] === 'browser') {
          if (!text.includes('async function getinfo(') || !text.includes('async function chapter(')) throw new Error('not a 浏览器 source page (no getinfo/chapter)');
          name = 'browser.html';
        } else {
          JSON.parse(text);
        }
        fs.mkdirSync(path.join(cfg.dataDir, 'static'), { recursive: true });
        fs.copyFileSync(a[1], path.join(cfg.dataDir, 'static', name));
        out('ok');
        break;
      }
      case 'set-source': {
        // a 时光源 page served at <base>/tsy/<name>.html (sources/<name>/dist/source.html of the repository)
        if (!/^[A-Za-z0-9._-]{1,64}$/.test(a[0] ?? '') || !a[1]) throw new Error('set-source <name> <file.html>');
        const text = fs.readFileSync(a[1], 'utf8');
        if (!/function\s+search\s*\(/.test(text) || !/function\s+chapter\s*\(/.test(text) || !/function\s+content\s*\(/.test(text)) throw new Error('not a 时光源 page (no search/chapter/content)');
        const dir = path.join(cfg.dataDir, 'static', 'tsy');
        fs.mkdirSync(dir, { recursive: true });
        fs.writeFileSync(path.join(dir, `${a[0]}.html`), text);
        out(`${cfg.baseUrl}/tsy/${a[0]}.html`);
        break;
      }
      case 'luis-add-book': {
        if (!a[0] || !opt.name) throw new Error('luis-add-book <file.txt> --name N [--author A] [--intro T] [--tags T] [--category C] [--cover URL] [--status S]');
        ensureLuisSchema(db);
        const lib = libraryAdapter(db);
        const r = lib.add({
          name: String(opt.name),
          author: String(opt.author ?? ''),
          intro: String(opt.intro ?? ''),
          tags: String(opt.tags ?? ''),
          category: String(opt.category ?? ''),
          cover: String(opt.cover ?? ''),
          status: String(opt.status ?? '已完结'),
          text: decodeText(fs.readFileSync(a[0])),
        });
        db.prepare("DELETE FROM luis_cache WHERE key LIKE 'search:%' OR key LIKE 'discoverList:%'").run();
        out(`book ${r.id}: ${opt.name}, ${r.chapters} chapters, ${r.words} chars`);
        break;
      }
      case 'luis-list-books': {
        const rows = libraryAdapter(db).list();
        out(rows.length ? rows.map((b) => `${b.id}\t${b.name}\t${b.author}\t${b.chapters} chapters\t${b.word_count} chars`).join('\n') : '(none)');
        break;
      }
      case 'luis-remove-book': {
        if (!a[0]) throw new Error('luis-remove-book <id>');
        ensureLuisSchema(db);
        const n = libraryAdapter(db).remove(a[0]);
        db.prepare('DELETE FROM luis_cache').run();
        out(n ? 'removed' : 'no such book');
        break;
      }
      case 'luis-cache-clear': {
        ensureLuisSchema(db);
        out(`cleared ${db.prepare('DELETE FROM luis_cache').run().changes} entries`);
        break;
      }
      case 'list-sources': {
        const dir = path.join(cfg.dataDir, 'static', 'tsy');
        const names = fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => f.endsWith('.html')) : [];
        out(names.length ? names.map((f) => `${cfg.baseUrl}/tsy/${f}`).join('\n') : '(none)');
        break;
      }
      case 'set-update': {
        const f = updateFile(cfg.dataDir);
        if (opt.clear) {
          fs.rmSync(f, { force: true });
          out('cleared: check_update answers "no update"');
          break;
        }
        if (!a[0]) throw new Error('set-update <file.json>');
        const rel = parseUpdate(JSON.parse(fs.readFileSync(a[0], 'utf8')));
        fs.mkdirSync(path.dirname(f), { recursive: true });
        fs.writeFileSync(f, JSON.stringify(rel, null, 2));
        out(`update set: ${rel.version || '(no version)'} build ${rel.build}${rel.platform ? ' for ' + rel.platform : ''} -> ${rel.url}`);
        break;
      }
      case 'show-update': {
        const f = updateFile(cfg.dataDir);
        out(fs.existsSync(f) ? fs.readFileSync(f, 'utf8') : '(none)');
        break;
      }
      default:
        out(HELP);
    }
  } finally {
    db.close();
  }
}

const isMain = process.argv[1] && fs.realpathSync(process.argv[1]) === fs.realpathSync(fileURLToPath(import.meta.url));
if (isMain) {
  try {
    run(process.argv.slice(2));
  } catch (e) {
    console.error('error:', e.msg ?? e.message);
    process.exit(1);
  }
}
