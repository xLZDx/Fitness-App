# Fitness App — HUD Glass UI Design Handoff (English Historical Translation)

**Original:** [HUD design reference README](README.md), exact Git blob `eb98a338dddda4c035d7591ae388ffeaec2366eb`. Two source copies are byte-identical under `core/design/reference/fitness_hud_v1` and `core/design/reference/full_handoff_v1`. The [English CLAUDE reference](CLAUDE.en.md) summarizes the source design formula; this document translates the **complete original design handoff**. No current Flutter implementation or acceptance is certified.

## Overview

The original reference package depicts a mobile fitness application: Home, workout catalog, equipment scanner, active set, progress, profile and AI trainer assessing technique from video.

The visual concept is **floating HUD glass over live photographic imagery**. The background adapts to time of day. Panels are mostly transparent, defined by thin glowing outlines instead of opaque fills.

## About the design files

The bundled `.dc.html` assets are **visual and interaction prototypes**, not production source code to copy. Recreate relevant experience in the project's real target stack — the source mentions React Native, SwiftUI, Flutter or React Web as possible generic implementation platforms, but **the current Fitness-App project has a locked Flutter architecture**. Do not interpret a generic historic tool description as authorization to rewrite the app into another framework.

The internal design-tool syntax included markup inside `<x-dc>` and a logic class within `<script type="text/x-dc">`:

- `{{ x }}` — expression/value interpolation.
- `<sc-for list as>` — list rendering.
- `<sc-if value>` — conditional rendering.
- `<dc-import name>` — nested component import.

`support.js` is the **design tool's runtime and must NOT be copied into the product**.

## Fidelity and simulated behavior boundary

The source called for **high fidelity** in color, type, spacing, radius and visual states, with pixel-level matching to its prototypes. Its one explicit functionality simplification was **pose recognition in `Fitness Form Coach Phone`: a timer and trigonometry simulated the result**.

Therefore a real product must use a validated pose-estimation system rather than treating the demo's changing counters, warnings or skeleton as actual AI. Do not turn mock technique percentage into a product-quality claim without current model calibration, exercise coverage and real-device evidence.

## Design tokens

### Color table

| Role | Dark theme | Light theme |
| --- | --- | --- |
| Accent | `#C9FF47` | `#4B7A00` |
| Primary text | `#FFFFFF` | `#1b2030` |
| Secondary text | `rgba(255,255,255,.62–.80)` | `rgba(27,32,48,.62–.80)` |
| Device shell | `#14182c` | `#eef0f6` |
| Normal/success | `#7BF08A` | `#2F7A3A` |
| Error | `#FF5A5A` | `#FF5A5A` |
| Warning | `#FFB86B` | `#FFB86B` |
| Extra chart colors | `#FF7A5C` / `#FFB86B` / `#7CE0FF` | Same |

Alternative accent presets: `#7CE0FF`, `#FFB86B`, `#FF7A9C`.

### Dark theme glass (exact source formula)

```css
background: rgba(255,255,255,.014);
backdrop-filter: blur(7px);
box-shadow: inset 0 0 0 1px rgba(255,255,255,.34),
            0 0 26px -6px rgba(255,255,255,.26);
text-shadow: 0 1px 14px rgba(6,8,18,.85);
```

- Primary button: fill `rgba(255,255,255,.05)`, border opacity **.46**, glow `0 0 28px -8px rgba(255,255,255,.35)`. Hover `translateY(-2px)`, fill **.12**, border **.6**; active `translateY(0)`, fill **.2**; `.18s ease` transitions for transform/background/shadow.
- Small chips: fill `rgba(255,255,255,.02)`, outline `rgba(255,255,255,.28)`.
- Gauge tracks: `rgba(255,255,255,.16)`; accent fill and glow `0 0 12px -2px <accent>`.

### Light theme glass

```css
background: rgba(255,255,255,.3);
backdrop-filter: blur(14px) saturate(150%);
box-shadow: inset 0 0 0 1px rgba(255,255,255,.85),
            0 0 0 1px rgba(27,32,48,.16),
            0 18px 34px -22px rgba(42,52,74,.35);
text-shadow: 0 1px 12px rgba(255,255,255,.9);
```

