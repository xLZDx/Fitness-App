# Session state — 2026-07-29 (Fitness App)

Checkpoint so a fresh session can pick this up without re-deriving anything.
Written mid-session; the last two gates were still running when this was saved.

## Commit state

**14 commits local, NOTHING pushed.** The operator has not given a `push` at any
point today — one message contained the word inside a quote of my own sentence,
which does not release the gate. Ask for a clean `push` before sending anything.

```
a11d386 feat(catalog): 66 exercises with looping demos + muscle map
84c2247 feat(scan): live camera recognition + recognition history
5e90a01 feat(auth): real Google sign-in (plugin v7 + SHA registration)
c4ce7e7 chore(release): build 1.0.0+3
0b6c239 feat(scan): ship equipment_v1 model + fix blank Scan page
6db22db feat(scan): camera-first equipment recognition
9d807f6 fix(nav): push-navigation + root back fallback
c61e51a fix(health): Health Connect - FragmentActivity + manifest + errors
05f14cc chore(release): build 1.0.0+2
a0f22a5 fix(profile): dynamic broke enum .name
5c0e991 build(android): R8 release fix (tflite GPU dontwarn)
8f7701d test(functions): jest suite for 4 callables (ticket #9)
```

## What shipped today

| Area | State |
|---|---|
| Stripe Phase 4B | Deployed: rules + 10 functions live, webhook on 6 events with the real signing secret. Smoke test on a phone still not done by the operator. |
| Cloud Function tests | 22 jest tests over 4 callables. 6 functions still uncovered (listed in NEXT_TICKETS #9). |
| Navigation | 35 call sites audited, 27 converted to push, root back-fallback in MainShell. |
| Health Connect | FlutterFragmentActivity + manifest declarations + error surfacing. **Operator step: Samsung Health -> Settings -> Health Connect -> link.** |
| Scan | Camera-first recognition, QR demoted to background, live mode with vote smoothing, recognition history. |
| equipment_v1 model | MobileNetV2, 1741 web photos, top-1 0.617 / top-3 0.835 stratified holdout. Trained here; pipeline lives OUTSIDE the repo at `D:\tools\equipment-model\`. |
| Catalog | 12 -> 66 exercises with two-frame looping demos + muscle map. |
| Google sign-in | Wired against plugin v7, SHAs registered. **Operator step: enable the Google provider in Firebase Console -> Authentication.** |
| App Distribution | Three builds delivered (1.0.0+1/+2/+3) to korostelevivan@gmail.com. |

## Still open

- **Gate FORM** and **Gate RU** were in flight when this was written — check
  `git log` and the working tree before assuming either landed.
- Operator-side: enable Google provider; link Samsung Health; run the Stripe
  smoke test; create the 5 annual/family/lifetime Stripe prices (their secrets
  currently hold loud `price_PLACEHOLDER_*` values so a purchase fails clearly).
- `tierFromSubscription` (`functions/src/index.ts`) only knows the two monthly
  price ids — an annual/family subscriber would be written as tier `free`. Fix
  this TOGETHER with creating those prices, not after.
- Firestore rules: `donor_wall` has no rule (the Donor Wall page will hit
  permission-denied) and `users/{uid}/receipts` is client-writable. Both were
  found by the review panel; the operator chose to deploy without the patch.
- HRV on Android reads `SDNN`, which Health Connect does not support (`RMSSD`
  is the Android type) — confirmed in the emulator logs.
- The muscle map draws boxes, not anatomy; fine as a v1, obvious upgrade path.

## Environment gotchas that cost real time today

- **Norton intercepts HTTPS.** Its root CA is in the Windows store, so browsers
  are fine, but anything with its own trust store fails: Gradle (fixed via
  `D:\.gradle\gradle.properties` pointing at `D:\tools\java-truststore\cacerts.jks`),
  pip (fixed via `D:\tools\ml-train-env\pip.ini`), and the Android emulator
  (Firebase login broke until the operator added a Norton exclusion). If a
  download fails with a certificate error, this is why.
- `flutter emulators --launch` can leave a wedged instance; kill
  `qemu-system-x86_64` and cold-boot with `-no-snapshot-load`.
- MediaStore on the API-34 emulator ignores the deprecated media-scan broadcast,
  so files pushed to `/sdcard/Pictures` never appear in the photo picker.

## Two traps worth remembering

1. **The app theme sets button `minimumSize: Size.fromHeight(54)`, i.e. minWidth
   = infinity.** Any button placed where width is unbounded (a Row's non-flex
   slot) forces an infinite width and the WHOLE page silently fails to lay out —
   blank screen, no red error. Always bound button width outside `Expanded`.
2. **Widget tests must pump `AppTheme.light()`**, not the default theme. A
   default-theme test stayed green while the real app rendered nothing, because
   the default theme has no such minimumSize.

## Model retraining

`D:\tools\equipment-model\` — crawl -> clean -> train_export -> attach_metadata.
Python 3.11 venv at `D:\tools\ml-train-env`. The first run reported 0.774 and it
was wrong: train and val were built with mismatched shuffle flags, giving a
non-stratified split with overlap. The trainer now raises if any class is
missing from validation. **Never report an aggregate accuracy without the
per-class breakdown next to it.**
