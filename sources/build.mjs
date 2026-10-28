#!/usr/bin/env node
// Builds a source: inlines sdk/qyd-sdk.js into <name>/source.src.html (at the `<!-- @sdk -->` marker) and writes
//   <name>/dist/source.html          the page (import it as the source's html, or host it)
//   <name>/dist/source.json          the import file of the app with the page inline (`html` = the page code)
//   <name>/dist/source.hosted.json   the same with `html` = --html-url (when given)
// Usage: node build.mjs <name> [--html-url https://host/path/source.html]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));

export function build(name, { htmlUrl = '' } = {}) {
  const dir = path.join(HERE, name);
  const meta = JSON.parse(fs.readFileSync(path.join(dir, 'source.meta.json'), 'utf8'));
  const sdk = fs.readFileSync(path.join(HERE, 'sdk', 'qyd-sdk.js'), 'utf8');
  const src = fs.readFileSync(path.join(dir, 'source.src.html'), 'utf8');
  if (!src.includes('<!-- @sdk -->')) throw new Error(`${name}/source.src.html has no <!-- @sdk --> marker`);
  const html = src.replace('<!-- @sdk -->', `<script>\n${sdk}\n</script>`);
  const out = path.join(dir, 'dist');
  fs.mkdirSync(out, { recursive: true });
  fs.writeFileSync(path.join(out, 'source.html'), html);
  const entry = (h) => [{ ...meta, html: h }];
  fs.writeFileSync(path.join(out, 'source.json'), JSON.stringify(entry(html)));
  if (htmlUrl) fs.writeFileSync(path.join(out, 'source.hosted.json'), JSON.stringify(entry(htmlUrl), null, 2));
  return { html, out };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [name, ...rest] = process.argv.slice(2);
  if (!name) {
    console.error('usage: node build.mjs <name> [--html-url URL]');
    process.exit(2);
  }
  const i = rest.indexOf('--html-url');
  const r = build(name, { htmlUrl: i >= 0 ? rest[i + 1] : '' });
  console.log(`built ${name}: ${r.out} (${r.html.length} chars)`);
}