- Button: `rgba(255,255,255,.46)` fill, **16px** blur and **160%** saturation, interior white outline `rgba(255,255,255,.95)`, exterior dark outline `rgba(27,32,48,.3)`.
- Chips: **.24** fill, outlines **.8** or `rgba(27,32,48,.16)`.
- Gauge track: `rgba(27,32,48,.10)` with inset outline `rgba(27,32,48,.16)`.

### Geometry

Frame radius **26**, main panel radius **30**, secondary panels **24–28**, buttons/chips **20–22**, picture tiles **16–22**. Circular counters: `border-radius:50%`, **158×158px**.

Reference screen **390×844**. Touch targets **at least 44px**. Arrange layouts with flex/grid and `gap` rather than independent margins on every child.

### Typography — Archivo, 400/500/600/700/800

| Text role | Source treatment |
| --- | --- |
| Screen heading | Weight **800**, **22px**, letter spacing **-.02em** |
| Panel heading | Weight **700**, **14–15px** |
| Large number | Weight **400**, **34–72px**, glow `0 2px 26px rgba(255,255,255,.45)` |
| Uppercase label | Weight **600**, **9–11px**, tracking **.18em**, secondary white opacity **.76** |
| Technical value | `ui-monospace`, **9–11px**, tracking **.1em** |
| Body | Weight **400**, **11–13px**, line height **1.4–1.6** |

**Large numeric weight is 400, NOT bold.** Contrast comes from size and glow.

### Shadows and photographic overlays

Presentation frame: `0 30px 60px -34px rgba(32,30,29,.55)`, reduced strength around **.4** for light.

Dark overlay: gradient from `rgba(10,12,22,α+.1)` at 0% to `α` at 58%, `α*.74` at 82%, `α*.9` at bottom. Original phase-specific α values: **night .50, dawn .44, morning .50, day .56, golden .46, dusk .44**.

Light overlay used `linear-gradient(180deg, rgba(246,247,252,.66), .6 58%, .7 100%)`.

## Screens and views

The original described the six main views in one `Fitness Glass Phone v1 - Sunset` (dark) / `... - Light` component, tab switching between them. Layer order: cover photo/video, translucent gradient, content, bottom tab bar.

### 1. Home (tab 0)

- **46px** status bar: time left, three icons right, text-shadow for legibility.
- Personal greeting with **800/22px** title and **400/11px** subtitle.
- Today's exercise panel with **158×158** circular count gauge, number weight **400/54px**, metadata; **Start** button as brightest element, label left/icon right.
- Seven weekday chips about **20px**, active one filled accent with dark text; completed days marked by `rgba(255,255,255,.85)` dot.
- Quick Scan entry as a glass row with icon.
- **Workout day vs rest day:** dim the hero-button glow and use honest recovery copy.

### 2. Workouts (tab 1)

Two subtabs `subTab 0/1`: **Programs** with active program and list; **Catalog** with five horizontal filter chips plus exercise list. Selected filter is fully accented; result count updates below.

### 3. Scan (tab 2)

Only four targeting corners, each `2px solid rgba(255,255,255,.9)` (light `rgba(27,32,48,.42)`), avoiding heavy permanent graphics. State `scanned` displays the recognition card with circular match percentage and exercise-opening action.

**Do not represent the prototype's simulated scan result or percentage as verified real recognition confidence.**

### 4. Progress (tab 3)

Weekly training-volume bars with outlines to stay visible in translucent panels; month calendar with dot markers; personal-record panel.

### 5. Profile (tab 4)

Settings rows use outlined glass surfaces and spacing rather than dividers. Toggle about **50×29px**, travel **21px**, highlighted accent state, white **23px** thumb with shadow.

### 6. Session (`view = "session"`)

Large SVG set-progress ring with `stroke-dasharray`, `rotate(-90deg)` and drop shadow; set list showing **done/current/pending** in `#7BF08A` / normal text / ~.45 opacity; bottom minus/plus and dominant **Set completed** CTA. Rest timer is live; button label changes but its shape remains stable.

