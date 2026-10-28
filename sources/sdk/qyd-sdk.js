/*
 * qyd-sdk.js — the page side of a 时光源 (轻悦时光 / qread web-page book source).
 *
 * A 时光源 is one HTML page that the app loads into a hidden web view. The app calls the page's global functions
 * (search / info / chapter / content / getfinds / find / getloginurl / login / gethelp / pay / filter / findfilter /
 * imagedecrypt / shouldOverrideUrlLoading / callbackjs) and the page talks back through
 * `window.flutter_inappwebview.callHandler(name, ...args)`. This file wraps every handler the app implements
 * (see docs/TIME_SOURCE.md) in the same class / method names that third-party sources already use
 * (FlutterJSBridge, Http, Cache, Cookie), and adds a few DOM / URL / model helpers under `QYD`.
 *
 * Usage (inline it in the page, before the source's own code):
 *   const flutterBridge = new FlutterJSBridge();   // reports `CookieJar` as soon as the bridge exists: the app waits for it
 *   const http = new Http(), cache = new Cache(), cookie = new Cookie();
 *   async function search(key, page) { ... return JSON.stringify([QYD.book({...})]); }
 *
 * Runs unchanged in the app (HeadlessInAppWebView), in the desktop runner (sources/runner) and in the original app.
 */
