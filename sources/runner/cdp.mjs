// Minimal Chrome DevTools Protocol client over the global WebSocket (Node >= 22). No dependencies.
export class CDP {
  #ws;
  #next = 1;
  #pending = new Map();
  #listeners = new Map();

  static connect(wsUrl, { timeoutMs = 15000 } = {}) {
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(wsUrl);
      const timer = setTimeout(() => reject(new Error(`CDP connect timeout: ${wsUrl}`)), timeoutMs);
      ws.addEventListener('open', () => {
        clearTimeout(timer);
        resolve(new CDP(ws));
      });
      ws.addEventListener('error', (e) => {
        clearTimeout(timer);
        reject(new Error(`CDP connect failed: ${e.message ?? e}`));
      });
    });
  }

  constructor(ws) {
    this.#ws = ws;
    ws.addEventListener('message', (ev) => this.#onMessage(String(ev.data)));
    ws.addEventListener('close', () => {
      for (const p of this.#pending.values()) p.reject(new Error('CDP connection closed'));
      this.#pending.clear();
    });
  }

  #onMessage(text) {
    let msg;
    try {
      msg = JSON.parse(text);
    } catch {
      return;
    }
    if (msg.id !== undefined) {
      const p = this.#pending.get(msg.id);
      if (!p) return;
      this.#pending.delete(msg.id);
      if (msg.error) p.reject(Object.assign(new Error(`${p.method}: ${msg.error.message}`), { code: msg.error.code, data: msg.error.data }));
      else p.resolve(msg.result ?? {});
      return;
    }
    if (msg.method) {
      const key = msg.sessionId ? `${msg.sessionId}:${msg.method}` : msg.method;
      for (const k of [key, msg.method, '*']) {
        const list = this.#listeners.get(k);
        if (!list) continue;
        for (const fn of [...list]) {
          try {
            fn(msg.params ?? {}, msg);
          } catch (e) {
            console.error('CDP listener error', e);
          }
        }
      }
    }
  }

  /** Sends a command; `sessionId` targets an attached (flattened) session. */
  send(method, params = {}, sessionId) {
    const id = this.#next++;
    return new Promise((resolve, reject) => {
      this.#pending.set(id, { resolve, reject, method });
      const msg = { id, method, params };
      if (sessionId) msg.sessionId = sessionId;
      this.#ws.send(JSON.stringify(msg));
    });
  }

  /** Listens to an event (optionally of one session); returns the unsubscribe function. */
  on(method, fn, sessionId) {
    const key = sessionId ? `${sessionId}:${method}` : method;
    if (!this.#listeners.has(key)) this.#listeners.set(key, new Set());
    this.#listeners.get(key).add(fn);
    return () => this.#listeners.get(key)?.delete(fn);
  }

  /** Resolves with the first event (of the session) whose params satisfy `test`. */
  waitFor(method, { sessionId, test = () => true, timeoutMs = 30000 } = {}) {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        off();
        reject(new Error(`timeout waiting for ${method}`));
      }, timeoutMs);
      const off = this.on(method, (params) => {
        if (!test(params)) return;
        clearTimeout(timer);
        off();
        resolve(params);
      }, sessionId);
    });
  }

  close() {
    try {
      this.#ws.close();
    } catch {}
  }
}

/** A flattened target session: send / on scoped to one page target. */
export class Session {
  constructor(cdp, sessionId, targetId) {
    this.cdp = cdp;
    this.id = sessionId;
    this.targetId = targetId;
  }

  send(method, params) {
    return this.cdp.send(method, params, this.id);
  }

  on(method, fn) {
    return this.cdp.on(method, fn, this.id);
  }

  waitFor(method, opts = {}) {
    return this.cdp.waitFor(method, { ...opts, sessionId: this.id });
  }

  /** Evaluates `expression` in the page; promises are awaited, values come back by value. */
  async evaluate(expression, { awaitPromise = true, timeoutMs } = {}) {
    const p = this.send('Runtime.evaluate', { expression, awaitPromise, returnByValue: true, userGesture: true });
    const r = timeoutMs ? await withTimeout(p, timeoutMs, 'Runtime.evaluate') : await p;
    if (r.exceptionDetails) {
      const d = r.exceptionDetails;
      throw new Error(d.exception?.description ?? d.text ?? 'evaluate failed');
    }
    return r.result?.value;
  }
}

export function withTimeout(promise, ms, what = 'operation') {
  let timer;
  const t = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(`${what} timed out after ${ms} ms`)), ms);
  });
  return Promise.race([promise, t]).finally(() => clearTimeout(timer));
}

/** Creates a page target and attaches to it (flatten mode). */
export async function newPage(cdp, { url = 'about:blank', background = true } = {}) {
  const { targetId } = await cdp.send('Target.createTarget', { url, background });
  const { sessionId } = await cdp.send('Target.attachToTarget', { targetId, flatten: true });
  return new Session(cdp, sessionId, targetId);
}

export async function closePage(cdp, session) {
  try {
    await cdp.send('Target.closeTarget', { targetId: session.targetId });
  } catch {}
}
