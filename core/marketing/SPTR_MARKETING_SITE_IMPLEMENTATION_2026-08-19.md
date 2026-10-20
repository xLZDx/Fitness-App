# SPTR Marketing Site — Implementation Report

**Date:** 2026-08-19
**Repository:** `xLZDx/Fitness-App`
**HEAD at start:** `78b24dc` (no drift from the Decision Pack reference)
**Branch:** see §9
**Source of truth:** SPTR Marketing R&D Decision Pack v1.0
**Deployment:** NOT PERFORMED · **Push:** NOT PERFORMED · **Public marketing:** NOT AUTHORIZED

---

## 1. What was built

One static site shell in the existing Firebase Hosting root, carrying three equal-quality concept
variants selected by query parameter. No hero was selected; the site *is* the R&D instrument.

| URL | Cell | Hero |
|---|---|---|
| `/?concept=a` | Emotional / avoided machine | That machine you keep walking past? |
| `/?concept=b` | Auditable trust | See what SPTR saw. |
| `/?concept=c` | Future recurring value | Point. Recognize. Continue. |

Internal controls: `?lang=en` (default) · `?lang=ru` · `?debug=1`. Concept and language persist in
`localStorage` so a reviewer keeps a cell across reloads; an explicit query parameter always wins.

---

## 2. Files added

```
public/index.html                              new   (~15 KB)
public/assets/sptr/site.css                    new   (~16 KB)
public/assets/sptr/site.js                     new   (~10 KB)
public/assets/sptr/favicon.svg                 new
public/assets/sptr/media/machine-alone.jpg     new   (+ @700)
public/assets/sptr/media/label-band.jpg        new   (+ @590)
public/assets/sptr/media/label-context.jpg     new   (+ @600)
public/assets/sptr/media/gym-floor.jpg         new   (+ @800)
core/marketing/SPTR_MARKETING_SITE_IMPLEMENTATION_2026-08-19.md   new
core/marketing/SPTR_MARKETING_SITE_CLAIM_REGISTER_2026-08-19.md   new
core/marketing/SPTR_MARKETING_SITE_QA_2026-08-19.md               new
```

**Files modified:** none. **Files deleted:** none.

All seven pre-existing files under `public/` — `privacy.html`, `terms.html`,
`checkout-success.html`, `checkout-cancel.html`, `portal-return.html`,
`coach/onboarding-done.html`, `coach/onboarding-refresh.html` — are untouched and were verified
still resolving after the change (§7). `firebase.json` was not modified: hosting already serves
`public/` with `cleanUrls: true`, which is why the footer links are `/privacy` and `/terms`.

---

## 3. Architecture

**Static-first, as the gate directed.** Semantic HTML, one stylesheet, one deferred script. No
framework, no build step, no package manifest, no CDN, no runtime dependency on the Flutter app.

**Variant gate.** All three messages exist in the DOM; `html[data-concept]` reveals one. The
attribute is resolved by a small inline script in `<head>` *before first paint*, so no cell ever
flashes another cell's headline. Without JavaScript the page renders concept A in English, fully
readable — the copy is in the markup, not injected.

**Claim classes.** Every classified sentence carries `data-claim-class="exists|committed|
hypothesis"` in source. Under `?debug=1` each renders an inline badge via CSS `attr()`, and media
blocks reveal `data-media` (`real-photo` / `illustration`). Nothing is visible in normal mode.

**Localisation.** English lives in the markup and is the no-JS fallback; Russian is a dictionary in
`site.js` applied over `data-i18n` keys. 67 keys, 67 translated, zero orphans (§7).

**Instrumentation.** Local only. Concept views and CTA clicks go to an in-memory array readable via
`window.sptrEvents()` and echoed to the console in debug mode. Nothing is transmitted; the QA run
confirms zero external requests.

**Theming.** Light by default, with a full dark palette under `prefers-color-scheme`. Brand
continuity with the existing legal pages is deliberate: the same deep violet and the same
`#C2F562` lime, inverted onto a bright ground because the visual direction called for light and
premium rather than the dark treatment those pages use.

---

## 4. Media — and what could not be used

**Real photography only.** Four images, all cropped from the operator's own gym photographs of
2026-07-30 (`data/gym_photos_2026-07-30/`). Crops were chosen to exclude identifiable people; the
source set contains gym members whose faces are recognisable and who have not released them.

The evidence section is the strongest asset in the build: `label-band.jpg` and `label-context.jpg`
are a real Nautilus placard reading **PEC FLY / REAR DELT**, photographed on a real gym floor. That
is the actual mechanic being claimed, documented rather than illustrated.

**No app footage exists in this repository.** The only screenshots present
(`Screenshot_20260730_*.jpg`) are debugging artefacts from a bug hunt: one shows the old on-device
classifier calling two flat benches a *treadmill* at 100% confidence, another is a
`PlatformException` stack trace. Both predate the cloud recognition path. Using either as product
evidence would be false in the opposite direction, so neither was used.

