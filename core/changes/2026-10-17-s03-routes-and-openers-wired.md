# S03 routes and openers wired

Date: 2026-10-17. Kind: production code (wiring), stories S03-06, S03-08 to S03-11.

## What changed
- mobile/lib/core/router/s03_routes.dart: real pages for /mode-chooser, /mode-questions/:mode and /sources; stubs and the unused list removed.
- mobile/lib/main.dart: provider overrides for the mode switcher opener and the Record sheet opener.

## Why
The pages and sheets exist; the shortcut layer, the dock and the rail must reach them.

## Affected contracts and paths
Routes are reachable; the /mode-questions guard is unchanged.

## Verification state
Nothing was run; NOT_RUN until the test agents.
