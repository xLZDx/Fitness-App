// Renders the design reference's Scan screen -- both states, both themes --
// to PNGs plus a JSON of DOM anchors, for SCAN-G1's reference-fidelity gate
// (core/SCAN_G1_SCOPE.md, R6). This is the ONLY source of the files under
// mobile/test/golden/reference/: nothing there is hand-drawn or hand-measured.
//
// What it does, in order, per (theme, state):
//   1. serves core/design/reference/fitness_hud_v1 over a local HTTP server
//      (the dc runtime fetches location.href, which file:// forbids), with
//      React 18 UMD injected before support.js and the prop defaults patched
//      to initialTab=2 (Scan) and initialScanned=<state>;
//   2. pauses every CSS animation (the sweep line's keyframes start at
//      opacity 0, so t=0 is a state the app can reproduce deterministically);
//   3. screenshots the 390x844 phone at 2x -> scan_<state>_<theme>.png
//      (the sky variant, for side-by-side viewing);
//   4. hides the sky import and the two rotated light streaks so the chrome
//      sits on the flat base colour, and renders the hint in Roboto Mono 600
//      (the family the app bundles; the reference's `ui-monospace` resolves
//      to whatever the host OS has, which no phone would match)
//      -> scan_<state>_<theme>_flat.png (the fidelity-check input);
//   5. reads the DOM rects + computed styles of every element the app has
//      to place -> scan_anchors.json (phone-relative logical px).
//
// usage: node tools/design/render_reference_scan.js [--out <dir>]
// env:   PLAYWRIGHT_MODULE (default D:/Repo/pm-bridge/node_modules/playwright)
'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const PLAYWRIGHT = process.env.PLAYWRIGHT_MODULE ||
  'D:/Repo/pm-bridge/node_modules/playwright';
const { chromium } = require(PLAYWRIGHT);

const REF_DIR = path.resolve(__dirname, '../../core/design/reference/fitness_hud_v1');
const SOURCES = {
  dark: 'Fitness Glass Phone v1 - Sunset.dc.html',
  light: 'Fitness Glass Phone v1 - Light.dc.html',
};
const outIdx = process.argv.indexOf('--out');
const OUT = outIdx > 0
  ? path.resolve(process.argv[outIdx + 1])
  : path.resolve(__dirname, '../../mobile/test/golden/reference');
fs.mkdirSync(OUT, { recursive: true });

const VIEWPORT = { width: 390, height: 844 };
const DSF = 2;
// The phone sits at the body's 8px margin; the browser viewport must hold
// it whole or the screenshot clip is cut to 382x836.
const BROWSER = { width: VIEWPORT.width + 16, height: VIEWPORT.height + 16 };

// Material Symbols ligature names -> codepoints, as shipped in
// mobile/assets/fonts/MaterialSymbolsSharp-scan.ttf (tools/design/build_symbols_subset.py).
const ICON_CODEPOINTS = {
  center_focus_weak: 'e3b5',
  center_focus_strong: 'e3b4',
  refresh: 'e5d5',
  arrow_forward: 'e5c8',
  photo_library: 'e413',
  videocam: 'e04b',
};

const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript',
  '.webp': 'image/webp', '.png': 'image/png', '.jpg': 'image/jpeg',
  '.css': 'text/css', '.json': 'application/json', '.woff2': 'font/woff2',
};

// R6(a)'s ONE approved font substitution: the hint's `ui-monospace` resolves
// to whatever the host OS has, which no phone would match, so it is forced
// to Roboto Mono 600 -- the app's own bundled face for that role -- below,
// after the flat variant is derived. Every OTHER face, Archivo included,
// stays exactly what the canonical HTML itself requests: Google's own
// variable Archivo webfont, unmodified. A round-2 GPT-PM review (SCAN-G1,
// 2026-09-04) rejected an earlier version of this file that ALSO substituted
// the app's static Archivo cuts here, reasoning (correctly) that doing so
// moves the reference toward the app instead of measuring the app against
// the reference -- a real app font-metric defect would have silently
// vanished into "the reference now matches" rather than being fixed.
const FONT_DIR = path.resolve(__dirname, '../../mobile/assets/fonts');
const FONTS = {
  'RobotoMono-SemiBold.ttf': ['Roboto Mono', 600],
};
for (const f of Object.keys(FONTS)) {
  if (!fs.existsSync(path.join(FONT_DIR, f))) throw new Error('missing ' + path.join(FONT_DIR, f));
}
const FONT_FACES = Object.entries(FONTS).map(([file, [family, weight]]) =>
  `@font-face{font-family:'${family}';font-weight:${weight};src:url(/__fonts/${file}) format('truetype')}`).join('');

