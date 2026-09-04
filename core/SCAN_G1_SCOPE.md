# SCAN-G1 — the Scan tab is the design reference's Scan screen

Rosetta plan `fitness_app-2026-09-04T01-00-12-787Z-9ccb13` (rev5), GPT-PM
`VERDICT: APPROVE` on hash `24efdd0d…8a1405` (request
`e4b8d2a1-6c3f-4d5e-8f7a-2b1c9d0e3f4a`, reply
`92f182f1-1a4a-4baf-83d2-c84f1385d33b`). Four earlier revisions were refused;
each refusal narrowed the acceptance contract and is recorded below, because
the contract is what this gate is.

## What this gate covers

Operator instruction, 2026-09-04, after G17 closed — verbatim: *«продолжай
автономно распознавание тренажёров, к тренеру вернёмся позже, отправляй
каждую новую версию с дистрибюшен тест»*, then, with the reference's two
Scan screens attached: *«и чтобы избежать прецедентов это должно выглядеть
та[к]»*. The Scan tab must look like the reference — both states — so the
Form Coach story (three rounds of "fixed" that were not what was asked) does
not repeat here.

This is the explicit operator request the 2026-08-30 Scan closure named as a
reopening condition. Gate 7's "overlap-only" GO (`core/DECISION_LOG.md`,
2026-08-30) is superseded for **visual layout**; its production-capability
protections (live camera, gallery, live labeler, history, privacy strip, AI
coach entry) stay.

## The reference

Canonical: `core/design/reference/fitness_hud_v1/` — the `isScan` block of
`Fitness Glass Phone v1 - Sunset.dc.html` (dark) and
`Fitness Glass Phone v1 - Light.dc.html` (light), both starting at line 180;
`README.md` §3 line 91. The checked-in `screenshots/{dark,light}/03-scan.png`
are 2924-px gallery strips, so the fidelity gate renders its own frames from
the canonical HTML (see R6).

| element | Sunset (dark) | Light | line |
| --- | --- | --- | --- |
| title | `font:800 24px/1.1 Archivo; #fff` | `#1b2030` | 183 |
| subtitle | `400 12.5px/1.5; rgba(255,255,255,.72)` "Point the camera at one machine and tap Recognise." | `rgba(27,32,48,.78)` | 184 |
| viewfinder card | `margin:0 16px; height:230px; r30; bg rgba(255,255,255,.014); blur(7px); inset ring .34; glow 0 0 26px -6px .26` | `bg rgba(255,255,255,.3); blur(14) saturate(150%); inset ring .85; outer ring ink .16; drop 0 18px 34px -22px rgba(42,52,74,.35)` | 186 |
| brackets ×4 | `34×34 at inset 20; 2px solid rgba(255,255,255,.9); radii 15/10/10/10` | `rgba(27,32,48,.42)` | 187–190 |
| sweep line | `left/right 20; top 18; 2px; gradient transparent→white .95→transparent; glassScan 3.4s ease-in-out infinite` (translateY 0→196, opacity 0 →12 % 1 →88 % 1 →0) | same | 191 |
| centre glyph | `Material Symbols Sharp center_focus_weak 36px; rgba(255,255,255,.9)` | `rgba(27,32,48,.92)` | 193 |
| hint | `600 10px ui-monospace; letter-spacing .14em; rgba(255,255,255,.8)`; `ALIGN THE MACHINE IN FRAME` / `MACHINE LOCKED` | `rgba(27,32,48,.86)` | 194 |
| match card | `margin:14px 16px 0; padding:16px 18px; r30`, same glass as the viewfinder | same as light viewfinder | 205 |
| ring | `78×78, r 34; track rgba(255,255,255,.22) 1.5; arc #fff 2.5 round, drop-shadow 0 0 6px .85; value 400 20px Archivo` | `track rgba(27,32,48,.22); arc #1b2030` | 206 |
| eyebrow | `600 9px; .16em; uppercase; .72` "Match" | `.78` | 209 |
| name | `800 19px/1.15; margin-top 3` "Lat pulldown" | | 210 |
| category line | `400 11.5px; .8; margin-top 3` "Strength · Lats, Biceps" | `.86` | 211 |
| CTA | `margin-top 14; padding 14px 16px; r22; gradient accentSoft(accent+'59')→accentFaint(accent+'1f'); blur(18) saturate(160%); inset 0 1px 0 rgba(255,255,255,.55); inset ring accentLine(accent+'66'); drops 0 20px 34px -16px rgba(12,7,24,.85), 0 6px 14px -8px rgba(12,7,24,.5)`; label `700 13.5px` "Open exercises"; `arrow_forward` 19px | drops `rgba(42,52,74,.18)` ×2; label ink | 214–216 |
| primary button | `margin:14px 16px 18px; padding 16; r24; gradient rgba(26,15,34,.5)→.3; blur(22); inset 0 1px 0 .4; inset ring .2; drops 0 20px 36px -16px rgba(12,7,24,.85), 0 6px 14px -8px rgba(12,7,24,.5)`; glyph `center_focus_strong`/`refresh` 20px; label `700 14px` "Recognise"/"Scan again"; gap 9 | `bg rgba(255,255,255,.3); blur(14) saturate(150%); inset ring .85; outer ring ink .16; drop 0 18px 34px -22px rgba(42,52,74,.35)` | 221–223 |

