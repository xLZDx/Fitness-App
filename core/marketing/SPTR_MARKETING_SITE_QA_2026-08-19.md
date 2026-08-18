# SPTR Marketing Site — QA Report

**Date:** 2026-08-19 · **Build:** internal R&D prototype · **Repo state:** `78b24dc` + this change
**Harness:** Chrome (system channel) driven by Playwright, against a local static server that
emulates Firebase `cleanUrls`.

---

## 1. Matrix executed

Three concepts × two languages × two viewports, plus debug and reduced-motion passes.

| Viewport | Cases |
|---|---|
| Desktop 1440×900 | `a·en` `b·en` `c·en` `a·ru` `c·ru` `b·en·debug` |
| Mobile 390×844 @2x | same six |
| Reduced motion | `c·en` desktop |

---

## 2. Results

| Check | Result |
|---|---|
| Visible heroes per cell | **exactly 1** in all 12 cases — no cross-cell leakage |
| Visible hero sub-headlines per cell | **exactly 1** in all 12 cases |
| Horizontal overflow (`scrollWidth − clientWidth`) | **0 px** in all 12 cases |
| External network requests | **none** in any case |
| Console errors (normal use) | **none** |
| `/privacy` → HTTP | **200** via cleanUrls |
| `/terms` → HTTP | **200** via cleanUrls |
| Images loaded (mobile, full scroll) | 4 of 4, `naturalWidth > 0` |
| Initial transfer, each concept, both viewports | **142 KB — identical across A/B/C** |
| Debug badges | computed `::after` content resolves to `"exists"` under `?debug=1`, absent without |
| Prototype CTA | does not navigate; records `cta` in the local event array |
| Translation coverage | 67 `data-i18n` keys, **67 translated, 0 orphans** |
| Asset references | 9 referenced paths, **0 missing** |
| `alt` on every `<img>` | yes |

### Keyboard

Tab order from a cold load: skip link → brand mark → nav CTA → hero primary CTA → hero secondary
CTA → final CTA. Every stop takes a visible 3 px focus ring (`:focus-visible`, 3 px offset). The
skip link is off-screen until focused, then lands at `#main`.

### Reduced motion

Under `prefers-reduced-motion: reduce`: `.cta-in` computed opacity **1** — no content is left
hidden. Scroll-reveal transforms are neutralised, transitions collapse to ~0 ms, and the brand mark
renders its **final** form (`SPTR`) immediately rather than animating or freezing on the long word.

### Dark mode

A full dark palette is defined at token level under `prefers-color-scheme: dark`, including the
`theme-color` meta pair. Not exercised in the automated matrix — see limitations.

---

## 3. Defects found and fixed during QA

| # | Defect | Fix |
|---|---|---|
| 1 | **The debug panel was visible to every visitor.** An author `display: grid` on `.debug` outranked the user-agent rule for `[hidden]`, so the internal R&D switcher rendered in normal mode. | Explicit `.debug[hidden] { display: none }` |
| 2 | 404 on `/favicon.ico` in the console | Added `favicon.svg` and a `<link rel="icon">` |
| 3 | `<button>` styled as `.btn` inherited neither the page font nor a pointer cursor | `font-family: inherit; cursor: pointer` on `.btn` |
| 4 | Final CTA was `href="#"`, which scrolls to top on click | Converted to a `<button>` that records intent locally and does not navigate |
| 5 | `srcset` width descriptors and intrinsic `width`/`height` went stale after images were re-encoded — a layout-shift source | Descriptors and attributes re-synced to the real pixel sizes |
| 6 | `gym-bright.jpg` was generated but never referenced | Deleted rather than shipped as dead weight |

### Two harness defects, recorded so they are not mistaken for site defects

- **Blank sections in full-page screenshots.** The first capture showed every section below the hero
  empty. Cause: the page sets `scroll-behavior: smooth`, so the QA script's programmatic scroll
  outran the actual scroll position and the reveal observer never fired for lower sections. Fixed in
  the harness by forcing `scroll-behavior: auto` during traversal. The site was never affected.
- **`ERR_CONNECTION_RESET` on mobile.** Produced only when the harness scrolled the whole page in
  ~90 ms bursts, flooding a single-process test server with lazy-image requests. Re-tested under a
  normal wheel scroll: **zero console errors, zero non-200 responses, all images complete.** A
  threaded test server cleared it on desktop; the residual mobile case is the toy server, not the page.

---

## 4. Performance

| Metric | Value |
|---|---|
| Initial transfer (HTML + CSS + JS + hero image + favicon) | **142 KB** |
| Requests on first paint | 5 |
| Images below the fold | `loading="lazy"`, 3 of 4 |
| Total media on disk | 1.2 MB across 8 files (4 images × 2 widths) |
| Third-party bytes | **0** |
| Blocking scripts | none — the only inline script sets two attributes; `site.js` is `defer` |
| Fonts | system stack; no font download |

Images were right-sized and re-encoded during QA (`gym-floor` 410→289 KB, `label-context`
277→211 KB), and every `<img>` carries intrinsic dimensions plus `srcset`/`sizes`, so there is no
layout shift from media.

---

## 5. Preservation of existing surfaces

`git status` shows **no modified and no deleted files** — only additions. The seven pre-existing
files under `public/` are byte-identical, and `firebase.json` was not touched. `/privacy` and
`/terms` were re-checked live through the cleanUrls emulation and both return 200.

---

## 6. Limitations of this QA

Stated plainly rather than implied by silence.

1. **One browser engine.** Chrome only. No Firefox, no WebKit/Safari, no real iOS or Android device.
2. **Dark mode was not exercised in the matrix.** The tokens exist and are structured correctly, but
   no rendered pass confirms contrast or image legibility on the dark ground.
3. **No screen-reader pass.** Landmarks, `alt` text, `aria-hidden` on the decorative mark and an
   `aria-label` on the brand link are all in place, but no assistive technology was actually run.
   Contrast ratios were designed for, not measured.
4. **No Lighthouse or Core Web Vitals run.** Transfer size and request count were measured directly;
   LCP/CLS/INP were not.
5. **`cleanUrls` is emulated.** The Firebase Hosting emulator was not run, so rewrite behaviour is
   inferred from `firebase.json` plus a local shim.
6. **Russian copy was not reviewed by a second reader.** It is a concept localisation, not a
   translation, and the register-level risk identified in earlier rounds applies to it directly.
7. **No real user has seen this page.** Nothing here says anything about whether the concepts work.

---

## 7. Blockers before public use

1. Run the **pre-public truth gate** from Decision Pack §11, in **both languages**.
2. Remove or build every `committed` claim — four sentences today.
3. Remove the `hypothesis` claim, or keep it internal.
4. Replace the four illustration slots with **real product footage** (Implementation report §4).
5. Wire a real destination for the prototype CTA.
6. Remove `<meta name="robots" content="noindex, nofollow">` only at the moment the page is
   genuinely intended to be public — it is deliberately there now.
7. Close the QA limitations above that matter for a public surface: second engine, dark-mode pass,
   assistive-technology pass, measured contrast.

---

## 8. Verdict

**Internal R&D prototype: PASS.** All three concept cells render at parity, in two languages,
across two viewports, with no overflow, no external requests, no console errors, working
reduced-motion and keyboard paths, an intact set of pre-existing hosting files, and no fabricated
product evidence anywhere on the page.

**Public deployment: NOT READY**, and not attempted — see §7.
