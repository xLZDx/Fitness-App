> **Inherits global rules from `D:\test 2\CLAUDE.md`** — approval gate, no-guessing, regression
> tests, git lifecycle (including todo-in-commits), shell pre-approval. Read that file too.

# Fitness App — router

This file is deliberately thin: it is re-sent on **every** turn, so detail lives in `core/` and is
read on demand. Start with the table below.

| Need | Go to |
|---|---|
| **Which file do I open?** — 33 features, 22 routes, entry points | `core/CODEMAP.md` |
| The rules a change is reviewed against (layout, iOS portability, injury filtering, testing) | `core/CONVENTIONS.md` |
| Index of all docs, tiered by who reads them | `core/INDEX.md` |
| Stack versions, key decisions, toolchain paths | `core/TECHSTACK.md` |
| **Any bug report — read this before theorising** | `core/DEBUGGING.md` |
| Stripe test-mode price IDs and secret slots | `core/PHASE_4B_STRIPE_SETUP.md` |
| What to build next | `core/plans/` |
| Conventions for non-Claude agents + the agent cadence | `AGENTS.md` |
| Master 75-feature list | `FITNESS_APP_TASK_LIST.md` (repo root, tracked) |

`core/business/` holds positioning, competitor and fundraising material. It contains **no
engineering facts** — skip it for code work.

## Facts worth not re-deriving

- **Layout:** `mobile/` Flutter app · `functions/` Cloud Functions (TypeScript) · `wear/` Wear OS
  companion (Kotlin) · `core/` docs · `scripts/` PowerShell dev+ops · `logs/sessions/<latest>/`
  per-session debug captures.
- **Stack:** Flutter + Dart, Riverpod for state, go_router for routing, Firebase
  (Auth/Firestore/Storage/Functions), Stripe in **test mode**.
- **Android ships first, but every choice must accommodate iOS** — full rule in
  `core/CONVENTIONS.md`. The `HealthService` interface is the Health Connect ↔ HealthKit seam;
  do not bypass it.
- **Tests:** `mobile/test/` (129 files, 1002 tests) runs on the host — `flutter test`. There IS also
  `mobile/integration_test/app_test.dart`, which drives the real app on a device or emulator and is
  the only thing that can see the native ML Kit bridge and what actually ends up in the APK. It
  needs hardware; `flutter test` does not run it.
- **Verify loop:** `/fitness-verify` — analyze, test, `scripts/dev/audit_doc_links.ps1`, and a real
  build+install on `Pixel_API_34` for UI changes.

## Keeping docs true

Adding or removing a feature means updating `core/CODEMAP.md` in the same commit. Moving or
deleting anything a doc names means `scripts/dev/audit_doc_links.ps1` must still exit 0.
