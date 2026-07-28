---
description: Canonical verify loop before claiming any change is done — analyze, test, doc audit, UI check
---

The full "is it actually done?" sequence for this repo. Run **all** applicable steps; a passing
`flutter test` alone does not mean a change works.

## 1. Static + unit/widget

```powershell
cd "D:\test 2\Fitness App\mobile"
flutter analyze
flutter test
```

Or the wrapper, which writes a triage report to `logs/test_runs/<timestamp>/`:

```powershell
pwsh .\scripts\dev\run_tests.ps1
```

> `run_tests.ps1` accepts `-Integration`, but **do not use it** — `mobile/integration_test/` does
> not exist in this repo, so that switch has nothing to run. `mobile/test/` (71 files) is the only
> suite.

0 failures is the bar. Do not report a pass count you did not just produce.

## 2. Docs still consistent

```powershell
pwsh .\scripts\dev\audit_doc_links.ps1
```

Exit 0 required. FAIL means a doc points at a path that no longer exists — if you moved, renamed or
deleted a file, fix the docs in the *same* commit. If you added or removed a feature, also update
the tables in `core/CODEMAP.md`; the audit cannot detect a feature you forgot to add.

## 3. UI changes — build and look at it

`flutter analyze` + `flutter test` passing does **not** prove a screen renders. For any UI change,
build and install on the `Pixel_API_34` emulator and visually verify:

```powershell
pwsh .\scripts\dev\run_app.ps1 -Session verify
```

Full restart, not hot reload — a stale process serves old code and produces both false passes and
false failures.

## 4. If anything failed

Start the debug daemon and reproduce rather than guessing — see `/fitness-debug-daemon` and
`core/DEBUGGING.md`. Reading the captured session log before theorising is a project rule.

## 5. Optional — repo context health

```powershell
pwsh .\scripts\dev\measure_context.ps1 -Csv core\context_baseline.csv
```

Tracks the AI-context cost of the repo over time. Worth running after any large doc change.
