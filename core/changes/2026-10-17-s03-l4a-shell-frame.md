# S03 lane L4a: shell frame

Date: 2026-10-17. Kind: production code (UI), stories S03-04 and S03-05.

## What changed
- mobile/lib/shared/widgets/shell_destinations.dart (new): the single destinations list and helpers.
- mobile/lib/shared/widgets/shell_layout.dart (new): `ShellLayout`, the rail label measurer seam, the rail form rule and the memo.
- mobile/lib/shared/widgets/hud/hud_side_rail.dart (new): the rail widget.
- mobile/lib/shared/widgets/shell_dock.dart (new): the dock host and the Record sheet opener provider.
- mobile/lib/shared/widgets/main_shell.dart (rewritten): stateful shell that builds bar or rail from the list, keeps the route child under one GlobalKey, mounts the dock widgets of lane L4b; Back handling unchanged and outside the swap.
- mobile/lib/shared/widgets/hud/hud_scaffold.dart: `HudScreenBody` reads `ShellLayout` and keeps the old code when it is absent.

## Why
Stories S03-04 and S03-05 (design 2.6, contract 5.1, 5.3, 10.1, 10.4): the same five destinations as bottom bar on compact windows and as a side rail on wide or short windows, with the dock for Record and the running session.

## Affected contracts and paths
Back behaviour is unchanged by construction. Pages that use `HudScreenBody` get the same clearance as before in the bar presentation without a dock.

## Verification state
Nothing was run. The tests (DT-04-x, DT-05-x, back_navigation_test.dart as the gate) are written and run by the test agents after epics 4 and 5; until then NOT_RUN. The code needs the ARB keys of lane L13 to compile.
