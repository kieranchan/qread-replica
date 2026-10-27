// Consistent online backup of the SQLite file (VACUUM INTO), keeps the newest N copies.
//   node src/backup.mjs [keep=14]      env: QREAD_DATA_DIR / QREAD_DB
import fs from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { loadConfig } from './config.mjs';

const cfg = loadConfig();
const keep = Number(process.argv[2] ?? 14);
const dir = path.join(cfg.dataDir, 'backups');
fs.mkdirSync(dir, { recursive: true });
const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\..*/, '').replace('T', '-');
const out = path.join(dir, `qread-${stamp}.db`);
const db = new DatabaseSync(cfg.dbPath);
db.exec(`VACUUM INTO '${out.replace(/'/g, "''")}'`);
db.close();
const files = fs.readdirSync(dir).filter((f) => /^qread-.*\.db$/.test(f)).sort();
for (const f of files.slice(0, Math.max(0, files.length - keep))) fs.unlinkSync(path.join(dir, f));
console.log(JSON.stringify({ backup: out, kept: Math.min(files.length, keep) }));
