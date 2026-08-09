# Reference frames — Figma Make prototype walkthrough

What the app is supposed to look like. Captured 2026-08-09 from a screen
recording the operator made while clicking through the Make prototype.

## Why these exist

R1–R4 were scoped from an audit document's prose retelling of the design
rather than from the design itself (`core/plans/PLAN_R11_FIGMA_PARITY_REBUILD_2026-08-08.md`,
§1), and §30 of the master prompt — capture an emulator screenshot, compare
it against the reference, record the deviations — was never executed once
across the whole R-sequence. The result was a shipped app that matched the
prototype's colour tokens and nothing else.

A reference that lives only in a chat attachment or in a recording on one
machine is not a reference. These are in the repository so a gate can be
closed against a picture instead of against a memory of one.

## Provenance

Source: `Rec - Aug 9, 2026 12-31-52 PM.mp4`, 190s, 3840×2160, operator's
own recording of the Figma Make preview.

Extraction — the prototype panel occupies a small region of the 4K frame,
so each frame is a crop of that region, not the whole screen:

```bash
ffmpeg -ss <t> -i "<video>" -frames:v 1 \
  -vf "crop=500:1060:1960:655,scale=560:-1" -y "p_<t>.png"
```

Sampled every 3 seconds from t=45s to t=189s, then converted to JPEG q4
(11 MB → 3.5 MB; these are read for layout, colour and type, not measured
to the pixel).

## What is in which frame

The filename is the timestamp in seconds.

| Frames | Screen |
|---|---|
| `p_045`–`p_099` | Internal "Research & Design System" governance screen — **not product UI**, ignore for implementation |
| `p_102`–`p_147` | Onboarding, steps 1/9 through 7/9 — goal + level, birth year + height (wheel/ruler pickers), weight with BMI card and target delta |
| `p_150` | Plan preview — "Твой план на неделю", stat tiles, today's session card |
| `p_153`–`p_171` | Home — greeting, programme progress bar, hero CTA, Quick Scan, recovery strip, week strip, stat tiles |
| `p_174`–`p_183` | Workouts — Programs/Library toggle, search, filter chips, exercise rows |
| `p_186`–`p_189` | Profile — grouped sections |

## Known limits — read before treating these as authoritative

- **Not pixel-exact.** A 560px crop upscaled from a browser rendering inside
  a 4K screen capture. Good for hierarchy, spacing proportion, colour and
  type treatment. Not good for measuring a padding value.
- **Coverage is only what the operator clicked.** Scanner, Exercise page,
  Workout Player, Rest Timer, Technique Coach, Progress, Progress Photos and
  Paywall are **not** in this set — the walkthrough did not open them.
- **`src/App.tsx` in the sibling zip outranks these.** It is the actual
  prototype source, 5471 lines, and it is exact where a screenshot is
  approximate. Use these frames to see intent; use `App.tsx` to settle a
  detail.

For the screens missing above, the prototype has to be run locally — it
ships a `vite` setup in `../../Review Existing Examples (Copy).zip`. That is
required before Ф3 (per-screen rebuild) and was deliberately not done for
Ф1, whose changes are global and already specified by the CSS tokens.
