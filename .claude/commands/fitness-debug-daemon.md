---
description: Launch the debug daemon to capture logs/errors/touches/screencaps for a dev session
---

Full runbook: `core/DEBUGGING.md` — read it first if this is unfamiliar. This command is the quick-start.

**Fresh install + clear + launch + start capturing:**
```powershell
pwsh .\scripts\dev\run_app.ps1 -Session <name>
```

**Or attach to an already-running app:**
```powershell
pwsh .\scripts\dev\debug_daemon.ps1 -Session <name>
```

Ctrl+C to stop. Captures land at `logs/sessions/<yyyyMMdd-HHmmss>-<session>/`:
- `flutter.log` — curated logcat (flutter/AndroidRuntime/Firebase tags)
- `errors.log` — every ERROR/FATAL line across all tags
- `touches.log` — raw tap events, cross-reference timestamps with `flutter.log`
- `screencap-NNNN-HHMMSS.png` — full-screen capture every 30s
- `functions.log` — Cloud Functions log lines, polled every 30s
- `meta.json` — session start time, emulator serial, app package + version

**For any bug report: read the latest session log BEFORE guessing at a root cause** — this is a MANDATORY
project rule, not a suggestion. `core/DEBUGGING.md` has a "Lessons captured this way" section with real
past root-causes (Firestore permission-denied, token refresh races, Windows encoding bugs in captured
logs) — check there first, the same class of bug has recurred before.

If the daemon wasn't running before a failure, start it now and reproduce — it doesn't have to be the
exact original session. Fallback if you can't reproduce:
```powershell
D:\android-sdk\platform-tools\adb.exe -s emulator-5556 logcat -d -t 500 -s flutter:* AndroidRuntime:*
```