Accent: dark `#C9FF47`, light `#4B7A00` (line 461 of each template; the app's
`HudTokens.accent` already carries both).

DOM boxes measured from the rendered canonical frame (phone coordinates,
390×844): title (20, 52); subtitle (20, 83.4); card (16, 116.1, 358×230);
primary button (16, 360.1, 358×52) → **bottom 412.1** (aiming); match card
(16, 360.1, 358×171); ring (34, 376.1, 78); CTA (34, 468.1, 322×47); Scan
again (16, 545.1, 358×52) → **bottom 597.1** (found). Below that the
reference draws nothing.

## The invariant

**The Scan tab IS the reference screen; everything production adds sits
below it, in the same language.** Concretely: the page is
`HudScreenBody` + `HudScreenTitle` over the app's sky; then the viewfinder
card with the LIVE camera cover-fitted inside it (the reference shows the sky
through the glass there — the product needs the camera, and the operator
asked for the viewfinder to be live on 2026-07-30); then, in the found state,
the match card ending with the Open exercises CTA; then the ONE glass button
(Recognise / Scan again). Only below that button: LastSessionCard, the
gallery + Live-labeler row, the live section, the AI-coach entry, offline
note, machine card, «Мои тренажёры», «Готовим», one muted disclosure
paragraph.

## Contracts fixed before implementation (R1–R7)

Each of these came out of a refused revision. They are acceptance criteria,
not implementation notes.

- **R1 — liveness measures camera pixels only** (rev1 BLOCKER: the sweep
  line itself would have passed a pixel-diff over a black preview). A
  debug-only evidence mode (`--dart-define=SCAN_EVIDENCE=true`, guarded by
  `kDebugMode &&`) hides every overlay inside the card and shows a frame
  counter fed by `CameraSession.frames()`. Criterion: two screenshots 1 s
  apart, overlays off, differ inside the card by >2 % of pixels (>24/255)
  **and** the counter advanced. `dumpsys media.camera` is secondary. A static
  interior while the counter advances is the 2026-08-31 S8 black-viewfinder
  defect reproduced — recorded with logcat, not closed.
- **R2 — the device found state comes from the camera path** (rev1
  BLOCKER: the gallery path bypasses `captureStill → crop → classifier`).
  Recognise → `captureStill()` → `cropToViewfinder` → `classifyFilePath` →
  outcome, aimed at a catalogue machine photo on the monitor. Evidence mode
  writes the cropped still to `scan_evidence/last_crop.jpg`; it is pulled
  and shown with the bracket window outlined (**R7**: the crop equals the
  bracket window, card inset 20 — not the whole card interior). Gallery is
  a supplementary check only.
- **R3 — crop contract** (rev1 MAJOR: aspect + scalar inset cannot invert a
  cover fit). `cropToViewfinder(path, {viewport, windowNormalized})`:
  `viewport` = the card's rendered logical size from its `RenderBox` at
  capture time; `windowNormalized` = the bracket window as fractions of it.
  EXIF bake → cover mapping (scale = max(vw/iw, vh/ih), centred) → inverse →
  clamp → crop. Pure `viewfinderSourceRect(image, viewport, window)` with
  hand-computed expectations for 358×230 and 328×230 × 4032×3024 and
  3024×4032, plus a synthetic corner-marker image test. Fail-open to the
  original path is kept.
- **R4 — the match card ends at the CTA** (rev1 MAJOR). `LastSessionCard`
  is the first block below the primary button.
- **R5 — exact glass recipes** (rev1 MAJOR: "HudPanel tokens" was not proven
  equal to the reference). Verified: dark `panel` (`hud_tokens.dart:447-456`)
  = the reference card exactly; dark `button` (`:490-499`) ≠ the reference
  primary button; `HudButtonTone.accent` = the reference CTA gradient and
  hairline but not its glass. So: `scanPrimaryButton` and `scanCta` recipes
  with the numbers in the table above, both themes, and an optional
  `HudButton` override whose absence leaves every other button byte-identical
  (existing HUD goldens must not move).
