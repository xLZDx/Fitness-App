# Plan — nine device-reported defects (2026-07-30)

Operator reported nine items after testing release **1.0.0 (4)** on a real phone.
Five of the nine are defects I shipped while reporting the features as working.
Root cause for every item was verified against source before this plan was written.

`GO ALL по порядку` given 2026-07-30. Gates run in the operator's order.

---

## Why the previous verification failed

487 widget/unit tests + `flutter analyze` were green. Neither touches:

* the **native ML Kit bridge** (a Dart-side `InputImage` is accepted by the fake, rejected by Android), or
* the **asset bundle** (`Image.asset` resolves from the built manifest, not from the filesystem).

So two shipped features could never have worked on a device, and the suite could not
see it. Gates 3 and 9 add the two missing kinds of proof: an asset-manifest assertion
and real emulator drive tests.

---

## Verified root causes

| # | Symptom | Root cause | Evidence |
|---|---|---|---|
| 1 | `ImageFormat is not supported.` in Live mode | Android impl is `camera_android_camerax 0.6.17`, which **ignores** `imageFormatGroup` and always emits YUV_420_888. Code concatenated 3 planes and declared the format from `image.format.raw` (=35). Native accepts only NV21(17)/YV12. | `android_camera_camerax.dart:450-453`; `InputImageConverter.java:111,119`; `mlkit_live_equipment_service.dart:162` |
| 1b | AI form coach silently dead | Same conversion defect, errors swallowed | `mlkit_pose_detector_service.dart:104-108`, `:83` |
| 2 | Settings tile inert | `onTap: () {}`; no settings page exists | `profile_page.dart:148` |
| 3 | "Demo unavailable" on every exercise | pubspec `- assets/exercises/` is non-recursive; frames live in per-exercise subdirs, so 0 of 132 reached the APK | built `AssetManifest.json`: `assets/data/*`=2, `assets/exercises/*`=0 |
| 4 | Health Connect never connects | `HEART_RATE_VARIABILITY_SDNN` is iOS-only; native builds permissions via `mapToType[key]!!` → NPE kills the whole request | `heath_data_types.dart:171` vs `:223`; `HealthPlugin.kt:2413`, `:615` |
| 5 | Suggestion tiles inert | Hardcoded `static const _suggestions`, `onTap: () {}` | `home_page.dart:29-39`, `:353` |
| 6 | Muscle map looks bad | 14 axis-aligned `Rect.fromLTWH` blobs on a rounded box | `muscle_map.dart:63-80` |
| 7 | Scrolling janks | Every `GlassCard` = `BackdropFilter(sigma 28)` (11 on the workout page); `ScrollDimList` adds `ImageFiltered`+`Opacity`+2×`Transform` per non-focused card and `setState`s the list on every scroll tick | `glass.dart:57`; `scroll_dim_list.dart:67-91`, `:157-171` |
| 8 | Interface still English | 18 keys in `app_ru.arb`, ~300 strings hardcoded | `lib/l10n/*.arb` |
| 9 | No workflow tests | No `integration_test/`, package absent | `pubspec.yaml` |

---

## Gates

| Gate | Scope | Proof required |
|---|---|---|
| **1 LIVE** | Pure-Dart YUV_420_888 -> NV21 converter (rowStride/pixelStride aware), shared by the labeler and the pose detector; declare the format explicitly; stop swallowing persistent native errors in the pose path | converter unit tests on synthetic planes + on-device run |
| **2 SETTINGS** | Real `/settings` page: theme, language, notifications, units, sign-out, about | widget tests + live walk |
| **3 VIDEO** | Flatten frames to `assets/exercises/<slug>_<n>.jpg`, rewrite the catalog generator, **plus a test asserting every JSON frame path is in the built manifest** | manifest assertion test |
| **4 HEALTH** | SDNN -> RMSSD, filter every requested type through `isDataTypeAvailable`, `configure()` before first use, actionable diagnostics instead of a bare "denied" | filter unit tests + operator's phone |
| **5 SUGGEST** | Generate suggestions from intake + progress; each opens a real workout | generator tests + tap tests |
| **6 MUSCLE** | Anatomical `Path` silhouette, 14 groups, front/back | screenshot to operator before commit |
| **7 PERF** | Remove scroll blur entirely; `BackdropFilter` only on app bar + nav bar; cards on a cheap fill | frame-timing before/after |
| **8 RU** | ~300 strings. Split into 5 sub-gates: 8a core+home, 8b exercises+scan, 8c profile+settings, 8d onboarding+health, 8e progress+rest | tests move from text to `Key` |
| **9 E2E** | `integration_test` + emulator drive: onboarding -> home -> scan -> workout -> progress -> profile -> settings, language switch | real run, log in the report |

Gate 8 exceeds the A3 scope trigger (15+ files) on its own, hence the five sub-gates.
Order is the operator's and is also correct technically: tests last, so gates 7 and 8
do not invalidate them.

---

## Standing constraints

* Local commit per gate, then STOP. **No push** without a separate literal `push`.
* 17 commits from 2026-07-29 are still local and unpushed; this plan adds more on top.
* Testnet/test-key only; no live payment paths touched.

---

## Progress log (2026-07-30)

Gates 1-7 built, verified and committed locally. **Nothing pushed** — no `push` given.

