// Theme plaza: GET /public/themes, /public/themes/:id, /public/categories (contract in docs/API.md §3).
// Replies use HTTP-style codes: {code: 200, data} on success, {code: 4xx, message} on failure.

export function createThemes(db) {
  const catOf = (id) => (id == null ? null : db.prepare('SELECT id, name FROM categories WHERE id = ?').get(id) ?? null);
  const item = (r) => ({
    id: r.id,
    name: r.name,
    description: r.description,
    category_id: r.category_id,
    category: catOf(r.category_id),
    zip_path: r.zip_path,
    layout_path: r.layout_path,
    image_path: r.image_path,
    version: r.version,
    author: r.author,
    theme_mode: r.theme_mode,
    created_at: r.created_at,
    updated_at: r.updated_at,
  });

  return {
    categories() {
      return { code: 200, data: db.prepare('SELECT id, name FROM categories ORDER BY id').all() };
    },
    list({ page, limit, category_id }) {
      const pg = Math.max(1, Number.parseInt(page, 10) || 1);
      const lim = Math.min(100, Math.max(1, Number.parseInt(limit, 10) || 20));
      const cat = category_id === undefined || category_id === '' ? null : Number.parseInt(category_id, 10);
      const where = cat == null || Number.isNaN(cat) ? '' : 'WHERE category_id = ?';
      const args = where ? [cat] : [];
      const total = db.prepare(`SELECT COUNT(*) AS n FROM themes ${where}`).get(...args).n;
      const rows = db.prepare(`SELECT * FROM themes ${where} ORDER BY created_at DESC, id LIMIT ? OFFSET ?`).all(...args, lim, (pg - 1) * lim);
      return { code: 200, data: { items: rows.map(item), total, page: pg, limit: lim, max_page: Math.max(1, Math.ceil(total / lim)) } };
    },
    get(id) {
      const r = db.prepare('SELECT * FROM themes WHERE id = ?').get(id);
      return r ? { code: 200, data: item(r) } : { code: 404, message: 'theme not found' };
    },
  };
}
