# Dev observability — debug daemon

Captures everything you need to diagnose a session — Flutter logs,
crashes, touch events, periodic screenshots, and Cloud Functions logs —
into one timestamped folder under `logs/sessions/`.

The whole point: the next time something breaks (like the
"`cloud_firestore/permission-denied`" or "`firebase_functions/
unauthenticated`" snackbars we just hit), you'll have the exact log
line + a screencap from the moment it fired, sitting in a folder ready
to share or grep.

## TL;DR

```powershell
# Fresh install + clear + launch + start capturing.
pwsh .\scripts\dev\run_app.ps1 -Session stripe-flow

# Or just attach the daemon to an already-running app.
pwsh .\scripts\dev\debug_daemon.ps1 -Session whatever
```

Hit **Ctrl+C** to stop. Captures live at
`logs/sessions/<yyyyMMdd-HHmmss>-<session>/`.

## What you get per session

| File / pattern         | What's in it |
| ---------------------- | ------------ |
| `flutter.log`          | Curated logcat: `flutter`, `AndroidRuntime`, `FlutterActivityAndFragmentDelegate`, `FirebaseAuth`, `FirebaseFirestore`, `CloudFunctions` (everything else is silenced). |
| `errors.log`           | Broader net — every `ERROR`/`FATAL` line across all tags. Catches native crashes / system denials that don't surface in the curated stream. |
| `touches.log`          | Raw `getevent -lt` output filtered to `BTN_TOUCH` + `ABS_MT_POSITION_X/Y`. Pair with `flutter.log` timestamps to see which tap caused the next stack trace. |
| `screencap-NNNN-HHMMSS.png` | Full-screen capture every 30 s. Visual context for what was on screen when an error fired. |
| `functions.log`        | Cloud Functions log lines polled every 30 s (de-duplicated). |
| `meta.json`            | Session start time, emulator serial, app package + version. |

The daemon also enables **Show taps** and **Pointer location** developer
options on the emulator while it's running, so screencaps overlay the
exact tap point. Both are reset on Ctrl+C.

## Common workflows

### "I'm about to test something flaky"

Run a named session before you start tapping:

```powershell
pwsh .\scripts\dev\run_app.ps1 -Session subscription-cancel
```

The terminal turns into a live tail of `flutter.log`. Reproduce the
issue, then Ctrl+C. Hand the session folder (or a single
`screencap-XXXX.png` + the relevant `flutter.log` lines) to whoever's
debugging.

### "Something just broke and I want to see what happened"

The daemon must already be running before the failure for the capture
to include it. If it isn't, start it now and **reproduce** the bug —
it doesn't have to be on the original session.

If you can't reproduce, fall back on:

```powershell
D:\android-sdk\platform-tools\adb.exe -s emulator-5556 logcat -d -t 500 -s flutter:* AndroidRuntime:*
```

(`-d` dumps the existing buffer, `-t 500` shows the last 500 lines.
You'll lose anything older than the device buffer, ~100 KB by default.)

### "Cloud Functions failed but the app didn't crash"

The daemon polls `firebase functions:log` every 30 s into
`functions.log`. For a faster turnaround, run it manually:

```powershell
firebase functions:log --only createCheckoutSession --project traidingbot-b4061
```

## Customisation

All knobs are PowerShell parameters on `debug_daemon.ps1`:

```powershell
pwsh .\scripts\dev\debug_daemon.ps1 `
    -Session quick-check `
    -EmulatorSerial emulator-5556 `
    -Package com.fitnessapp.fitness_app `
    -Project traidingbot-b4061 `
    -ScreenshotInterval 10 `      # default 30 s
    -FunctionsPollInterval 60     # default 30 s
```

## What the daemon does NOT capture (and why)

- **Network requests at the wire level.** Capturing TLS-encrypted HTTPS
  to Stripe / Firebase requires a proxy + cert install. Out of scope —
  the relevant signal already lands in `flutter.log` (request path) and
  `functions.log` (server side).
- **Firestore rule denials with offending paths.** Firestore client SDK
  surfaces "permission-denied" without saying which rule fired; the
  matching server log line lands in `functions.log` (audit log) only
  for Admin-SDK writes, not client writes. For client-write denials the
  fix is to read the snackbar in `flutter.log` + cross-reference
  `firestore.rules` manually.
- **Widget tree state.** For that, run `flutter run` separately and
  open Flutter DevTools — it complements but doesn't replace this
  daemon.

## Lessons captured this way (so we don't repeat them)

- **2026-05-09** — `cloud_firestore/permission-denied` when tapping
  "Start trial". Root cause: Phase 4B tightened firestore.rules to
  deny client writes to `users/{uid}/subscription/**`, but
  `SubscriptionAction.startTrial()` was still calling repo.save()
  directly. Fixed in commit `4f42ef6` by routing trials through a new
  `startFreeTrial` Cloud Function.
- **2026-05-09** — `firebase_functions/unauthenticated` when tapping
  "Choose Celebrity" after a Standard checkout. Root cause: anonymous
  Firebase tokens last only 1 hour; the auto-refresh lagged after the
  user bounced through Stripe Checkout in the browser. Fixed in commit
  `4a38fe2` with two layers: (1) UI gate — subscribed users now route
  through the Stripe Customer Portal, never a fresh checkout; (2)
  defense — `CloudFunctionsStripeService` now calls
  `user.getIdToken(true)` before every callable.
- **2026-05-09** — `firebase_functions/failed-precondition: No Stripe
  customer on file` when tapping "Manage subscription" on a trial-only
  account. Root cause: the trial path goes through `startFreeTrial`
  which writes the Firestore subscription doc directly without any
  Stripe call, so no customer is created. The Stripe portal can't
  manage a customer that doesn't exist. Fix: `SubscriptionPage` now
  branches on actual status — trial users see `_UpgradeFromTrialCard`
  (a "Subscribe to keep $tier" CTA that runs Stripe Checkout for the
  same tier they're trialing); the webhook overwrites the trial doc
  with active state. Only `active` / `cancelled` users see the Manage
  card.
- **2026-05-09** — Captured logs unreadable: `flutter.log` looked like
  UTF-16 with spaces between every character. Root cause: Windows
  PowerShell 5.1 `Tee-Object` defaults to UTF-16-LE encoding for file
  output. Fix: replace `Tee-Object -FilePath` with `ForEach-Object {
  Add-Content -Path $LogPath -Value $_ -Encoding utf8 }` so every
  capture writes plain UTF-8 that `grep` / `tail` understand.
