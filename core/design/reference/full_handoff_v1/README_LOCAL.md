# Full design handoff — everything from the zip, unabridged

Extracted 2026-08-30 from `D:\Downloads\Mobile app design (4).zip`
(`design_handoff_fitness_hud/`, archive dated 2026-08-20 00:43) — the same
archive `../onboarding_v4/README.md` pulled the onboarding subset from on
2026-08-20. **This directory is the rest of that same archive**, extracted
in full at the operator's explicit instruction after they pointed out that
80% of the design material had never been pulled into the repo.

## Why this was missing until now

Every visual-parity check done in this repo's HUD-redesign work up to
2026-08-30 compared the app against `docs/Redisign/reference/prototype/`
— screenshot crops from a screen recording of the Figma Make prototype.
That set's own README is explicit that it does **not** cover Scan, Session,
Progress, or the Form Coach / pose-overlay screen (`README.md`, "Coverage
is only what the operator clicked").

This archive is a different, higher-fidelity source: a proper design-tool
handoff (`.dc.html` specs, high-fidelity per its own `CLAUDE.md` — "colours,
typography, spacing, radii and states are final, reproduce pixel-for-pixel")
covering all six main screens plus Session plus a dedicated, detailed Form
Coach spec (`Fitness Form Coach Phone.dc.html` / `CLAUDE.md` §8) — including
an explicit real-product pose-overlay recipe (glowing bones, green/red by
technique correctness, pulsing error-joint indicator) that the prototype
video walkthrough never showed because the operator's recording never
opened that screen.

Only the onboarding slice of this archive was ever extracted
(`../onboarding_v4/`, 2026-08-20). The rest sat unextracted on the
operator's local disk for ten days while HUD-redesign gates were verified
against the narrower, admittedly-incomplete video-frame set instead —
including a `FORM_COACH_HUD_ALIGNMENT` gate (2026-08-29/30, see
`core/DECISION_LOG.md`) that was closed as done, but was scoped to exclude
pose-avatar/skeleton visual treatment entirely, so it never touched what
this archive actually specifies for that screen.

## What is here

Everything from `design_handoff_fitness_hud/` in the zip, unfiltered:

- `CLAUDE.md` — the approved design formula (tokens, glass-panel recipe,
  typography). Read this first.
- `README.md` — the handoff's own screen-by-screen spec (state machine,
  interactions, the Form Coach pose-overlay recipe in full).
- `*.dc.html` — the design-tool source files (all 6 main screens + Session
  in `Fitness Glass Phone v1 - Sunset/Light.dc.html`, Form Coach in its own
  file, onboarding, backgrounds library, and two overview/comparison files).
  Format note from the handoff's own README: `<x-dc>` markup +
  `<script type="text/x-dc">` component logic; `support.js` is the design
  tool's runtime and must not ship in the product.
- `screenshots/dark/`, `screenshots/light/` — one file per section
  (`01-home`, `02-workouts`, `03-scan`, `04-session`,
  `05-progress-profile-coach`), both themes, matching states.
- `screenshots/onboarding/` — the same 9-step onboarding screenshots already
  present in `../onboarding_v4/`, kept here too so this directory is the
  complete, unedited archive rather than a hand-curated subset.
- `screenshots/*.png` (top-level) — contact sheets and the 2x Form Coach
  detail shot.
- `uploads/*.webp` — the ten curated background photos referenced by
  `Fitness Sky.dc.html`'s `PHOTO_SETS`.
- `uploads/*.mp4` — `clip2-*.mp4` is the reference clip for Form Coach (with
  a burned-in skeleton overlay, used as the pose-overlay visual reference);
  `ref-indicators.mp4` is a style reference for on-screen indicators.
- `support.js` — the design tool's runtime. Reference only, per the
  handoff's own instruction: **do not ship this in the product.**

## Known caveats, carried over from the archive's own docs

- The handoff's own `CLAUDE.md`/`README.md` flag that pose detection in the
  Form Coach prototype is *simulated* (timer + trigonometry), not real
  pose estimation — the product's actual pose pipeline is what drives the
  overlay; the spec constrains the overlay's **visual treatment**, not the
  detection itself.
- Icons in the reference are Material Symbols Sharp; the handoff's own
  README says to swap for the product's own icon set, not copy verbatim.
  **Correction, 2026-08-30 (GPT-PM review caught this the same day it was
  written):** the line that used to stand here said this was "pending an
  operator reference for that specific asset" — wrong the moment this
  archive landed, since both main phone-spec `.dc.html` files name the five
  bottom-nav roles explicitly (`grid_view`, `fitness_center`,
  `radio_button_checked`, `north_east`, `person`). The nav-icon question is
  no longer blocked on a missing reference; see `core/DECISION_LOG.md`,
  2026-08-30 remediation entry, for the reopened ruling.
- Not yet reconciled against current code as of this commit — that
  comparison (pose-overlay visual treatment vs. `pose_silhouette.dart`, and
  Scan/Session/Progress screens vs. their current implementations) is
  separate follow-up work, not done in this commit.
- The overview/comparison `.dc.html` files (e.g. `Fitness All Screens -
  Dark.dc.html`) load `_ds/modernist-.../styles.css` and `_ds_bundle.js`,
  which are NOT included in this archive — opening those specific files
  directly will render with missing design-system assets/styling. The two
  main per-screen phone-spec files (`Fitness Glass Phone v1 - Light.dc.html`
  / `- Sunset.dc.html`) and `Fitness Form Coach Phone.dc.html` are
  self-contained (only `support.js` + `uploads/` alongside) and are the
  reliable files for parity work. (MINOR finding, GPT-PM review, 2026-08-30.)