(function (global) {
  'use strict';

  function bridge() {
    return global.flutter_inappwebview;
  }

  /** Calls a handler; a missing bridge or a handler error rejects. */
  async function call(name) {
    const args = Array.prototype.slice.call(arguments, 1);
    const b = bridge();
    if (!b || typeof b.callHandler !== 'function') throw new Error('flutter_inappwebview bridge missing: ' + name);
    return await b.callHandler.apply(b, [name].concat(args));
  }

  /** Calls a handler and answers [fallback] instead of throwing (the convention of the template pages). */
  async function safe(name, fallback) {
    const args = Array.prototype.slice.call(arguments, 2);
    try {
      return await call.apply(null, [name].concat(args));
    } catch (e) {
      return fallback;
    }
  }

  function headersJson(h) {
    if (h == null) return '{}';
    return typeof h === 'string' ? h : JSON.stringify(h);
  }

  class FlutterJSBridge {
    /**
     * @param {{isCookieJar?: boolean, autoReady?: boolean}} [opts] isCookieJar: let the app keep the cookies of the page's
     *   http requests (default true). autoReady false: the page calls ready() itself (front web views must NOT report ready).
     */
    constructor(opts) {
      opts = opts || {};
      this.isCookieJar = opts.isCookieJar !== false;
      this.isReady = false;
      if (opts.autoReady !== false) this.init();
    }

    init() {
      const self = this;
      if (bridge()) {
        self.ready();
      } else {
        global.addEventListener('flutterInAppWebViewPlatformReady', function () {
          self.ready();
        });
      }
    }

    /** `CookieJar(isCookieJar)`: tells the app the page is loaded; until then every call of the app waits (60 s). */
    async ready() {
      this.isReady = true;
      try {
        await call('CookieJar', this.isCookieJar);
      } catch (e) {
        console.error('CookieJar failed:', e);
      }
    }

    /** Reloads the discovery page (drops its cached entries when it is not open). */
    refreshExplore() {
      return safe('refreshExplore', '');
    }

    /** Replaces the stored html of this source (在线版地址更新) and restarts the page. */
    setHtml(html) {
      return safe('setHtml', null, String(html));
    }

    getbuildNumber() {
      return safe('buildNumber', 0);
    }

    getversion() {
      return safe('version', '0.0.0');
    }

    toTraditional(str) {
      return safe('toTraditional', '', String(str));
    }

    toSimplified(str) {
      return safe('toSimplified', '', String(str));
    }

    /** The device id the app sends as `deviceid` (stable per installation). */
    getDeviceid() {
      return safe('id', '');
    }

    /** windows | macos | ios | ohos | android */
    getDevice() {
      return safe('device', '');
    }

    /** The user name of the app account ('' when not logged in). */
    getLoginUser() {
      return safe('getLoginUser', '');
    }

    /** A line of the source debugger / app log. */
    log(str) {
      return safe('log', false, String(str));
    }

    /** Debugger html: type 0 search, 1 detail, 2 toc, 3 content. */
    text(type, str) {
      return safe('text', false, Number(type) || 0, String(str));
    }

    showToast(str) {
      return safe('showToast', false, String(str));
    }

    showLongToast(str) {
      return safe('showLongToast', false, String(str));
    }

    getWebViewUA() {
      return safe('getWebViewUA', '');
    }

    openurl(url) {
      return safe('openurl', false, String(url), '');
    }

    openurlwithMimeType(url, mimeType) {
      return safe('openurl', false, String(url), String(mimeType || ''));
    }

    /**
     * Background web view: loads `html` (with `url` as its address) or `url` (a POST when `body` is given, then put the
     * Content-Type in `header`), waits until the page is quiet and answers the value of `js` (the page source when empty).
     * `header` is a JSON string or an object.
     */
    webview(url, js, html, body, header) {
      return safe('webview', '', String(url || ''), String(js || ''), String(html || ''), String(body || ''), headersJson(header), '', '');
    }

    /** Like webview(), but answers the first navigation url matching `overrideUrlRegex` (the js value / source when none). */
    webViewGetOverrideUrl(url, js, html, body, header, overrideUrlRegex) {
      return safe('webview', '', String(url || ''), String(js || ''), String(html || ''), String(body || ''), headersJson(header), String(overrideUrlRegex || ''), '');
    }

    /** Like webview(), but answers the first loaded resource / navigation url matching `urlregex`. */
    webViewGetSource(url, js, html, body, header, urlregex) {
      return safe('webview', '', String(url || ''), String(js || ''), String(html || ''), String(body || ''), headersJson(header), '', String(urlregex || ''));
    }

    /** Like webview(), but answers the response text of the first XMLHttpRequest whose url matches `ajaxregex`. */
    webViewGetAjax(url, html, body, header, ajaxregex) {
      return safe('webviewajax', '', String(url || ''), String(html || ''), String(body || ''), headersJson(header), String(ajaxregex || ''));
    }

    /** Front web view (manual captcha / login); answers the page html when the user closes it. */
    startBrowser(url, title, header) {
      return safe('startBrowser', '', String(url), String(title || ''), headersJson(header));
    }

    /** Front web view that asks the page's `shouldOverrideUrlLoading(url)` before every navigation. */
    startBrowserWithShouldOverrideUrlLoading(url, title, header) {
      return safe('startBrowserWithShouldOverrideUrlLoading', '', String(url), String(title || ''), headersJson(header));
    }

    /** Half-height sheet (段评 / comments). */
    startBrowserDp(url, title) {
      return safe('startBrowserDp', '', String(url), String(title || ''));
    }

    startBrowserDpWithShouldOverrideUrlLoading(url, title, header) {
      return safe('startBrowserDpWithShouldOverrideUrlLoading', '', String(url), String(title || ''), headersJson(header));
    }

    /** Half-height sheet showing `html` under the address `url`. */
    startBrowserDpwithHtml(url, html, title) {
      return safe('startBrowserDpwithHtml', '', String(url || ''), String(html || ''), String(title || ''));
    }

    /** Front web views only: closes the current page. */
    back() {
      return safe('back', false);
    }

    utf8ToGbkUrlEncoded(str) {
      return safe('utf8ToGbkUrlEncoded', '', String(str));
    }

    /** Shows the captcha image (`str` url, `header` JSON) and answers what the user typed ('' = plain input). */
    getVerificationCode(str, header) {
      return safe('getVerificationCode', '', String(str || ''), headersJson(header));
    }

    /** Opens the detail page of `book` (a book url of this source, or the JSON of a book). */
    addbook(book) {
      return safe('addbook', '', typeof book === 'string' ? book : JSON.stringify(book));
    }

    /** Runs a search in the app with this source. */
    searchbook(key) {
      return safe('searchbook', null, String(key));
    }

    base64encode(str) {
      return safe('base64encode', '', String(str));
    }

    base64decode(str) {
      return safe('base64decode', '', String(str));
    }

    htmlToText(html) {
      return safe('htmlToText', '', String(html));
    }

    /** Plays `url` in the app's video player (short dramas). */
    showvideoplay(url, title) {
      return safe('showvideoplay', null, String(url), String(title || ''));
    }

    /** Speaks `text` with the app's TTS. */
    voice(text) {
      return safe('voice', null, String(text));
    }

    /** The reader's current chapter index of `bookUrl`. */
    getdurChapterIndex(bookUrl) {
      return safe('getdurChapterIndex', 0, String(bookUrl));
    }

    /** Asks the reader to reload the current chapter. */
    refreshContent() {
      return safe('refreshContent', null);
    }
  }

  /**
   * HTTP through the app: every answer is `{method, data (decoded text), body (base64 bytes), headers {name: [values]},
   * statusCode, statusMessage}` or null when the bridge failed; a transport error gives statusCode 0 with the error in
   * statusMessage. `http2://` / `https2://` urls select HTTP/2 in the original app (plain https here).
   */
  class Http {
    Get(url, headers, followRedirects) {
      return safe('http', null, 'get', String(url), '', headersJson(headers), followRedirects !== false, '');
    }

    Head(url, headers, followRedirects) {
      return safe('http', null, 'head', String(url), '', headersJson(headers), followRedirects !== false, '');
    }

    /** `contenttype` wins over a Content-Type header; without both the app sends application/x-www-form-urlencoded. */
    Post(url, headers, body, contenttype, followRedirects) {
      return safe('http', null, 'post', String(url), body == null ? '' : typeof body === 'string' ? body : JSON.stringify(body), headersJson(headers), followRedirects !== false, String(contenttype || ''));
    }
  }

  /** Key/value store of this source (one text value per key; `null` when unset). */
  class Cache {
    get(key) {
      return safe('cache.get', null, String(key));
    }

    set(key, value) {
      return safe('cache.set', null, String(key), value == null ? '' : typeof value === 'string' ? value : JSON.stringify(value));
    }

    remove(key) {
      return safe('cache.remove', null, String(key));
    }

    /** The store shared by all sources. */
    allget(key) {
      return safe('cache.allget', null, String(key));
    }

    allset(key, value) {
      return safe('cache.allset', null, String(key), value == null ? '' : typeof value === 'string' ? value : JSON.stringify(value));
    }

    allremove(key) {
      return safe('cache.allremove', null, String(key));
    }

    /** The JSON text of the login dialog's fields (getloginurl() answered a form), '' / null before the first login. */
    getLoginInfo() {
      return this.get('LoginInfo');
    }

    putLoginInfo(info) {
      return this.set('LoginInfo', info);
    }

    /** The 书籍变量 the user typed for a book (keyed by its bookUrl). */
    getbookVariable(bookurl) {
      return this.get(String(bookurl));
    }

    setbookVariable(bookurl, value) {
      return this.set(String(bookurl), value);
    }
  }

  /** The app's cookie store, by url. */
  class Cookie {
    /** All cookies of the url's host as one `a=b; c=d` text. */
    get(url) {
      return safe('cookie.get', null, String(url));
    }

    remove(url) {
      return safe('cookie.remove', null, String(url));
    }

    /** Replaces the cookies of the url's host with `value` (`a=b; c=d`). */
    set(url, value) {
      return safe('cookie.set', null, String(url), String(value));
    }

    setCookie(url, key, value) {
      return safe('cookie.setcookie', null, String(url), String(key), String(value));
    }

    /** One cookie value, null when absent. */
    getCookie(url, key) {
      return safe('cookie.getCookie', null, String(url), String(key));
    }
  }

  // ------------------------------------------------------------------ helpers (not part of the app's contract)

  /** Parses html into a Document (scripts never run). */
  function dom(html) {
    return new DOMParser().parseFromString(String(html || ''), 'text/html');
  }

  function q(root, selector) {
    return (root && root.querySelector) ? root.querySelector(selector) : null;
  }

  function qa(root, selector) {
    return (root && root.querySelectorAll) ? Array.prototype.slice.call(root.querySelectorAll(selector)) : [];
  }

  function text(el) {
    return el ? String(el.textContent || '').replace(/\s+/g, ' ').trim() : '';
  }

  function attr(el, name) {
    return el ? String(el.getAttribute(name) || '') : '';
  }

  /** Resolves `href` against `base` (absolute urls pass through). */
  function abs(base, href) {
    try {
      return new URL(String(href || ''), String(base || location.href)).href;
    } catch (e) {
      return String(href || '');
    }
  }

  /** Decodes json text (twice when the text holds a json string); `fallback` on failure. */
  function json(value, fallback) {
    let v = value;
    for (let i = 0; i < 2 && typeof v === 'string'; i++) {
      const t = v.trim();
      if (!t) return fallback;
      try {
        v = JSON.parse(t);
      } catch (e) {
        return i === 0 ? fallback : v;
      }
    }
    return v === undefined ? fallback : v;
  }

  /** Query-string encoding of an object. */
  function query(params) {
    return Object.keys(params || {}).map(function (k) {
      return encodeURIComponent(k) + '=' + encodeURIComponent(params[k] == null ? '' : params[k]);
    }).join('&');
  }

  /** Strips the decorations many sites put around a title (《》 are kept). */
  function purifyTitle(title) {
    const t = String(title == null ? '' : title).trim();
    return t.replace(/^[^A-Za-z0-9一-龥()（）《》【】]+|[^A-Za-z0-9一-龥()（）《》【】]+$/g, '');
  }

  function escapeHtml(s) {
    return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  /** `<p>` paragraphs out of plain text lines (what content() returns for a novel). */
  function paragraphs(textOrLines) {
    const lines = Array.isArray(textOrLines) ? textOrLines : String(textOrLines || '').split(/\r?\n/);
    return lines.map(function (l) {
      return l.replace(/^[\s　]+|\s+$/g, '');
    }).filter(Boolean).map(function (l) {
      return '<p>' + escapeHtml(l) + '</p>';
    }).join('\n');
  }

  /** Book type numbers of the app. */
  const TYPE = { novel: 0, audio: 1, comic: 2, drama: 4 };

  /** A book object with every field the app reads (search / find lists and info()). */
  function book(b) {
    b = b || {};
    return {
      bookUrl: String(b.bookUrl || ''),
      name: String(b.name || ''),
      author: String(b.author || ''),
      kind: Array.isArray(b.kind) ? b.kind.filter(Boolean).join(',') : String(b.kind || ''),
      coverUrl: String(b.coverUrl || ''),
      intro: String(b.intro || ''),
      tocUrl: String(b.tocUrl || b.bookUrl || ''),
      wordCount: String(b.wordCount == null ? '' : b.wordCount),
      type: Number(b.type) || 0,
      latestChapterTitle: String(b.latestChapterTitle || ''),
      downloadUrls: String(b.downloadUrls || ''),
    };
  }

  /** A chapter object (index is overwritten by the app with the position). */
  function chapter(c, index) {
    c = c || {};
    return {
      name: String(c.name || ''),
      chapterId: String(c.chapterId || c.url || ''),
      index: Number(index != null ? index : c.index) || 0,
      isPay: !!c.isPay,
      isVip: !!c.isVip,
      isVolume: !!c.isVolume,
      tag: String(c.tag || ''),
    };
  }

  /** The entries getfinds() answers (JSON array). width: 0 auto, 1 half, 2 two thirds, 3 full line. */
  const explore = {
    /** A list: `url` is given to find(url, page) (`{{page}}` is replaced by the page). */
    list: function (title, url, width) {
      return { title: String(title), url: String(url), width: Number(width) || 0 };
    },
    /** A page opened in the app's web view. */
    web: function (title, url, width) {
      return { title: String(title), url: String(url), width: Number(width) || 0, type: 1 };
    },
    /** A drop-down: the choice is stored with cache.set(title, value), then `action` (js) runs in the page. */
    select: function (title, chars, defaultValue, action, width) {
      return { title: String(title), type: 2, chars: chars.map(String), default: String(defaultValue == null ? '' : defaultValue), action: String(action || ''), width: Number(width) || 0 };
    },
    /** An input box, stored like a drop-down. */
    input: function (title, defaultValue, action, width) {
      return { title: String(title), type: 3, default: String(defaultValue == null ? '' : defaultValue), action: String(action || ''), width: Number(width) || 0 };
    },
    /** A button running `action` (js) in the page. */
    button: function (title, action, width) {
      return { title: String(title), type: 4, action: String(action || ''), width: Number(width) || 0 };
    },
    /** A full-width section title. */
    title: function (title) {
      return { title: String(title), url: '', width: 3 };
    },
  };

  /** Login dialog rows for getloginurl(): [{name, type: text|password|select|button, default, chars, action}]. */
  const loginForm = {
    text: function (name, defaultValue) {
      return { name: String(name), type: 'text', default: String(defaultValue == null ? '' : defaultValue) };
    },
    password: function (name) {
      return { name: String(name), type: 'password' };
    },
    select: function (name, chars, defaultValue) {
      return { name: String(name), type: 'select', chars: chars.map(String), default: String(defaultValue == null ? '' : defaultValue) };
    },
    button: function (name, action) {
      return { name: String(name), type: 'button', action: String(action || '') };
    },
  };

  /** `<img src="url,{json}">` with options the reader understands (js on tap, headers, imageDecode). */
  function image(url, opts) {
    return '<img src="' + String(url) + (opts ? ',' + JSON.stringify(opts) : '') + '"/>';
  }

  const QYD = {
    version: '1.0.0',
    call: call,
    safe: safe,
    FlutterJSBridge: FlutterJSBridge,
    Http: Http,
    Cache: Cache,
    Cookie: Cookie,
    dom: dom,
    q: q,
    qa: qa,
    text: text,
    attr: attr,
    abs: abs,
    json: json,
    query: query,
    purifyTitle: purifyTitle,
    escapeHtml: escapeHtml,
    paragraphs: paragraphs,
    TYPE: TYPE,
    book: book,
    chapter: chapter,
    explore: explore,
    loginForm: loginForm,
    image: image,
  };

  global.QYD = QYD;
  global.FlutterJSBridge = FlutterJSBridge;
  global.Http = Http;
  global.Cache = Cache;
  global.Cookie = Cookie;
})(typeof window !== 'undefined' ? window : globalThis);