| Gate | Commit | Proof |
|---|---|---|
| 1 LIVE | `f0180b5` | 8 converter tests + 3 error-surfacing; one test pins that the old concatenation had the wrong buffer length. Device proof deferred to gate 9 |
| 2 SETTINGS | `49695d0` | 14 unit + 7 widget; theme/locale taps proven to reach the real MaterialApp; navigation test confirmed failing pre-fix via git stash |
| 3 VIDEO | `09c301a` | 132 frames flattened; bundle assertion test through rootBundle; nested path confirmed unloadable before the fix |
| 4 HEALTH | `e8f5d4b` | 29 health tests; guard test mutation-checked by restoring SDNN |
| 5 SUGGEST | `8f51a07` | 16 builder tests + 2 rewritten widget tests; replaced the test that asserted five fake titles |
| 6 MUSCLE | `647ccc6` | 10 geometry/widget tests, mutation-checked; verified by rendering to PNG twice (lower body, upper body) |
| 7 PERF | `a3fc751` | BackdropFilter count on a card page measured 11 -> 0; budget pinned in blur_budget_test |

Suite: **571/571**. Analyzer: the same 4 pre-existing issues throughout.

### Deliberate non-goals, stated rather than silently dropped

* **No units toggle** in Settings — nothing in the app reads a unit preference
  (grepped: no kg/lb formatting anywhere), so it would be another inert control.
* **No fake exercise video.** `videoUrl` and a real `video_player` block exist but
  no exercise has a URL: free-exercise-db ships two stills per exercise and no
  clips, and there is no free licensed source to bundle. The looped frame demo
  (play/pause, 0.5x/1x/2x) is the on-device demo. A real video library needs a
  licensing or user-contribution decision from the operator.

### Gate 8 scope, measured

227 distinct user-facing English literals across 44 files. Sub-gates:
8a core+home+settings, 8b exercises+scan, 8c health+progress+form-check,
8d onboarding+auth+subscription, 8e secondary pages (about, donors, community,
marketplace, moderation, celebrity plans, contribute, photos, planner, moments).

### Environment gotchas that cost time before

* Antivirus HTTPS interception breaks Gradle/pip trust stores. Java truststore
  with the extra root at `D:\tools\java-truststore\cacerts.jks`, referenced from
  `D:\.gradle\gradle.properties` — `GRADLE_USER_HOME` is `D:\.gradle`, so a
  profile-directory `gradle.properties` is NOT read.
* Release build needs `proguard-rules.pro` with `-dontwarn org.tensorflow.lite.gpu.**`.
* An emulator (`Pixel_API_34`, `emulator-5554`) is already running from the
  previous session; launching the same AVD again fails with FATAL unless `-read-only`.
* `boundary.toImage()` under `flutter test` must run inside `tester.runAsync`,
  otherwise its future never completes and the test hangs.
* Text renders as grey boxes in `flutter test` renders — no font is loaded there.
  That is the harness, not the widget.

---

## Final state (2026-07-30) — all nine gates closed

| Gate | Commit | Proof |
|---|---|---|
| 8 RU | `7d10288` | 208 keys / 40 files via committed tooling; +15 keys in `7f7eecf`; completeness guard test |
| device fixes | `7f7eecf` | ref-after-dispose in FormCheckPage + 13 ternary-hidden strings |
| 9 E2E | `87b8bc9` | **8/8 on Pixel API 34** |
| release | `60e21f9` | 1.0.0+5 |

Host suite **579/579**. Analyzer: the same 4 pre-existing issues, unchanged all day.

### What the on-device suite proved that the host suite could not

* live recognition runs with no `ImageFormat is not supported.` (gate 1)
* all **132** demo frames load from the installed APK via `rootBundle` (gate 3)
* the 4.3 MB recognition model is in the APK, not a placeholder
* the muscle map's `Path.combine` clipping survives a real graphics backend
* the language switch retranslates a live UI
* and it found a real crash the host suite structurally could not see:
  `FormCheckPage.dispose()` reading a provider after disposal.

### l10n tooling — how to continue

```
python scripts/l10n/extract_strings.py     # refresh spec (keeps existing ru)
# fill scripts/l10n/ru.json
python scripts/l10n/apply_strings.py       # patch call sites + ARB
python scripts/l10n/fix_const.py           # analyzer-driven const cleanup
```

Invariant to preserve: **the English ARB value equals the old literal byte for
byte**, so host tests that assert English keep passing.

Known extractor blind spots (both bit once already, both now documented in the
script): literals behind a ternary (`label: x ? 'a' : 'b'`) and prose in `body:`
arguments.

### Still English, by decision

* `about_page` principles + 3 seed-data repositories (celebrity plans, donor
  tiers, injury protocols) — prose lives in `body:` args; translated headings
  over English paragraphs read worse than consistent English.
* 65 interpolated strings — need ARB placeholders.

### Operator actions still outstanding

1. Firebase Console -> Authentication -> enable the Google provider.
2. Samsung Health -> Settings -> Health Connect -> allow.
3. Create the 5 annual/family/lifetime Stripe prices **and fix
   `tierFromSubscription`** at the same time (functions/src/index.ts:356-361
   matches only the two monthly price ids, so an annual subscriber would be
   written as tier `free`).
4. Deferred from the 2026-07-29 review, still open: Firestore rules for
   `donor_wall` (Donor Wall page will hit permission-denied),
   `payment_intent.payment_failed` unhandled, Node 20 runtime decommissioned
   2026-10-30.

### Push status

**30 commits local, zero pushed.** No `push` has ever been given for any of them.
