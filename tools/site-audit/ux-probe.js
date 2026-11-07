#!/usr/bin/env node
// Visitor-POV probe: renders each URL in headless Chromium at 1366 px (light, plus dark for the first
// URL) and as iPhone 13, and writes <out>/ux_probe.json and <out>/shots/<slug>_<mode>.png.
// Read-only: navigation only - no click, no input, no form. A page's errors land in the JSON, never thrown.
//
// Usage: node ux-probe.js [--out <dir>] [--reloads <n>] <url> [...url]
//   --out <dir>     where to write; default: the current folder
//   --reloads <n>   when the first URL's first load calls api.github.com, load it n more times in desktop mode,
//                   each as a new visitor; the api.github.com responses of every load of it are recorded;
//                   default 3, at most 20
// Needs Playwright with Chromium: npm i -g playwright, then npx playwright install chromium. Looked up as the
// package folder in SZA_PLAYWRIGHT, then playwright and playwright-core beside this script, in the current folder
// and in the global npm folder, then each playwright-core the ms-playwright cache links to. Honours HTTPS_PROXY
// when set (corporate or sandbox egress).
// The JSON is rewritten after every visit, so a run stopped from outside leaves what it measured; only a finished
// run sets its finishedAt.
// Exit: 0 the JSON is written, 1 it is not, 2 bad arguments, 3 Playwright or its Chromium missing, 4 the JSON is
// written but no page could be measured.
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');