Consequently **no screenshot of the app appears anywhere on the site.** Where product behaviour is
depicted it is either a real photograph (hero: a real machine inside a phone frame showing a camera
viewfinder, never a UI) or an explicitly labelled illustration built from the app's own shipped
strings.

### Real media still required before public use

| Slot | Needed |
|---|---|
| Hero | A real capture of the scanner in use — camera frame through to result |
| §3 return-to-machine | Real UI, once `MRD-01`…`MRD-04` are built. Cannot be shot today |
| §4 evidence | A real screenshot of `scannerReadOnMachine` next to a result |
| §5 unknown machine | A real machine card showing *Not in the catalog yet* and a sighting count |

---

## 5. Copy provenance

Quoted product strings are taken verbatim from `mobile/lib/l10n/app_en.arb` and `app_ru.arb`, not
invented: *Not sure — closest matches* (`scannerNotSureClosest`), *Not in the catalog yet*
(`machineCardNotInCatalogYet`), *scanned 3 times* (`machineCardSeenTimes`), *Read on the machine*
(`scannerReadOnMachine`). The Russian page uses the Russian originals of the same keys.

**Russian is localised as concept, not translated.** Concept C is the clearest case: *Point.
Recognize. Continue.* becomes *Навести. Узнать. Продолжить.* — infinitives, because the natural
imperative in Russian forces a formality choice and the past tense forces a gender. That makes the
Russian heroes **separate stimuli**, and they must be tested as such rather than pooled with the
English cells.

---

## 6. Concept parity

The gate required equal production quality so that message is tested rather than execution. Parity
is enforced structurally rather than by eye: all three cells share one layout, one stylesheet, one
section count, one CTA treatment, one brand treatment, and the same images. Only the hero headline
and its single supporting sentence differ.

Objective check: initial transfer is **142 KB for all three cells at both viewports** — byte-identical,
because nothing but two text nodes changes between them.

---

## 7. Tests run

Full detail in the QA report. Headline results, Chrome via Playwright, desktop 1440×900 and mobile
390×844:

- three concepts × two languages × two viewports render, each with exactly one visible hero and one
  visible sub-headline — no cross-cell leakage;
- **zero horizontal overflow** in every combination;
- **zero external network requests** — no analytics, no fonts, no CDN;
- zero console errors under normal use;
- `/privacy` and `/terms` return 200 through `cleanUrls`;
- reduced-motion: all content painted, reveal skipped, brand mark lands on its final form;
- keyboard: skip link first, then brand, then every CTA — all focusable with a visible ring;
- debug mode renders claim badges (`content: "exists"` confirmed computed);
- prototype CTA does not navigate and records locally.

Screenshots: all three concepts at both viewports, both languages for A and C, debug mode, and a
reduced-motion pass, in the session scratchpad under `shots/`.

---

## 8. Findings raised during implementation

1. **The exercise clips are not bundled.** `assets/exercises/` was removed from `pubspec.yaml` on
   2026-08-04. Clips stream from cloud storage over a signed URL with a bundled still as the
   instant fallback; if signing fails the poster simply stays. The demonstration-video claim is
   true but network-dependent, and the claim register records that.
2. **`gym-bright.jpg` was generated and then deleted** rather than shipped unused.
3. **A CSS specificity bug was found and fixed in review:** an author `display: grid` on the debug
   panel beat the user-agent rule for `[hidden]`, so the internal R&D control was visible to every
   visitor. Now explicitly `display: none` when hidden.
4. **Scroll-reveal is JS-additive, not CSS-default** — the hiding class is applied by script, so a
   JavaScript failure leaves the page fully visible rather than blank.

---

## 9. Git

Local commit only, on a branch off `master`. Nothing pushed, nothing deployed, no remote touched.
Exact commit hash and branch name are recorded in the session report accompanying this document.

---

## 10. How to run it locally

Firebase Hosting is not required. From the repository root:

```bash
python -m http.server 8080 --directory public
```

Then open `http://127.0.0.1:8080/?concept=a`. Swap `a` for `b` or `c`; add `&lang=ru` and
`&debug=1` as needed.

`cleanUrls` is a Firebase Hosting behaviour, so `/privacy` and `/terms` 404 under a plain static
server. Use `/privacy.html` locally, or run `firebase emulators:start --only hosting`. The QA
harness emulates `cleanUrls` and confirms both links resolve as they will in production.

---

## 11. Not done, deliberately

- **No hero selected.** Ranking the cells needs real respondents.
- **Not deployed, not pushed.**
- **No public-facing copy approved.** Two `committed` claims and one `hypothesis` claim are rendered
  in this internal build; under the Decision Pack they may not appear publicly until built and
  verified. The pre-public truth gate has not been run and must be, in both languages.
- **No web fonts.** A system stack is used to keep the page free of external dependencies. If a
  distinct typeface becomes part of the brand, it must be self-hosted and inlined, not linked.