function patch(html, scanned) {
  const before = html;
  html = html.replace('<script src="./support.js"></script>',
    '<script src="https://cdnjs.cloudflare.com/ajax/libs/react/18.3.1/umd/react.production.min.js"></script>' +
    '<script src="https://cdnjs.cloudflare.com/ajax/libs/react-dom/18.3.1/umd/react-dom.production.min.js"></script>' +
    `<style>${FONT_FACES}</style>` +
    '<script src="./support.js"></script>');
  html = html.replace('&quot;initialTab&quot;:{&quot;editor&quot;:&quot;int&quot;,&quot;default&quot;:0',
    '&quot;initialTab&quot;:{&quot;editor&quot;:&quot;int&quot;,&quot;default&quot;:2');
  html = html.replace('&quot;initialScanned&quot;:{&quot;editor&quot;:&quot;boolean&quot;,&quot;default&quot;:false',
    '&quot;initialScanned&quot;:{&quot;editor&quot;:&quot;boolean&quot;,&quot;default&quot;:' + (scanned ? 'true' : 'false'));
  if (html === before) throw new Error('reference markup changed: none of the patch points matched');
  return html;
}

const server = http.createServer((req, res) => {
  const u = new URL(req.url, 'http://x');
  let file = decodeURIComponent(u.pathname);
  const m = /^\/render\/(dark|light)\/(aiming|found)\.html$/.exec(file);
  if (m) {
    const html = patch(fs.readFileSync(path.join(REF_DIR, SOURCES[m[1]]), 'utf8'), m[2] === 'found');
    res.writeHead(200, { 'content-type': MIME['.html'] });
    return res.end(html);
  }
  if (file.startsWith('/render/')) file = file.replace(/^\/render\/(dark|light)\//, '/');
  const font = /^\/__fonts\/([^/]+)$/.exec(file);
  if (font && FONTS[font[1]]) {
    res.writeHead(200, { 'content-type': 'font/ttf' });
    return fs.createReadStream(path.join(FONT_DIR, font[1])).pipe(res);
  }
  const p = path.join(REF_DIR, file);
  if (!p.startsWith(REF_DIR) || !fs.existsSync(p) || fs.statSync(p).isDirectory()) {
    res.writeHead(404);
    return res.end('not found: ' + file);
  }
  res.writeHead(200, { 'content-type': MIME[path.extname(p)] || 'application/octet-stream' });
  fs.createReadStream(p).pipe(res);
});

// Runs in the page. Returns every anchor the app must reproduce, in
// phone-relative logical px, plus the computed style facts the identity
// assertions check (family, size, weight, spacing, colour, transform).
function extractAnchors({ origin, iconCodepoints }) {
  const screen = document.querySelector('[data-screen-label="Scan"]');
  if (!screen) return { error: 'no [data-screen-label="Scan"]' };
  const round = v => Math.round(v * 100) / 100;
  const rect = e => {
    const b = e.getBoundingClientRect();
    return {
      x: round(b.left - origin.x), y: round(b.top - origin.y),
      w: round(b.width), h: round(b.height),
      right: round(b.right - origin.x), bottom: round(b.bottom - origin.y),
    };
  };
  const style = e => {
    const c = getComputedStyle(e);
    return {
      fontFamily: c.fontFamily, fontSize: c.fontSize, fontWeight: c.fontWeight,
      letterSpacing: c.letterSpacing, lineHeight: c.lineHeight, color: c.color,
      opacity: c.opacity, textTransform: c.textTransform,
      borderRadius: c.borderRadius, fontVariationSettings: c.fontVariationSettings,
    };
  };
  const all = Array.from(screen.querySelectorAll('*'));
  const visible = e => { const b = e.getBoundingClientRect(); return b.width > 0 && b.height > 0; };
  const text = e => e.textContent.trim();
  const leaf = pred => all.find(e => e.childElementCount === 0 && visible(e) && pred(text(e), e));
  const container = e => e ? { rect: rect(e), style: { borderRadius: getComputedStyle(e).borderRadius } } : null;
  const textual = e => e ? { rect: rect(e), text: text(e), style: style(e) } : null;
  const icon = e => e ? {
    rect: rect(e), name: text(e), codepoint: iconCodepoints[text(e)] || null, style: style(e),
  } : null;
  const near = (a, b) => Math.abs(a - b) < 0.75;

  const out = {};
  out.screen = container(screen);
  const title = leaf((t, e) => t === 'Scan' && getComputedStyle(e).fontSize === '24px');
  out.title = textual(title);
  out.subtitle = textual(leaf(t => t.startsWith('Point the camera')));

  const card = all.find(e => visible(e) && near(rect(e).h, 230) && rect(e).w > 300 && e.childElementCount >= 5);
  out.card = container(card);
  if (card) {
    const inside = Array.from(card.querySelectorAll('*')).filter(visible);
    // `width:34px;height:34px` plus a 2px border on two sides, content-box:
    // the rendered box is 36x36, with the stroke on its outer edges.
    const brackets = inside.filter(e => near(rect(e).w, 36) && near(rect(e).h, 36) && e.childElementCount === 0 && text(e) === '')
      .map(e => ({ e, r: rect(e) }))
      .sort((a, b) => (a.r.y - b.r.y) || (a.r.x - b.r.x));
    const names = ['bracket_tl', 'bracket_tr', 'bracket_bl', 'bracket_br'];
    brackets.forEach((b, i) => { out[names[i] || ('bracket_' + i)] = container(b.e); });
    out.sweep = container(inside.find(e => near(rect(e).h, 2) && rect(e).w > 200));
    const glyph = inside.find(e => e.hasAttribute('data-icon'));
    out.centre_glyph = icon(glyph);
    out.hint = textual(inside.find(e => e.childElementCount === 0 && !e.hasAttribute('data-icon') && text(e) !== ''));
  }

  // The one primary button: its label is either "Recognise" or "Scan again".
  // The runtime wraps bound text in its own span, so "the button" is the
  // first ancestor that spans the phone's content width, not the parent.
  const wide = e => { while (e && rect(e).w < 350) e = e.parentElement; return e; };
  const primaryLabel = leaf(t => t === 'Recognise' || t === 'Scan again');
  if (primaryLabel) {
    const btn = wide(primaryLabel);
    out.primary_button = container(btn);
    out.primary_label = textual(primaryLabel);
    out.primary_glyph = icon(btn && btn.querySelector('[data-icon]'));
  }

  const eyebrow = leaf(t => t === 'Match');
  if (eyebrow) {
    const mc = wide(eyebrow);
    out.match_card = container(mc);
    out.eyebrow = textual(eyebrow);
    out.name = textual(eyebrow.nextElementSibling);
    out.category = textual(eyebrow.nextElementSibling && eyebrow.nextElementSibling.nextElementSibling);
    const svg = mc.querySelector('svg');
    out.ring = container(svg);
    out.ring_value = textual(leaf(t => /^\d{1,3}$/.test(t)));
    const ctaLabel = leaf(t => t === 'Open exercises');
    if (ctaLabel) {
      out.cta = container(ctaLabel.parentElement);
      out.cta_label = textual(ctaLabel);
      out.cta_arrow = icon(ctaLabel.parentElement.querySelector('[data-icon]'));
    }
  }
  return out;
}

function sha256(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

(async () => {
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  const port = server.address().port;
  const browser = await chromium.launch({ args: ['--font-render-hinting=none'] });
  const ctx = await browser.newContext({ viewport: BROWSER, deviceScaleFactor: DSF });
  const anchors = {
    meta: {
      generated_by: 'tools/design/render_reference_scan.js',
      viewport: VIEWPORT, device_scale_factor: DSF,
      coordinates: 'logical px relative to the 390x844 phone; multiply by 2 for the PNGs',
      sources: Object.fromEntries(Object.entries(SOURCES).map(([k, f]) => [k, {
        file: path.posix.join('core/design/reference/fitness_hud_v1', f),
        sha256: sha256(path.join(REF_DIR, f)),
      }])),
      flat: 'dc-import and the two rotate(24deg) streaks hidden; hint font-family forced to Roboto Mono 600; animations paused at t=0',
      fonts: 'Archivo is the canonical reference\'s own Google webfont, unmodified; Roboto Mono 600 is R6(a)\'s one approved substitution -- the app\'s own mobile/assets/fonts/RobotoMono-SemiBold.ttf, for the hint only',
      icon_codepoints: ICON_CODEPOINTS,
    },
  };
  const failures = [];
  for (const theme of ['dark', 'light']) {
    for (const state of ['aiming', 'found']) {
      const key = `${theme}_${state}`;
      const page = await ctx.newPage();
      page.on('pageerror', e => { console.error(`${key}: pageerror ${e.message}`); failures.push(`${key}: pageerror ${e.message}`); });
      // Console errors are reported, not fatal: the reference bundle itself
      // requests an `image-slot.js` that does not exist in the checkout (a
      // 404 on every load, including the hand-verified probe renders).
      page.on('console', m => { if (m.type() === 'error') console.error(`${key}: console ${m.text()}`); });
      page.on('requestfailed', r => console.error(`${key}: request failed ${r.url()} ${r.failure() && r.failure().errorText}`));
      console.log(`${key}: loading`);
      await page.goto(`http://127.0.0.1:${port}/render/${theme}/${state}.html`, { waitUntil: 'load', timeout: 60000 });
      await page.waitForTimeout(2500);
      await page.addStyleTag({ content: '*{transition:none !important}' });
      // Every animation paused AT ITS START: the sweep line's keyframes put
      // it at opacity 0 there, which is the one state the app reproduces
      // deterministically (`ScanFrame` at t=0, and under reduce motion).
      const { paused, fonts } = await page.evaluate(async () => {
        await document.fonts.ready;
        const anims = document.getAnimations();
        for (const a of anims) { a.pause(); a.currentTime = 0; }
        const fonts = [...document.fonts]
          .filter(f => f.status === 'loaded')
          .map(f => `${f.family.replace(/"/g, '')} ${f.weight}`).sort();
        return { paused: anims.length, fonts };
      });
      console.log(`${key}: ${paused} animations paused at t=0; fonts loaded: ${fonts.join(', ')}`);
      // Every Archivo weight the screen uses must actually have loaded --
      // from Google's webfont, the canonical reference's own source, not a
      // silent system-sans fallback (which `document.fonts` would still
      // report as "loaded" under the requested family name only if a real
      // face resolved). Roboto Mono is checked below, once the hint is
      // restyled to it -- nothing asks for it before that.
      for (const w of [400, 700, 800]) {
        if (!fonts.includes(`Archivo ${w}`)) failures.push(`${key}: Archivo ${w} not loaded`);
      }
      await page.waitForTimeout(300);
      // The phone: the first 390x844 box the dc runtime rendered.
      const box = await page.evaluate(([w, h]) => {
        for (const d of document.querySelectorAll('div')) {
          const r = d.getBoundingClientRect();
          if (Math.abs(r.width - w) < 0.5 && Math.abs(r.height - h) < 0.5) {
            return { x: r.left, y: r.top, width: r.width, height: r.height };
          }
        }
        return null;
      }, [VIEWPORT.width, VIEWPORT.height]);
      if (!box) {
        const dump = await page.evaluate(() => ({
          react: typeof window.React, xdc: document.querySelectorAll('x-dc').length,
          body: document.body.innerHTML.slice(0, 600),
        }));
        throw new Error(`${key}: phone box not found; ${JSON.stringify(dump)}`);
      }
      const clip = { x: box.x, y: box.y, width: VIEWPORT.width, height: VIEWPORT.height };
      await page.screenshot({ path: path.join(OUT, `scan_${state}_${theme}.png`), clip });

      // Flat variant.
      const hidden = await page.evaluate(() => {
        const out = { imports: 0, streaks: 0, hint: 0 };
        // The `<dc-import name="Fitness Sky">` renders as a `.sc-host` with
        // that name; hiding it leaves the phone's own flat background.
        document.querySelectorAll('.sc-host[data-sc-name="Fitness Sky"], dc-import').forEach(e => { e.style.visibility = 'hidden'; out.imports++; });
        // The light streaks: absolutely positioned, rotated gradient bands
        // over the sky (`rotate(24deg)` in Sunset; the Light file has its
        // own set). Anything rotated at the phone's top level is one.
        document.querySelectorAll('div').forEach(d => {
          if (/rotate\(/.test(d.getAttribute('style') || '')) { d.style.visibility = 'hidden'; out.streaks++; }
        });
        const screen = document.querySelector('[data-screen-label="Scan"]');
        const hint = screen && Array.from(screen.querySelectorAll('span')).find(s =>
          s.childElementCount === 0 && !s.hasAttribute('data-icon') &&
          getComputedStyle(s).fontFamily.includes('monospace'));
        if (hint) { hint.style.fontFamily = "'Roboto Mono', monospace"; out.hint++; }
        return out;
      });
      console.log(`${key}: flat -- hid ${hidden.imports} import(s), ${hidden.streaks} streak(s); hint restyled ${hidden.hint}`);
      if (hidden.imports < 1 || hidden.hint < 1) failures.push(`${key}: flat variant incomplete ${JSON.stringify(hidden)}`);
      await page.evaluate(async () => {
        await document.fonts.load("600 10px 'Roboto Mono'");
        await document.fonts.ready;
        return true;
      });
      await page.waitForTimeout(300);
      const monoOk = await page.evaluate(() => document.fonts.check("600 10px 'Roboto Mono'"));
      if (!monoOk) failures.push(`${key}: Roboto Mono 600 did not load`);
      await page.screenshot({ path: path.join(OUT, `scan_${state}_${theme}_flat.png`), clip });

      const a = await page.evaluate(extractAnchors, { origin: { x: box.x, y: box.y }, iconCodepoints: ICON_CODEPOINTS });
      if (a.error) failures.push(`${key}: ${a.error}`);
      const required = state === 'found'
        ? ['title', 'subtitle', 'card', 'bracket_tl', 'bracket_tr', 'bracket_bl', 'bracket_br', 'sweep',
          'centre_glyph', 'hint', 'primary_button', 'primary_label', 'primary_glyph', 'match_card',
          'ring', 'ring_value', 'eyebrow', 'name', 'category', 'cta', 'cta_label', 'cta_arrow']
        : ['title', 'subtitle', 'card', 'bracket_tl', 'bracket_tr', 'bracket_bl', 'bracket_br', 'sweep',
          'centre_glyph', 'hint', 'primary_button', 'primary_label', 'primary_glyph'];
      for (const r of required) if (!a[r]) failures.push(`${key}: anchor ${r} not found`);
      anchors[key] = a;
      console.log(`${key}: phone at (${box.x},${box.y}); ${Object.keys(a).length} anchors; hint "${a.hint && a.hint.text}"; primary "${a.primary_label && a.primary_label.text}"`);
      await page.close();
    }
  }
  fs.writeFileSync(path.join(OUT, 'scan_anchors.json'), JSON.stringify(anchors, null, 1) + '\n');
  await browser.close();
  server.close();
  if (failures.length) {
    console.error('FAILED:\n  ' + failures.join('\n  '));
    process.exitCode = 1;
  } else {
    console.log('wrote', OUT);
  }
})().catch(e => { console.error(e); process.exitCode = 1; });