- **R6 — reference-fidelity acceptance gate** (rev2 MAJOR: no PASS/FAIL
  criterion; rev3 MAJOR: masks hid deterministic elements; rev4 MAJOR: ROI
  compared production extras against a reference that ends at the button).
  - (a) Reference frames are repository artefacts:
    `tools/design/render_reference_scan.js` renders the canonical HTML
    headless (Playwright, React 18 UMD injected before `support.js`,
    `initialTab`/`initialScanned` defaults patched, animations paused at
    t=0) at 390×844 @2x → `mobile/test/golden/reference/
    scan_{aiming,found}_{dark,light}.png` (as designed) and `…_flat.png`
    (sky import and the two decorative streaks hidden → flat base `#14182C` /
    `#EEF0F6` = `HudTokens.dark.base` / `light.base`; the hint's
    `ui-monospace` rendered as Roboto Mono 600, the app's bundled face for
    that role — the one documented substitution) plus `scan_anchors.json`
    (DOM `getBoundingClientRect` of every anchor, phone coordinates,
    including the centre glyph, hint, button glyph, CTA arrow and each
    state's primary button).
  - (b) Geometry + identity gate: a widget test at 390×844 asserts every
    canonical anchor within ±2 px (containers) / ±3 px (text boxes) of
    `scan_anchors.json`, and the identity/style of every glyph and text run
    (codepoint, family, size, weight, letter-spacing, colour, case). Both
    states, both themes.
  - (c) Pixel gate: `tools/design/scan_fidelity_check.py` compares
    `composed_scan_fidelity_{aiming,found}_{dark,light}.png` (ScannerPage at
    390×844 @2x over `ColoredBox(base)`, transparent fake camera, sweep at
    t=0, EN fixture "Lat pulldown / 92 / Strength · Lats, Biceps") with the
    flat reference frames on a **state-dependent ROI**: full width × y from
    46 to that state's canonical primary-button bottom read from
    `scan_anchors.json` (≈412.1 aiming / ≈597.1 found). The ONLY mask is the
    camera/sky region — the bracket window interior (card inset 23, so the
    2-px bracket strokes stay in) minus the dilated centre-glyph and hint
    boxes. Thresholds per frame at 2x: ≤ 2.5 % of ROI pixels with
    max-channel |Δ| > 40/255 (aiming_dark: ≤ 3.2 %, see below) and mean
    |Δ| ≤ 5.0/255, every frame. A frame over its threshold is a finding to
    remediate, never a PASS with an explanation; the four numbers go into
    the decision log and the report either way.

    **aiming_dark's per-frame exception (2026-09-04).** Rosetta plan
    `fitness_app-2026-09-04T16-17-19-994Z-588ce5`, GPT-PM APPROVE on hash
    `cb7afce8caa0c6a8b90ede096df28a073c5675e07fcaf7a39f8588e00b25e248`
    (`core/DECISION_LOG.md`). Reasoning, GPT-PM's own: with the canonical,
    unmodified reference target (Google's own variable Archivo, not an
    app-font substitution -- a round-2 review of this same gate rejected an
    earlier attempt that substituted it), geometry/identity stayed 28/28
    PASS, and two independent measurements (3.102%, then 2.965% after that
    correction) both showed the diff confined to text/glyph/hairline
    anti-aliasing edges across the whole frame, with no localised or
    systematic defect -- the practical floor of comparing Chromium's
    rasteriser against Skia's at this ROI's size, not a geometry or token
    defect. Scoped narrowly on purpose: only `aiming_dark`'s bad-pixel-share
    moves, only to 3.2%; its own mean threshold, and every number for the
    other three frames, are unchanged. Raising this further, or extending an
    exception to another frame, needs its own approval the same way this one
    required -- not a comment edit.
  - (d) The sky composed goldens (full page, extras included) stay as
    regression pins and sit beside the as-designed reference renders in the
    report.
  - Glyphs: the reference's own icon font, `Material Symbols Sharp`,
    bundled as a six-glyph variable subset (`assets/fonts/
    MaterialSymbolsSharp-scan.ttf`, Apache-2.0, reproducible from
    `tools/design/build_symbols_subset.py`) and drawn with
    `fontVariations` wght 300 / opsz = size / FILL 0 / GRAD 0 — the same
    optical size Chromium picks for the reference.

## Out of scope

The recognition pipeline (`visualEquipmentControllerProvider`, Gemini/ML
Kit, timeouts, text anchor, history repository, machine-card
sanitisation-at-rest, P1.G5/P2/P4/P6); the equipment detail page; the Form
Coach; the ~24 non-scanner `App.tsx` citations; the light-theme accent
mismatch app-wide; the sky background system; the nav bar; migrating any
other screen's icons to Material Symbols. Anything found there is recorded,
not fixed.

## Review guidance

Review this diff against the invariant and R1–R7. The mandatory evidence is:
the geometry/identity test and the four fidelity numbers from the container
run on the final tree; the Windows and container suites; the S8 device
evidence per R1/R2/R7 (S23 only if it is reconnected); the distributed
version. Anything not obtained is recorded as not obtained.
