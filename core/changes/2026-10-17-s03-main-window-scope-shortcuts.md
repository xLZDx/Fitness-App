# S03 main.dart: window scope, shortcuts, resume refresh

Date: 2026-10-17. Kind: production code (wiring), stories S03-02, S03-13, S03-17.

## What changed
- mobile/lib/main.dart: three imports; builder wraps content in WindowSizeScope and AppShortcuts; app resume calls the digest refresh (unawaited, guarded).

## Why
The window class must be live above the router, the shortcut layer must see the router, and dashboards must be fresh after resume (design 2.6, 3.7).

## Affected contracts and paths
Touch behaviour is unchanged; no second WidgetsBindingObserver.

## Verification state
Nothing was run; NOT_RUN until the test agents.
