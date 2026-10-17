# S03 lane L3: HUD primitives and window size class

Date: 2026-10-17. Kind: production code (UI), stories S03-03 and S03-02.

## What changed
- mobile/lib/shared/widgets/hud/hud_surface.dart: `HudKeyboardActivation` becomes a stateful widget with optional focus ring (`showFocusRing`), hover wash (`hoverStyle`), mouse cursor, key handling switch and border radius; `HudButton`, `HudChip` and `HudPanel` get optional minimum height, semantic hint, selected, enabled and the same three extras. All defaults reproduce the previous behaviour.
- mobile/lib/shared/widgets/hud/hud_metric.dart: `HudSettingRow` gets `mergeSemantics`, `trailingLabel`, `semanticHint`, `enabled`, `selected` and the extras.
- mobile/lib/shared/widgets/window_size.dart (new): `WindowSizeClass`, `WindowSizeInfo`, `classifyWindow`, `WindowSizeScope` (inherited model), `WindowSizeAspect`, `windowSizeOverrideProvider`.

## Why
Stories S03-03 and S03-02 of the S03 design (section 2.6, UI contract 9.1): the shell and the new screens need a visible keyboard focus, hover and richer semantics on the shared controls, and one place that classifies the window.

## Affected contracts and paths
No call site uses the new parameters or `WindowSizeScope` yet; later lanes (L4a, L4b, L5 and following) wire them. `hud_scaffold.dart` is untouched.

## Verification state
Nothing was run by the coordinator or the implementation agent. The tests (S03-02, S03-03) are written and run by the test agents after epic 3; until then the status is NOT_RUN.
