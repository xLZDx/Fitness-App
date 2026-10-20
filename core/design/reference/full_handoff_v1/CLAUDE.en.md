# Fitness App — Approved Historical HUD/Glass Visual Design (English Companion)

**Original:** [HUD design instructions](CLAUDE.md), Git blob `25234e886fac645381a0bb9136b46e1ff44587ce`. The two source copies under `core/design/reference/fitness_hud_v1/` and `core/design/reference/full_handoff_v1/` are byte-identical. This is a **dated design reference**, not proof the current Flutter app uses these tokens or that simulated pose detection is a validated live capability.

**Visual concept:** A floating **head-up-display (HUD) glass** UI above background photography. The main source reference is `Fitness Form Coach Phone.dc.html`; theme comparison: `Fitness Screens 50-50.dc.html`.

## Source design assets

- `Fitness Glass Phone v1 - Sunset.dc.html` — dark theme, six views: Home, Workouts, Scan, Progress, Profile and Session.
- `Fitness Glass Phone v1 - Light.dc.html` — light theme using the same layout.
- `Fitness Form Coach Phone.dc.html` — trainer video and highlighted skeleton.
- `Fitness Sky.dc.html` — background `variant="photo"` changes with local device time and a **1.6-second cross-fade**.

## Dark glass formula — preserve exact source values

```css
background:rgba(255,255,255,.014);
backdrop-filter:blur(7px);
box-shadow:inset 0 0 0 1px rgba(255,255,255,.34),0 0 26px -6px rgba(255,255,255,.26);
text-shadow:0 1px 14px rgba(6,8,18,.85)
```

The primary button is the brightest element: background opacity **.05**, border **.46**, glow `0 0 28px -8px rgba(255,255,255,.35)`, and **-2px hover lift**.

Small chips use **.02 fill opacity** and **.28 border opacity**.

## Light glass formula

Same visual strategy with different contrast: `rgba(255,255,255,.3)` fill, `blur(14px) saturate(150%)`, double outline `inset 0 0 0 1px rgba(255,255,255,.85)` plus `0 0 0 1px rgba(27,32,48,.16)`, and white text shadow `0 1px 12px rgba(255,255,255,.9)`.

Buttons: **.46** fill opacity and **.3** dark outline. Primary text `#1b2030`, secondary `rgba(27,32,48,.62–.8)`.

## Geometry

- Main device frame corner radius **26**.
- Main panels **30**; secondary panels **24–28**.
- Buttons/chips **20–22**.
- Circular gauges `border-radius:50%`, **158×158 px**.
- Avoid dense opaque fills; the outline defines the surface.

## Color and type

- Dark accent `#C9FF47`; light accent `#4B7A00`.
- Positive/normal `#7BF08A`; error `#FF5A5A`.
- Font: **Archivo**. Large figures weight **400** at **34–72px**, with glow; contrast comes from size, not font bolding.
- Unit/caption labels: `ui-monospace`, **9–11px**, letter spacing **.1–.2em**, uppercase.
- Layout: flex/grid with `gap` rather than ad hoc element margins.

## Photography and day phases

The background switches through six phases: **night / dawn / morning / day / golden hour / dusk**. Use two curated image sets **A/B** (`photoSet`), optionally the user's photographs.

Source image library/settings: `Fitness Backgrounds.dc.html`. For light theme the source suggested photos above **55% brightness** with an uncluttered upper area; dark theme benefits from deeper shadows.

Personal-photo selection, any display of friends/family, and retention/share settings require actual user consent/privacy controls — the design file alone provides none.

## Rules from the original

- Reference device viewport: **390×844**.
- Touch targets at least **44px**.
- New pages should reuse existing theme files rather than creating unrelated duplicated versions.
- The project design system was named **Modernist**. Presentation/overview pages (50-50 comparison, background library) use Modernist tokens; product screen layers apply the HUD glass formula above.

## Implementation and governance boundary

This is a translated **historical design instruction**, not new authority to replace the current approved app tokens, edit existing Flutter code, copy `.dc.html` runtime logic, publish claims about real-time Form Coach, or collect/import personal photographs.

The original source and its identical copy remain unchanged. For full typography, screens and interaction details see the [English design handoff README](README.en.md).

**Disposition:** Source-linked English translation prepared; no product change, build, visual verification, independent design-review approval or deployment was performed.