const USAGE = 'usage: node ux-probe.js [--out <dir>] [--reloads <n>] <url> [...url]';
const INSTALL = 'npm i -g playwright, then npx playwright install chromium';
const TAP = 48;            // the canon UI_UX touch size in CSS px, applied to the mobile mode only
const PAGE_MS = 45000;     // one page's load and measurements; a measurement starting past it still gets a few seconds
const SETTLE_MS = 1500;    // after the load event, for what a script fills in (a fetched version)
const API_WAIT_MS = 5000;  // longest extra wait for an api.github.com call still in flight
const MAX_RELOADS = 20;    // the unauthenticated GitHub API allows 60 calls an hour per address
const DESKTOP = { viewport: { width: 1366, height: 800 }, deviceScaleFactor: 1 };
const API = /^https?:\/\/api\.github\.com(?=[/:?#]|$)/i;
const WEB = /^https?:/i;

const clip = (s, n) => { s = String(s == null ? '' : s).replace(/\s+/g, ' ').trim(); return s.length > n ? `${s.slice(0, n - 2)}..` : s; };
const firstLine = e => clip(String((e && e.message) || e).split('\n')[0], 200);
const uniq = a => [...new Set(a)];
// Lower case: on a file system that ignores case, /Case and /case would share one screenshot file
const slug = u => u.replace(/^https?:\/\//i, '').toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 60).replace(/_+$/, '') || 'page';
const log = s => process.stderr.write(`ux-probe: ${s}\n`);

function guard(promise, ms, what) {
  let timer;
  const late = new Promise((_, reject) => { timer = setTimeout(() => reject(new Error(`${what} took over ${Math.round(ms / 1000)} s`)), ms); });
  return Promise.race([Promise.resolve(promise), late]).finally(() => clearTimeout(timer));
}

function parseArgs(argv) {
  const a = { out: process.cwd(), reloads: 3, urls: [] };
  for (let i = 0; i < argv.length; i++) {
    let arg = argv[i], value;
    if (arg.startsWith('--') && arg.includes('=')) { value = arg.slice(arg.indexOf('=') + 1); arg = arg.slice(0, arg.indexOf('=')); }
    if (arg === '--out' || arg === '--reloads') {
      if (value === undefined) { if (i + 1 >= argv.length) throw new Error(`${arg} needs a value`); value = argv[++i]; }
      if (arg === '--out') { if (!value) throw new Error('--out needs a folder'); a.out = path.resolve(value); continue; }
      if (!/^\d+$/.test(value) || Number(value) > MAX_RELOADS) throw new Error(`--reloads takes a whole number from 0 to ${MAX_RELOADS}`);
      a.reloads = Number(value);
    } else if (arg.startsWith('-')) {
      throw new Error(`unknown option ${arg}`);
    } else {
      let u;
      try { u = new URL(arg); } catch { throw new Error(`not a URL: ${arg}`); }
      if (u.protocol !== 'http:' && u.protocol !== 'https:') throw new Error(`not an http(s) URL: ${arg}`);
      if (!a.urls.includes(u.href)) a.urls.push(u.href);
    }
  }
  if (!a.urls.length) throw new Error('no URL given');
  return a;
}

// Playwright keeps only the scheme and host of `server`, so credentials in the URL go to their own fields.
function proxyFromEnv() {
  const raw = process.env.HTTPS_PROXY || process.env.https_proxy;
  if (!raw) return null;
  try {
    const u = new URL(raw.includes('://') ? raw : `http://${raw}`);
    const proxy = { server: `${u.protocol}//${u.host}` };
    if (u.username && !u.protocol.startsWith('socks')) { proxy.username = decodeURIComponent(u.username); proxy.password = decodeURIComponent(u.password); }
    return proxy;
  } catch {
    return { server: raw };
  }
}

function packageRoot(file) {
  for (let dir = path.dirname(file), i = 0; i < 4; i++, dir = path.dirname(dir)) if (fs.existsSync(path.join(dir, 'package.json'))) return dir;
  return path.dirname(file);
}

function versionAt(dir) {
  try { return String(JSON.parse(fs.readFileSync(path.join(dir, 'package.json'), 'utf8')).version || 'unknown'); } catch { return 'unknown'; }
}

function linksFolder() {
  const set = process.env.PLAYWRIGHT_BROWSERS_PATH;
  let base;
  if (set && set !== '0') base = path.resolve(set);
  else if (process.platform === 'win32') base = path.join(process.env.LOCALAPPDATA || path.join(os.homedir(), 'AppData', 'Local'), 'ms-playwright');
  else if (process.platform === 'darwin') base = path.join(os.homedir(), 'Library', 'Caches', 'ms-playwright');
  else base = path.join(process.env.XDG_CACHE_HOME || path.join(os.homedir(), '.cache'), 'ms-playwright');
  return path.join(base, '.links');
}

// Where `npm i -g` puts a package; require.resolve does not look there on its own
function globalModules() {
  if (process.platform === 'win32') return path.join(process.env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming'), 'npm', 'node_modules');
  return path.join(path.dirname(path.dirname(process.execPath)), 'lib', 'node_modules');
}

function* candidates() {
  // A folder named in SZA_PLAYWRIGHT comes before anything found on its own
  if (process.env.SZA_PLAYWRIGHT) { const dir = path.resolve(process.env.SZA_PLAYWRIGHT); yield () => ({ mod: require(dir), dir }); }
  for (const name of ['playwright', 'playwright-core']) {
    yield () => { const file = require.resolve(name, { paths: [__dirname, process.cwd(), globalModules()] }); return { mod: require(file), dir: packageRoot(file) }; };
  }
  // `npx playwright install` leaves one file per installed playwright-core here, holding its folder; newest first.
  const links = linksFolder();
  const stamp = f => { try { return fs.statSync(f).mtimeMs; } catch { return 0; } };
  let files = [];
  try { files = fs.readdirSync(links).map(n => path.join(links, n)).sort((x, y) => stamp(y) - stamp(x)); } catch { /* no cache */ }
  for (const f of files) {
    let dir = '';
    try { dir = fs.readFileSync(f, 'utf8').trim(); } catch { /* unreadable link */ }
    if (dir) yield () => ({ mod: require(path.resolve(dir)), dir: path.resolve(dir) });
  }
}

// The first package that loads and starts Chromium wins; a package whose browser is missing is passed over.
async function start(launchOpts) {
  const seen = new Set();
  let found = '', failure = '';
  for (const load of candidates()) {
    let got;
    try { got = load(); } catch { continue; }
    const pw = got.mod;
    if (!pw || !pw.chromium || typeof pw.chromium.launch !== 'function' || !pw.devices) continue;
    const id = process.platform === 'linux' ? got.dir : got.dir.toLowerCase();
    if (seen.has(id)) continue;
    seen.add(id);
    found = found || `Playwright ${versionAt(got.dir)}`;
    try {
      return { pw, dir: got.dir, version: versionAt(got.dir), browser: await pw.chromium.launch(launchOpts) };
    } catch (e) {
      failure = failure || firstLine(e);
    }
  }
  return { found, failure };
}

// Runs inside the page: self-contained, serialised by Playwright. It reads the DOM and changes nothing.
const PROBE = ({ tap, bad }) => {
  const vw = innerWidth, vh = innerHeight;
  const de = document.documentElement, body = document.body || de;
  const st = (el, pseudo) => getComputedStyle(el, pseudo);
  const box = el => el.getBoundingClientRect();
  // Screen-reader-only text (a 1 px box that hides its overflow) is not on the screen a visitor sees
  const srOnly = el => {
    for (let e = el, i = 0; e && e !== body && i < 4; e = e.parentElement, i++) { const r = box(e); if ((r.width <= 1 || r.height <= 1) && st(e).overflow !== 'visible') return true; }
    return false;
  };
  const vis = el => { const r = box(el), s = st(el); return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none' && !srOnly(el); };
  const inView = r => r.top < vh && r.bottom > 0 && r.left < vw && r.right > 0;
  const top = el => Math.round(box(el).top + scrollY);
  const txt = el => (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim();
  const attr = (el, name) => (el.getAttribute(name) || '').trim();
  const px = v => Math.round(parseFloat(v) * 10) / 10;
  const uniq = a => [...new Set(a)];
  const label = el => {
    const img = el.querySelector('img[alt]');
    return (txt(el) || attr(el, 'aria-label') || attr(el, 'title') || (img ? attr(img, 'alt') : '') || attr(el, 'placeholder') || el.tagName.toLowerCase()).slice(0, 40);
  };
  const failedUrls = new Set(bad);
  const header = document.querySelector('header, .site-header, [role=banner]');

  // What the page says it is
  const h1s = [...document.querySelectorAll('h1')].filter(vis);
  const text = body.innerText || '';
  const cyr = (text.match(/[\u0400-\u04FF]/g) || []).length;
  const lat = (text.match(/[A-Za-z]/g) || []).length;
  const desc = document.querySelector('meta[name="description" i]');

  // Type: the sizes of visible running text; bodyFontPx is the size most of that text is set in
  const blocks = [...document.querySelectorAll('p, li, dd, td, blockquote, figcaption')].filter(e => e.textContent.trim() && vis(e));
  const weight = new Map();
  for (const e of blocks.slice(0, 400)) { const k = px(st(e).fontSize); weight.set(k, (weight.get(k) || 0) + txt(e).length); }
  const bodyFontPx = weight.size ? [...weight].sort((a, b) => b[1] - a[1])[0][0] : px(st(body).fontSize);
  const fonts = uniq(blocks.slice(0, 50).map(e => px(st(e).fontSize))).sort((a, b) => a - b);

  // Where content starts: the first visible h1 outside the header, else main
  const lead = h1s.find(e => !(header && header.contains(e))) || [...document.querySelectorAll('main, [role=main]')].find(vis);

  // Images: a failed request, or a decoded image of no size (lazy and SVG ones only by their request)
  const imgs = [...document.images];
  const svg = s => /\.svg([?#]|$)|^data:image\/svg/i.test(s);
  const brokenImgs = uniq(imgs.filter(i => {
    const s = i.currentSrc || i.src;
    if (!s) return false;
    if (failedUrls.has(s)) return true;
    return i.complete && i.naturalWidth === 0 && i.loading !== 'lazy' && !svg(s);
  }).map(i => (i.currentSrc || i.src).slice(-80)));

  // New-tab links: a hint is text, a label, a title, an icon's alt or name, or a ::before/::after glyph
  const hintRe = /new (browser )?(window|tab)|opens? in (a )?new|нов\S*\s+(окн|вкладк|вікн)|[\u2197\u21D7\u29C9]/i;
  const hinted = a => {
    let s = `${a.textContent} ${attr(a, 'aria-label')} ${attr(a, 'title')}`;
    for (const e of a.querySelectorAll('img[alt], [aria-label], title')) s += ` ${e.getAttribute('alt') || e.getAttribute('aria-label') || e.textContent}`;
    for (const id of attr(a, 'aria-describedby').split(/\s+/)) { const d = id && document.getElementById(id); if (d) s += ` ${d.textContent}`; }
    s += ` ${st(a, '::before').content} ${st(a, '::after').content}`;
    return hintRe.test(s);
  };
  const newTabLinks = [...document.querySelectorAll('a[target="_blank" i]')];
  const skipLink = !!document.querySelector('a[href^="#"][class*=skip], a.skip-link, [class*=skip-to]')
    || [...document.querySelectorAll('a[href^="#"]')].slice(0, 5).some(a => /skip|to (main )?content|перейти|к содержимому|до (змісту|вмісту|контенту)/i.test(a.textContent));

  // Calls to action
  const ctaRe = /download|install|get it|google play|play store|app store|\bstore\b|releases|open project|winget|скача|завантаж|загруз|установ|встанов/i;
  const ctas = [...document.querySelectorAll('a[href], button')].filter(vis).filter(a => ctaRe.test(a.textContent) || ctaRe.test(attr(a, 'aria-label')));
  const cta = ctas[0];
  const href = el => (typeof el.href === 'string' && el.href) || el.getAttribute('href') || null;
  // Above the fold means whole on the first screen: a button the bottom edge cuts is not
  const whole = r => r.top > -1 && r.bottom < vh + 1 && r.left < vw && r.right > 0;
  const firstCta = cta ? { text: (txt(cta) || attr(cta, 'aria-label')).slice(0, 50), href: href(cta), aboveFold: whole(box(cta)), top: top(cta) } : null;

  // Tap targets on the phone; a link inside a sentence is exempt, as WCAG 2.5.8 exempts it
  let small = null;
  if (tap) {
    const inSentence = el => {
      if (el.tagName !== 'A' || st(el).display !== 'inline') return false;
      let b = el.parentElement;
      while (b && b !== body && st(b).display === 'inline') b = b.parentElement;
      if (!b || b === body) return false;
      let rest = txt(b).length;
      for (const a of b.querySelectorAll('a, button')) rest -= txt(a).length;
      return rest >= 20;
    };
    small = [];
    for (const el of document.querySelectorAll('a[href], button, input:not([type=hidden]), select, summary, [role=button], [role=link], [role=tab], [role=menuitem]')) {
      if (!vis(el)) continue;
      const r = box(el);
      if (!inView(r) || (r.width >= tap && r.height >= tap) || inSentence(el)) continue;
      small.push(`${label(el)} (${Math.round(r.width)}x${Math.round(r.height)})`);
    }
    small = uniq(small).slice(0, 20);
  }

  // Switches, ads, consent
  // body only: PAGE-STYLE sets data-lang statically on <html>, the switch buttons carry it inside the body
  const hasLangSwitch = !!document.querySelector('body [data-lang], .lang, a[hreflang], [class*="lang-switch" i], [class*="langswitch" i], [class*="lang-select" i], [class*="language-switch" i], [class*="language-select" i], select[name*="lang" i], select[id*="lang" i], [aria-label*="language" i], [aria-label*="Язык"], [aria-label*="язык"], [aria-label*="Мова"], [aria-label*="мова"]');
  const hasThemeSwitch = !!document.querySelector('#themeBtn, [id*="theme-toggle" i], [class*="theme-toggle" i], [class*="theme-switch" i], [class*="themetoggle" i], button[class*="theme" i], button[id*="theme" i], [role=button][class*="theme" i], [role=switch][class*="theme" i], input[id*="theme" i], [aria-label*="theme" i], [title*="theme" i], [aria-label*="dark mode" i], [aria-label*="Тем"], [aria-label*="тем"], [title*="Тем"], [title*="тем"]');
  const clear = c => !c || c === 'transparent' || /^rgba\(.*,\s*0\)$/.test(c);
  const bg = st(body).backgroundColor;
  // adSlots: every slot the page declares, filled or not; adSlotsShown: those the visitor sees this time, so an
  // unfilled or 0x0 slot is left out
  const adIns = [...document.querySelectorAll('ins.adsbygoogle')];
  const adFrames = [...document.querySelectorAll('iframe')].filter(f => /googlesyndication|doubleclick/i.test(f.src || '') && !f.closest('ins.adsbygoogle'));
  const adSlots = adIns.length + adFrames.length;
  const adSlotsShown = adIns.filter(i => vis(i) && i.getAttribute('data-ad-status') !== 'unfilled').length + adFrames.filter(vis).length;
  const overlay = el => {
    for (let e = el, i = 0; e && e !== body && i < 8; e = e.parentElement, i++) {
      const s = st(e), role = e.getAttribute('role');
      if (s.position === 'fixed' || s.position === 'sticky' || role === 'dialog' || role === 'alertdialog' || e.getAttribute('aria-modal') === 'true' || (e.tagName === 'DIALOG' && e.open)) return true;
    }
    const r = box(el);
    return r.width * r.height >= 0.15 * vw * vh;
  };
  const consentDialog = [...document.querySelectorAll('[class*="fc-consent" i], [id*="fundingchoices" i], [class*="fundingchoices" i], iframe[src*="fundingchoices" i], [id*="consent" i], [class*="consent" i], [id*="cmp" i], [class*="cmp" i]')]
    .some(el => vis(el) && inView(box(el)) && overlay(el));

  // Versions in the text: dotted (26.1007.1435, 1.2.3), v-prefixed, after the word, or a separator-less
  // yyMMddHHmm stamp; a dd.mm.yyyy date is not one
  const versionsInText = [];
  const versionRe = /(?:version|версия|версія)\s*:?\s*v?\d{1,4}(?:\.\d{1,4}){1,3}|\bv?\d{1,4}(?:\.\d{1,4}){2,3}\b|\bv\d{1,4}\.\d{1,4}\b|\bv?\d\d(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01])(?:[01]\d|2[0-3])[0-5]\d\b/gi;
  for (const m of text.matchAll(versionRe)) {
    if (/^\d{1,2}\.\d{1,2}\.\d{4}$/.test(m[0]) || versionsInText.includes(m[0])) continue;
    versionsInText.push(m[0]);
    if (versionsInText.length === 10) break;
  }

  // The visible text of the first screen, in DOM order; " | " where a new block starts
  const parts = [];
  let size = 0, lastBlock = null;
  const blockOf = n => { let e = n.parentElement; while (e && e !== body && st(e).display === 'inline') e = e.parentElement; return e; };
  const walker = document.createTreeWalker(body, NodeFilter.SHOW_TEXT);
  const range = document.createRange();
  for (let n = walker.nextNode(); n && size < 500; n = walker.nextNode()) {
    const t = n.nodeValue.replace(/\s+/g, ' ').trim();
    const p = n.parentElement;
    if (!t || !p || /^(SCRIPT|STYLE|NOSCRIPT|TEMPLATE)$/.test(p.tagName)) continue;
    range.selectNodeContents(n);
    const r = range.getBoundingClientRect();
    if (!r.width || !r.height || !inView(r) || st(p).visibility === 'hidden' || srOnly(p)) continue;
    const b = blockOf(n);
    parts.push((parts.length ? (b === lastBlock ? ' ' : ' | ') : '') + t);
    lastBlock = b;
    size += t.length + 1;
  }

  return {
    // Every px here is a CSS px; a screenshot has dpr image pixels to each of them (3 on the phone)
    vw, vh, dpr: devicePixelRatio,
    lang: de.hasAttribute('lang') ? de.getAttribute('lang') : null,
    title: document.title,
    metaDesc: desc ? attr(desc, 'content').slice(0, 160) : null,
    h1: h1s.map(e => txt(e).slice(0, 120)),
    cyrRatio: +(cyr / Math.max(1, cyr + lat)).toFixed(2),
    fonts, bodyFontPx,
    overflow: de.scrollWidth > vw + 1,
    docH: de.scrollHeight,
    firstContentTop: lead ? top(lead) : null,
    imgs: imgs.length, brokenImgs,
    noAlt: imgs.filter(i => !i.hasAttribute('alt')).length,
    newTab: newTabLinks.length,
    newTabNoHint: newTabLinks.filter(a => !hinted(a)).length,
    skipLink,
    ctaCount: ctas.length, firstCta,
    smallTapTargetsAboveFold: small,
    headerHeight: header ? Math.round(box(header).height) : null,
    hasLangSwitch, hasThemeSwitch,
    colorScheme: matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light',
    bgColor: clear(bg) ? st(de).backgroundColor : bg,
    adSlots, adSlotsShown, consentDialog, versionsInText,
    foldText: parts.join('').slice(0, 500),
  };
};

// Byte counts come from the network, not from Resource Timing: that reports 0 for a cross-origin file served
// without Timing-Allow-Origin and nothing for what an iframe loads, which is where ads and embeds weigh.
async function perfOf(page, url, net, ms) {
  const [interactive, loaded] = await guard(page.evaluate(() => {
    const n = performance.getEntriesByType('navigation')[0];
    return n ? [n.domInteractive, n.loadEventEnd] : [0, 0];
  }), ms, 'timing');
  const sizes = (await guard(Promise.all(net.sized), ms, 'sizes')).filter(Boolean);
  const own = new Set();
  for (const u of [url, page.url()]) { try { own.add(new URL(u).host); } catch { /* not a URL */ } }
  // The page's own files by path, other hosts' with the host; a long path keeps the host and the file name
  const name = u => {
    try {
      const x = new URL(u), host = own.has(x.host) ? '' : x.host, s = host + x.pathname;
      return s.length <= 70 ? s : `${host}/../${x.pathname.split('/').filter(Boolean).pop() || ''}`.slice(0, 70);
    } catch { return clip(u, 70); }
  };
  // A moment the page never reached is null, not 0
  return {
    domInteractive: interactive > 0 ? Math.round(interactive) : null,
    load: loaded > 0 ? Math.round(loaded) : null,
    resources: net.requests,
    bytes: sizes.reduce((sum, x) => sum + x.bytes, 0),
    heaviest: sizes.sort((a, b) => b.bytes - a.bytes).slice(0, 5).map(x => ({ name: name(x.url), bytes: x.bytes })),
    thirdParty: [...net.hosts].filter(h => !own.has(h)),
  };
}

// Playwright's screenshot waits for document.fonts.ready, which stays pending while the page is still loading;
// the DevTools capture does not wait. Its clip is in the document's CSS px, so it starts at the scroll offset, and
// `scale` gives the image the profile's device pixels, as page.screenshot does.
async function rawShot(ctx, page, scale, file) {
  const { width, height } = page.viewportSize() || DESKTOP.viewport;
  const [x, y] = await page.evaluate(() => [scrollX, scrollY]);
  const cdp = await ctx.newCDPSession(page);
  try {
    const { data } = await cdp.send('Page.captureScreenshot', { format: 'png', clip: { x, y, width, height, scale } });
    fs.writeFileSync(file, Buffer.from(data, 'base64'));
  } finally {
    await cdp.detach().catch(() => {});
  }
}

const run = { current: null };
process.on('unhandledRejection', e => { const m = `unhandled: ${firstLine(e)}`; if (run.current) run.current.push(m); else log(m); });

// One load of one URL in one mode, in a fresh context. load 0 measures everything and takes the screenshot;
// a reload (load > 0) only records what api.github.com answered.
async function visit(url, mode, { load = 0, shot = null } = {}) {
  const full = load === 0;
  const R = { nav: { status: null, finalUrl: null, loadMs: null }, err: null, perf: null, probe: null, consoleErrs: [], failed: [], shot: null };
  const errs = [], errors = [], warnings = [], failed = [], bad = new Set(), sized = [], hosts = new Set();
  const pending = new Set(); // requests not finished yet: what a load that never ends is waiting for
  const api = { open: new Set(), list: [], closed: false };
  const watchApi = url === run.firstUrl;
  const deadline = Date.now() + PAGE_MS;
  const left = (cap, floor) => Math.max(floor, Math.min(cap, deadline - Date.now()));
  const wait = ms => page.waitForTimeout(ms).catch(() => {});
  let requests = 0, mainStatus = null, ctx = null, page = null;
  run.current = errs;
  try {
    if (!run.modes[mode]) throw new Error(`no device profile for ${mode}`);
    if (!run.browser.isConnected()) run.browser = await run.pw.chromium.launch(run.launchOpts);
    ctx = await run.browser.newContext({ ...run.modes[mode], locale: 'en-US', acceptDownloads: false });
    page = await ctx.newPage();
    const on = (event, fn) => page.on(event, x => { try { fn(x); } catch (e) { errs.push(`${event} handler: ${firstLine(e)}`); } });
    const isMain = q => { try { return q.isNavigationRequest() && q.frame() === page.mainFrame(); } catch { return false; } };
    on('console', m => {
      const type = m.type();
      if (type !== 'error' && type !== 'warning') return;
      const text = m.text(), at = /^Failed to load resource/.test(text) && m.location().url ? ` @ ${clip(m.location().url, 120)}` : '';
      (type === 'error' ? errors : warnings).push(`${type}: ${clip(text, 160)}${at}`);
    });
    on('pageerror', e => errors.push(`pageerror: ${clip(e && e.message, 160)}`));
    on('request', q => {
      const u = q.url();
      if (!WEB.test(u)) return;
      pending.add(q);
      if (!isMain(q)) requests++;
      try { hosts.add(new URL(u).host); } catch { /* not a URL */ }
      if (watchApi && API.test(u) && q.method() !== 'OPTIONS') api.open.add(q);
    });
    on('response', r => {
      const q = r.request(), u = q.url(), status = r.status();
      if (isMain(q)) mainStatus = status;
      if (status >= 400) { failed.push(`${status} ${clip(u, 140)}`); bad.add(u); }
      // What is left of this address's hourly quota: 0 beside a 403 means the quota is spent, by this audit too
      if (api.open.has(q) && !api.closed) {
        const quota = r.headers()['x-ratelimit-remaining'];
        api.open.delete(q);
        api.list.push({ load, mode, url: u, status, remaining: /^\d+$/.test(quota || '') ? Number(quota) : null });
      }
    });
    on('requestfailed', q => {
      pending.delete(q);
      const u = q.url(), why = (q.failure() || {}).errorText || 'failed';
      if (WEB.test(u)) { failed.push(`${why} ${clip(u, 140)}`); bad.add(u); }
      if (api.open.delete(q) && !api.closed) api.list.push({ load, mode, url: u, status: why, remaining: null });
    });
    on('requestfinished', q => {
      pending.delete(q);
      if (!full || !WEB.test(q.url())) return;
      sized.push(guard(q.sizes(), 5000, 'sizes').then(s => ({ url: q.url(), bytes: (s.responseBodySize || 0) + (s.responseHeadersSize || 0) }), () => null));
    });

    const t0 = Date.now();
    try {
      const resp = await page.goto(url, { waitUntil: 'load', timeout: PAGE_MS });
      R.nav = { status: resp ? resp.status() : mainStatus, finalUrl: page.url(), loadMs: Date.now() - t0 };
    } catch (e) {
      R.nav = { status: mainStatus, finalUrl: WEB.test(page.url()) ? page.url() : null, loadMs: Date.now() - t0 };
      const open = uniq([...pending].map(q => clip(q.url(), 80)));
      errs.push(`navigation: ${firstLine(e)}${open.length ? ` (still loading: ${open.slice(0, 3).join(', ')}${open.length > 3 ? ` and ${open.length - 3} more` : ''})` : ''}`);
    }
    if (WEB.test(page.url())) {
      const pause = Math.min(SETTLE_MS, deadline - Date.now());
      if (pause > 0) await wait(pause);
      await guard(page.evaluate(() => (document.fonts ? document.fonts.ready.then(() => 1) : 1)), left(3000, 500), 'fonts').catch(() => {});
      const until = Math.min(Date.now() + API_WAIT_MS, deadline);
      while (api.open.size && Date.now() < until) await wait(250);
      // A script can move the page on during the wait (location.replace); what is measured below is where it landed
      if (WEB.test(page.url()) && page.url() !== R.nav.finalUrl) R.nav = { ...R.nav, status: mainStatus, finalUrl: page.url() };
      if (full) {
        try { R.perf = await perfOf(page, url, { requests, hosts, sized: sized.slice() }, left(5000, 2000)); } catch (e) { errs.push(`perf: ${firstLine(e)}`); }
        try { R.probe = await guard(page.evaluate(PROBE, { tap: mode === 'mobile' ? TAP : 0, bad: [...bad].slice(0, 300) }), left(15000, 3000), 'probe'); } catch (e) { errs.push(`probe: ${firstLine(e)}`); }
      }
    }
    // The first screen in device pixels: 1366x800 on the desktop, 1170x1992 on the phone (probe.dpr per CSS px)
    if (full && shot) {
      const file = path.join(run.shotsDir, shot);
      try { await page.screenshot({ path: file, timeout: left(15000, 5000) }); R.shot = shot; } catch (e) {
        try {
          await guard(rawShot(ctx, page, run.modes[mode].deviceScaleFactor || 1, file), 5000, 'raw screenshot');
          R.shot = shot;
          errs.push(`screenshot: ${firstLine(e)} (captured without waiting for the page instead)`);
        } catch (e2) { errs.push(`screenshot: ${firstLine(e)}`, `raw screenshot: ${firstLine(e2)}`); }
      }
    }
  } catch (e) {
    errs.push(`${page ? 'page' : 'browser'}: ${firstLine(e)}`);
  } finally {
    api.closed = true;
    for (const q of api.open) api.list.push({ load, mode, url: q.url(), status: 'no response', remaining: null });
    R.consoleErrs = uniq([...errors, ...warnings]).slice(0, 10);
    R.failed = uniq(failed).slice(0, 10);
    if (ctx) await guard(ctx.close(), 10000, 'closing the page').catch(() => {});
    run.current = null;
  }
  R.err = errs.length ? errs.join(' | ') : null;
  if (watchApi) run.result.apiGithubLoads.push(...api.list);
  return R;
}

async function main() {
  let args;
  try { args = parseArgs(process.argv.slice(2)); } catch (e) { log(e.message); process.stderr.write(`${USAGE}\n`); return 2; }
  const startedAt = new Date().toISOString();
  const launchOpts = { headless: true, timeout: 60000 };
  const proxy = proxyFromEnv();
  if (proxy) launchOpts.proxy = proxy;

  const got = await start(launchOpts);
  if (!got.browser) {
    log(got.found ? `${got.found} found but Chromium did not start (${got.failure}) - install it with: ${INSTALL}` : `Playwright not found - install it with: ${INSTALL}`);
    return 3;
  }
  log(`Playwright ${got.version} from ${got.dir}`);
  const shotsDir = path.join(args.out, 'shots');
  try { fs.mkdirSync(shotsDir, { recursive: true }); } catch (e) {
    log(`cannot create ${shotsDir}: ${firstLine(e)}`);
    await guard(got.browser.close(), 15000, 'closing the browser').catch(() => {});
    return 2;
  }

  const phone = got.pw.devices['iPhone 13'];
  const { defaultBrowserType, ...phoneOpts } = phone || {};
  Object.assign(run, {
    pw: got.pw, browser: got.browser, launchOpts, shotsDir, firstUrl: args.urls[0],
    modes: { desktop: { ...DESKTOP, colorScheme: 'light' }, 'desktop-dark': { ...DESKTOP, colorScheme: 'dark' }, mobile: phone ? { ...phoneOpts, colorScheme: 'light' } : null },
    result: { tool: 'ux-probe', version: 1, startedAt, finishedAt: null, playwright: got.version, tapThreshold: TAP, pages: {}, apiGithubLoads: [] },
  });
  const { result } = run;
  const said = r => `${r.nav.status == null ? 'no response' : r.nav.status} in ${r.nav.loadMs == null ? '-' : r.nav.loadMs} ms${r.err ? ` (${clip(r.err, 160)})` : ''}`;
  const file = path.join(args.out, 'ux_probe.json');
  // Through a temporary file, so a run stopped mid-write keeps the previous whole file; when the rename fails (a
  // scanner holding the new file on Windows) the file is written in place
  const save = () => {
    const text = `${JSON.stringify(result, null, 1)}\n`;
    try { fs.writeFileSync(`${file}.tmp`, text); fs.renameSync(`${file}.tmp`, file); return true; } catch { /* in place below */ }
    try { fs.rmSync(`${file}.tmp`, { force: true }); } catch { /* left behind */ }
    try { fs.writeFileSync(file, text); return true; } catch (e) { log(`cannot write ${file}: ${firstLine(e)}`); return false; }
  };
  // Once the first URL is known to call api.github.com, a load of it that failed before any such call answered still
  // counts as a load, so "403 on N of M loads" holds
  const counted = (n, mode, r) => {
    if (r.err && !result.apiGithubLoads.some(e => e.load === n && e.mode === mode)) result.apiGithubLoads.push({ load: n, mode, url: run.firstUrl, status: `error: ${r.err}`, remaining: null });
  };
  let shots = 0, measured = 0, views = 0, firstErr = '', apiSeen = false;
  for (const url of args.urls) {
    const first = url === run.firstUrl;
    let key = slug(url);
    for (let n = 2; result.pages[key]; n++) key = `${slug(url)}_${n}`;
    const entry = result.pages[key] = { url };
    for (const mode of first ? ['desktop', 'desktop-dark', 'mobile'] : ['desktop', 'mobile']) {
      const R = entry[mode] = await visit(url, mode, { shot: `${key}_${mode}.png` });
      views++;
      if (R.probe) { measured++; if (R.shot) shots++; } else firstErr = firstErr || R.err || 'the probe returned nothing';
      log(`${mode} ${url} -> ${said(R)}`);
      if (first && mode === 'desktop') apiSeen = result.apiGithubLoads.length > 0;
      else if (first && apiSeen) counted(0, mode, R);
      save();
      if (!first || mode !== 'desktop' || !args.reloads) continue;
      // A reload records only what api.github.com answered, so a page that made no such call is not reloaded
      if (!apiSeen) { log(`desktop reloads skipped: the first load of ${url} made no api.github.com call`); continue; }
      for (let n = 1; n <= args.reloads; n++) {
        const r = await visit(url, mode, { load: n });
        counted(n, mode, r);
        log(`${mode} reload ${n} ${url} -> ${said(r)}`);
        save();
      }
    }
  }

  result.finishedAt = new Date().toISOString();
  let code = save() ? 0 : 1;
  if (!code && !measured) { log(`no page could be measured: ${clip(firstErr, 200)}`); code = 4; }
  await guard(run.browser.close(), 15000, 'closing the browser').catch(() => {});
  if (code !== 1) process.stdout.write(`ux-probe: wrote ${file}: ${measured} of ${views} page view(s) measured, ${shots} screenshot(s) of them in ${shotsDir}\n`);
  return code;
}

main().then(code => { process.exitCode = code; }, e => { log(`stopped: ${firstLine(e)}`); process.exitCode = 1; })
  // A handle Playwright leaves open must not keep a finished run alive.
  .finally(() => setTimeout(() => process.exit(process.exitCode), 3000).unref());
