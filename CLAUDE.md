> **Inherits global rules from `D:\test 2\CLAUDE.md`** — approval gate, no-guessing, regression tests, git lifecycle (including todo-in-commits), shell pre-approval, D:-drive-only disk policy. Read that file too.

# Fitness App — Project Context

## Layout
- Project root: `D:\test 2\Fitness App`
- Mobile app: `mobile/` (Flutter)
- Cloud Functions: `functions/` (TypeScript)
- Plans & docs: `core/`
- Per-session debug logs: `logs/sessions/<latest>/`

## Stack
- Flutter 3.x + Dart + Riverpod + go_router
- Firebase: Auth / Firestore / Storage / Functions(TS)
- Stripe (test mode) for payments. App Store IAP planned for iOS.

## Cross-platform principle — design for iOS too
Android ships first, iOS is on the roadmap. Every package + abstraction choice must accommodate iOS from day one:
- Default to packages listing both `android` and `ios` platform support in `pubspec`.
- No Android-only API references in shared code.
- Abstraction layer for Health Connect ↔ HealthKit (`HealthService` interface, platform-specific impls).
- Wear OS first, Apple Watch parity later — design phone-side comms as a generic interface.
- Cupertino-style fallbacks where Material conventions are too Android (date pickers, switches, action sheets) — Material everywhere for now, switch selectively when iOS spins up.
- Plan for App Store IAP alongside Stripe — `SubscriptionAction` is the abstract surface; `StoreKitCheckoutService` alongside `CloudFunctionsStripeService`.

## Debug daemon (READ FIRST for bug reports)
- Runbook: `core/DEBUGGING.md`.
- Launcher: `scripts/dev/debug_daemon.ps1`.
- Captures per-session: flutter logs, errors, touches, screencaps, Cloud Functions logs in `logs/sessions/<latest>/`.
- For any bug report, read the latest session log **before** guessing.

## Stripe test mode
- Price IDs documented in `core/PHASE_4B_STRIPE_SETUP.md`.
- Secrets via env vars (`.env`, never committed; `.env.example` for templates).

## Plan & reference docs
- `core/ROADMAP_2026_V2.md` — sequenced P0/P1/P2 + 7 Tier-X game-changers.
- `core/COMPETITIVE_ASSESSMENT.md` — vs 15 competitors; QR-scan + injury-filter are moats.
- `core/NONPROFIT_PLAN.md` — 501(c)(3) / fiscal-sponsor strategy.
- `core/IMPLEMENTATION_PLAN.md` — live phase/sequence roadmap.
- Master 75-feature list: `FITNESS_APP_TASK_LIST.md` (lives in trading-assistance dir for historical reasons).

## Toolchain (D: drive only — see global disk policy)
- Flutter SDK: `D:\flutter`
- Android SDK: `D:\android-sdk`
- AVD: `Pixel_API_34` (lives under `D:\android-sdk\avd`)
- Pin env vars to D:: `PUB_CACHE`, `GRADLE_USER_HOME`, `TEMP`, `TMP`, `ANDROID_AVD_HOME`, `ANDROID_SDK_ROOT`, `FLUTTER_ROOT`.
- JDK is system-installed at `C:\Program Files\Microsoft\jdk-17.0.18.8-hotspot` (read-only OS bridge — acceptable per global policy; no project data lands there).

## Tests
- `mobile/test/` — Flutter widget + unit tests.
- `mobile/integration_test/` — integration tests.
- `flutter analyze` + `flutter test` after every change. 0 failures required.
- For UI changes: build APK + install on emulator (`Pixel_API_34`) and visually verify.
