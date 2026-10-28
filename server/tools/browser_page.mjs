// Writes the app's built-in 「浏览器」 时光源 page (app/lib/util/source/browser_source_page.dart) out as a file, ready for
// `node src/admin.mjs set-static browser <file>` on the server (served at /static/browser.html; the app prefers it over its
// built-in copy, so the parser can be changed without a new build).
//
//   node tools/browser_page.mjs [out.html]      (default: deploy/browser.html, git-ignored)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const dart = fs.readFileSync(path.join(here, '..', '..', 'app', 'lib', 'util', 'source', 'browser_source_page.dart'), 'utf8');
const start = dart.indexOf("r'''") + 4;
const end = dart.indexOf("'''", start);
if (start < 4 || end < 0) throw new Error('page not found in browser_source_page.dart');
const page = dart.slice(start, end);
if (!page.includes('async function getinfo(')) throw new Error('not the browser page');
const out = process.argv[2] || path.join(here, '..', 'deploy', 'browser.html');
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, page);
console.log(`${out} (${page.length} chars)`);
