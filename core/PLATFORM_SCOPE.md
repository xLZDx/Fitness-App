# Platform scope — what this product officially supports

**Status:** the official answer, as of 2026-08-11. P1c of
`core/plans/PLAN_AUDIT_2026-08-11_REMEDIATION.md`, closing audit item
`AUDIT_REPORT_2026-08-11.md:373` — *"Определить официальный scope
Android/iOS/Wear."*

This exists because "Android first, iOS on the roadmap" was the only written
answer, and it is not one. It does not say whether an iOS bug is a bug, whether
a Wear regression blocks a release, or what a tester is entitled to expect. Each
tier below answers those three questions.

---

## The tiers

| Platform | Tier | A defect here is | Blocks a release? |
|---|---|---|---|
| **Android phone** (API 26+) | **Supported** | a bug | yes |
| **iOS phone** | **Not shipped** | not a defect | no |
| **Wear OS** | **Broken, known** | a known gap | no |
| **Web / desktop** | **Out of scope** | not a defect | no |

### Android phone — Supported

The only tier where "it doesn't work" is a bug report.

- Ships through Firebase App Distribution today, Play later.
- `flutter test` (1,925 tests) and `flutter analyze` gate every change.
- Release builds go through `scripts/dev/build_release.ps1`, arm64 by default.
- **minSdk 26.** Below that is not tested and not supported.

### iOS phone — Not shipped, but not allowed to rot

The distinction that matters: iOS is **not a target for defect reports**, and
is **still a constraint on design**. Those are different things, and collapsing
them is what produces a codebase that cannot be ported when the time comes.

What holds today, and is enforced in review (`core/CONVENTIONS.md`):

- Health data goes through `HealthService`
  (`mobile/lib/core/health/health_service.dart`) — the Health Connect ↔
  HealthKit seam. Nothing calls a platform health API directly.
- New packages must declare iOS support. `flutter_secure_storage`, added in
  A2-sec, covers the iOS Keychain in the same call for exactly this reason.
- Platform-specific code sits behind an interface, never in a widget.

What is NOT true today, and should stop being implied anywhere:

- Nobody has built or run this on iOS. There is no signing setup, no
  provisioning profile, no App Store Connect entry, and IAP is unimplemented —
  Stripe cannot be used for digital goods on iOS, so the paywall needs a second
  payment path before iOS can ship at all.
- An iOS defect is therefore not a bug. It is a task in the porting project.

### Wear OS — In the repo, broken, and knowingly so

`wear/` (Kotlin) exists and pairing **does not work for release installs**.
Cause is measured, not guessed: `wear/build.gradle.kts` declares no
`signingConfig`, so its release build is debug-signed while the phone's is
signed with the upload key, and the Data Layer pairs on applicationId **and**
signing key. The ids match and `/workout_state` matches; signing is the
remaining condition.

Untouched on purpose — signing changes need their own explicit GO. Until then:

- Wear is not advertised to testers and does not appear in release notes as
  working.
- A Wear regression does not block a phone release.
- The one thing that must not happen is quietly shipping it as a feature.

### Web / desktop — Out of scope

Flutter builds them; this product does not support them. The camera, health,
BLE and ML paths have no meaningful web implementation, and a half-working web
build invites bug reports against a target nobody intends to serve.

---

## What this changes in practice

1. **Bug triage.** Android phone → triage normally. iOS → close as
   out-of-scope, link here. Wear pairing → known, link here.
2. **Release gating.** Only the Android suites gate a release. A red Wear build
   does not.
3. **Review.** "Does this work on iOS?" is not a blocker. "Does this make iOS
   impossible later?" is — that is the portability rule, and it stays.
4. **Release notes.** They describe Android. Wear is mentioned only when its
   signing gap is closed.

## When iOS moves tiers

Not a date. The preconditions, all of which are visible:

- A payment path that is not Stripe (StoreKit / App Store IAP), because
  Apple requires it for digital goods.
- Signing and provisioning set up, and a build produced on Apple hardware.
- The health, camera, BLE and ML Kit paths exercised on a real device — every
  one of them is a platform channel that has never executed on iOS.
- `mobile/test/` passing on macOS, which nothing has ever run.

Until all four exist, iOS stays "not shipped", and saying otherwise in a
README, a pitch deck or a release note is a claim the code does not support.