### 7. Onboarding (separate Dark/Light design)

Nine source prototype steps, one question per screen, each with phase-specific background photo:

1. Welcome — one-sentence value promise.
2. Goal — four large choices.
3. Experience — circular levels **1–2–3**.
4. Schedule — day chips, 158px count circle, notification-reminder toggle.
5. Measurements — two large number sliders (weight 400/34px), unit selector.
6. Equipment — multi-select chips.
7. Camera — permission explanation, glowing skeleton preview and three privacy lines.
8. Background — 9:16 picture grid, first tile uploads a personal background image.
9. Ready — circular **12-week** label and four-line summary.

Nine-segment progress bar at top; completed segments accent/glow. **Skip** top right jumps to final step using defaults in the prototype. Bottom: **52px** circular Back button (first step opacity .35) and a single glowing primary CTA.

Prototype state: `step 1..9` plus selected goal, level, days, equipment, background, units and reminder.

**Scope warning:** This historic reference does not authorize actual premature camera permission, treating defaults as personal fitness recommendations, storing personal background images without consent or reintroducing an onboarding flow later removed by owner decisions.

### 8. Form Coach (`Fitness Form Coach Phone`)

- Layer 1: Workout video with `object-fit:cover`, `object-position:42% center` and `filter:saturate(.85) brightness(.72) contrast(1.02)`.
- Layer 2: The **same video** blended into a simulated highlighted skeleton through `mix-blend-mode:screen`, opacity .9 and an intense grayscale/brightness/contrast/sepia/hue/saturation filter. This is **not real pose estimation**.
- In a real product the source wanted a validated pose overlay with **3–3.4px** bones, white lines, green glow `rgba(110,255,130,.9)` for supported normal-state segments and red `rgba(255,70,70,.95)` when an actual error was observed. Error joint marker: dashed radius 26 with `4 6` and 1.1s pulse.
- Animated horizontal scan line: 2px gradient, **3.6s** per sweep.
- Two **158×158px** circles: **Reps** (`08/10` plus progress bar) and **Technique** (`94%`, phase label such as pull down/return). These values are **mockup counters**, not measured clinical accuracy.
- At most two cue lines: one affirmative, one corrective amber.
- Bottom four measures: tempo, range of motion, symmetry and pause, plus Pause and Complete set actions.

**Current product safety:** Do not show a form score when frame quality, visibility or angle is insufficient. The prototype's animated 94% is not independent model evaluation.

## Interactions and behavior

- Tab switch is immediate, without a page-transition animation.
- Buttons rise -2px on hover, return on active, transition .18s ease.
- Simulated rest timer/rep counter ticks at about **1s / 110ms**, with a repetition every 12 ticks and count at top.
- Demo form error every fourth repetition in the lower phase; mock technique value drops to **78%**, screen becomes red and corrective cue appears.
- Photo phase change uses **1.6s opacity crossfade** among six backgrounds.
- Scanner result changes on target tap from aiming to found.

**Do not translate these demo event triggers into real Form Coach decision logic.**

## Prototype state management (not production model schema)

| State | Original range/type | Concept |
| --- | --- | --- |
| `tab` | 0–4 | Bottom navigation selection |
| `view` | `home` / `session` | Workout overlay |
| `subTab` | 0–1 | Workouts subtab |
| `filter` | 0–4 | Catalog filter |
| `scanned` | Boolean | Prototype scan result |
| `day` | 0–6 | Selected weekday |
| `done` | Integer | Completed sets |
| `rest` | Seconds | Rest countdown |
| `hour` | -1..23 | -1 means live device time |
| `photoSet` | `a` / `b` | Background set |
| `theme` | light/dark | Two demo files, one product setting ideally |

Programs, exercises, personal records and calendar data were **constants in the prototype's logic class**. A real product must use its actual approved data sources/API/local database, not silently copy demo data.

## Backgrounds

Six day phases derived from local device clock:

