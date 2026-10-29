// 路易斯书库: books the owner uploads to the server (TXT split into chapters; `qread-admin luis-add-book`). Members only.
const SCHEMA = `
CREATE TABLE IF NOT EXISTS luis_books (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  author TEXT NOT NULL DEFAULT '',
  intro TEXT NOT NULL DEFAULT '',
  cover TEXT NOT NULL DEFAULT '',
  tags TEXT NOT NULL DEFAULT '',
  category TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT '已完结',
  word_count INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS luis_chapters (
  book_id INTEGER NOT NULL REFERENCES luis_books(id) ON DELETE CASCADE,
  idx INTEGER NOT NULL,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  word_count INTEGER NOT NULL DEFAULT 0,
  is_volume INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (book_id, idx)
);
`;

const HEADING = /^\s*(?:(?:第\s*[0-9０-９零一二三四五六七八九十百千万〇两]+\s*[章节回卷集部篇话話幕]|(?:序章|序言|序|楔子|引子|尾声|尾聲|后记|後記|番外|终章|終章|Chapter\s*\d+|CHAPTER\s*\d+))(?:[\s:：、.．-]+.{0,50}|(?=\s*$))|(?:卷|第[一二三四五六七八九十0-9]+卷)[^\n]{0,30})\s*$/;

/** Text -> chapters: headings start chapters; a text without headings is cut every ~4000 characters. */
export function splitChapters(text) {
  const lines = String(text ?? '').replace(/\r\n?/g, '\n').split('\n');
  const chapters = [];
  let cur = null;
  let preface = [];
  for (const raw of lines) {
    const line = raw.replace(/　/g, ' ').trimEnd();
    if (line.trim().length <= 60 && HEADING.test(line)) {
      if (cur) chapters.push(cur);
      cur = { title: line.trim(), lines: [] };
      continue;
    }
    if (cur) cur.lines.push(line);
    else preface.push(line);
  }
  if (cur) chapters.push(cur);
  const prefaceText = preface.join('\n').trim();
  if (!chapters.length) {
    const body = prefaceText;
    if (!body) return [];
    const parts = [];
    const paras = body.split(/\n+/);
    let buf = [];
    let size = 0;
    for (const p of paras) {
      buf.push(p);
      size += p.length;
      if (size >= 4000) {
        parts.push(buf.join('\n'));
        buf = [];
        size = 0;
      }
    }
    if (buf.length) parts.push(buf.join('\n'));
    return parts.map((c, i) => ({ title: `第${i + 1}部分`, content: c }));
  }
  const out = chapters.map((c) => ({ title: c.title, content: c.lines.join('\n').trim() }));
  if (prefaceText.length > 200) out.unshift({ title: '前言', content: prefaceText });
  // a heading followed by nothing is a volume header
  return out.map((c) => ({ ...c, isVolume: !c.content && /卷/.test(c.title) }));
}

/** Decodes a TXT: BOM / valid UTF-8, else GB18030. */
export function decodeText(buf) {
  if (buf.length >= 3 && buf[0] === 0xef && buf[1] === 0xbb && buf[2] === 0xbf) return buf.subarray(3).toString('utf8');
  if (buf.length >= 2 && buf[0] === 0xff && buf[1] === 0xfe) return new TextDecoder('utf-16le').decode(buf.subarray(2));
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(buf);
  } catch {
    return new TextDecoder('gb18030').decode(buf);
  }
}

export function libraryAdapter(db, { now = Date.now } = {}) {
  db.exec(SCHEMA);
  const row2book = (r) => ({
    id: String(r.id),
    name: r.name,
    author: r.author,
    intro: r.intro,
    cover: r.cover,
    tags: r.tags,
    category: r.category,
    status: r.status,
    wordCount: r.word_count ? `${(r.word_count / 10000).toFixed(1)}万` : '',
    updatedAt: new Date(r.updated_at).toISOString().slice(0, 19).replace('T', ' '),
    latestChapter: db.prepare('SELECT title FROM luis_chapters WHERE book_id = ? AND is_volume = 0 ORDER BY idx DESC LIMIT 1').get(r.id)?.title ?? '',
  });

  return {
    name: '路易斯书库',
    tabs: ['小说'],
    tier: 'svip',

    /** Adds a book from text; answers its id. */
    add({ name, author = '', intro = '', cover = '', tags = '', category = '', status = '已完结', text }) {
      const chapters = splitChapters(text);
      if (!chapters.length) throw new Error('文本为空');
      const words = chapters.reduce((n, c) => n + c.content.replace(/\s/g, '').length, 0);
      const t = now();
      const id = Number(db.prepare('INSERT INTO luis_books(name, author, intro, cover, tags, category, status, word_count, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)')
        .run(name, author, intro, cover, tags, category, status, words, t, t).lastInsertRowid);
      const ins = db.prepare('INSERT INTO luis_chapters(book_id, idx, title, content, word_count, is_volume) VALUES (?,?,?,?,?,?)');
      chapters.forEach((c, i) => ins.run(id, i, c.title, c.content, c.content.replace(/\s/g, '').length, c.isVolume ? 1 : 0));
      return { id, chapters: chapters.length, words };
    },

    remove(id) {
      db.prepare('DELETE FROM luis_chapters WHERE book_id = ?').run(Number(id));
      return Number(db.prepare('DELETE FROM luis_books WHERE id = ?').run(Number(id)).changes);
    },

    list() {
      return db.prepare('SELECT b.*, (SELECT COUNT(*) FROM luis_chapters c WHERE c.book_id = b.id) AS chapters FROM luis_books b ORDER BY id').all();
    },

    async search(key) {
      const like = `%${key.replace(/[%_]/g, '')}%`;
      return db.prepare('SELECT * FROM luis_books WHERE name LIKE ? OR author LIKE ? OR tags LIKE ? ORDER BY updated_at DESC LIMIT 50').all(like, like, like).map(row2book);
    },

    async detail(id) {
      const r = db.prepare('SELECT * FROM luis_books WHERE id = ?').get(Number(id));
      return r ? { ...row2book(r), copyright: '路易斯书库 · 仅限本站会员阅读' } : null;
    },

    async catalog(id) {
      return db.prepare('SELECT idx, title, word_count, is_volume FROM luis_chapters WHERE book_id = ? ORDER BY idx').all(Number(id))
        .map((c) => ({ id: `${id}:${c.idx}`, title: c.title, wordCount: c.word_count, isVolume: !!c.is_volume }));
    },

    async content(itemId) {
      const [book, idx] = String(itemId).split(':');
      const c = db.prepare('SELECT title, content FROM luis_chapters WHERE book_id = ? AND idx = ?').get(Number(book), Number(idx));
      return c ? { title: c.title, content: c.content } : null;
    },

    async discover() {
      return [{ title: '最近添加', key: 'recent', width: 1 }, { title: '全部书籍', key: 'all', width: 1 }];
    },

    async discoverList(key, page) {
      const order = key === 'recent' ? 'created_at DESC' : 'name';
      return db.prepare(`SELECT * FROM luis_books ORDER BY ${order} LIMIT 20 OFFSET ?`).all((page - 1) * 20).map(row2book);
    },
  };
}