| Phase | Device-local hours |
| --- | --- |
| Night | **22:00–04:59** |
| Dawn | **05:00–06:59** |
| Morning | **07:00–10:59** |
| Day | **11:00–15:59** |
| Golden hour | **16:00–18:59** |
| Dusk | **19:00–21:59** |

Two curated photograph sets A/B plus optional user-selected photos (including loved ones). Each photo has phase and overlay opacity. An optional **protect faces** setting places content below detected face rows. `Fitness Backgrounds.dc.html` defines the 9:16 library, upload tile, selected check and person badge.

Source heuristic: light theme photos above **55% brightness** with a visually calm top; dark theme deeper shadow areas.

**Privacy boundary:** The source does not establish legal rights, retention, cloud sync or permission to import or process real personal photographs. Implement only with actual user authorization and source-of-truth storage privacy guarantees.

## Assets and fonts

- `uploads/01…10_*.webp` — ten phase-aligned backgrounds, **1440×2560** in `Fitness Sky.dc.html` `PHOTO_SETS`.
- `uploads/clip2-*.mp4` — demo Form Coach footage with embedded skeleton overlay.
- `uploads/ref-indicators.mp4` — indicator style reference.
- Icons: Material Symbols Sharp in the design; use current project-native icon equivalents in product.
- Typeface: Archivo (Google Fonts), but actual Flutter production must respect offline font-loading/packaging requirements.

## Source file directory

| Original file | Historical purpose |
| --- | --- |
| `Fitness Glass Phone v1 - Sunset.dc.html` | Dark theme, six views and Session |
| `Fitness Glass Phone v1 - Light.dc.html` | Light theme, same composition |
| `Fitness Form Coach Phone.dc.html` | AI Coach / Form Coach mock |
| `Fitness Sky.dc.html` | Time-of-day photos, sets, overlays, crossfade |
| `Fitness Backgrounds.dc.html` | Background library, selection, controls |
| `Fitness Screens 50-50.dc.html` | Side-by-side dark/light comparison |
| `Fitness All Screens - Dark.dc.html` | Full dark theme views and states |
| `CLAUDE.md` | Design formula — source said read first |
| `support.js` | Design-tool runtime — **do not copy into product** |

## Screenshot directory

**`screenshots/dark/`** — five files per view group:

- `01-home.png` — Home: training day, rest day, morning.
- `02-workouts.png` — Programs, catalog, filter.
- `03-scan.png` — Aiming, found.
- `04-session.png` — Active set, rest, completed.
- `05-progress-profile-coach.png` — Progress, Profile, Form Coach.

**`screenshots/light/`** — equivalent five screen groups.

**`screenshots/backgrounds/all-ten-on-screen.png`** — all ten phase backgrounds with A/B set captions.  
**`screenshots/01-all-screens-dark.png`** — dark-theme contact sheet.  
**`screenshots/03-backgrounds-and-controls.png`** — library, frame settings, controls.  
**`screenshots/04-form-coach.png`** — 2× Form Coach reference.

## Viewing the prototypes

`.dc.html` files can be opened as static local browser references with adjacent `support.js` and `uploads/`. For a quick orientation, use `Fitness All Screens - Dark.dc.html` and `Fitness Screens 50-50.dc.html`.

This is a usage instruction for an archived design bundle, **not** authorization to execute copied third-party JavaScript in production.

## Translation and acceptance boundary

This English companion preserves all source sections — overview, file formats, fidelity, precise tokens, eight view groups, prototype states/interaction timing, day phases, assets, source file names, screenshot paths and viewer instructions.

**No existing Russian source, simulation code, image, user photo, backend model, design decision, app runtime, consent, training/test data or production file was changed by this translation.** The original's statements that the prototype is high-fidelity **do not override subsequent active Flutter product governance**, especially the need to verify live camera/ML, privacy promises and owner reviews.

**Status: DETAILED ENGLISH HISTORICAL DESIGN HANDOFF PREPARED — INDEPENDENT SEMANTIC REVIEW AND CURRENT-HEAD UI VERIFICATION PENDING.**
