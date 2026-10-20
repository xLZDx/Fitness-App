# Full Fitness App Audit — English Historical Translation

**Original:** [Fitness App full audit](AUDIT_REPORT_2026-08-11.md), Git blob `68361ea2042b9b46e7b4f19c59f22ce067a7bcdd`.  
**Original audit date:** **August 11, 2026**.  
**Historical final verdict:** **BLOCK — not ready for public production release at that checkpoint**.

**Source precedence:** This is a detailed English translation of a dated report, **not a fresh audit** of the latest Fitness App HEAD, an assertion that every historical defect remains open, or a claim that any historical test suite was rerun here. Every file/line reference and numerical result below is inherited from the original report; verify it against that exact historical source before attempting remediation. The reviewer-independence statements describe what the original report claimed, **not independently attested reviewer sessions conducted as part of this translation**.

## Executive summary

The source assessed Fitness App as a strong **Android private beta**, with substantial features, good localization, an established design system, **1,886 passing Flutter tests** and **107 passing backend tests**.

Public launch, particularly with real subscriptions, progress photos and advertised AI capabilities, was **not recommended**. The report described independent reviewer and subsequent adversarial-review findings concerning incomplete personal-data deletion, Stripe billing, Firebase production configuration and ML validation.

The claimed read-only reviewer-consensus workstreams were architecture/code/backend/security/Git; Flutter/UX/accessibility/performance; ML/E2E/functionality/silent failures; and a critical second adversarial pass. **FastAPI review was not applicable:** the backend used Firebase Authentication, Firestore and Node/TypeScript Cloud Functions, not FastAPI.

## Component status at the historical checkpoint

| Area | Source verdict |
| --- | --- |
| Core workout/catalog/profile flows | Substantive beta-stage capability |
| Flutter unit/widget suite | **1,886 green tests** |
| Backend Functions | Covered by tests; production deployment lagged behind |
| Stripe/subscriptions | **Release blocker** |
| Personal-data deletion/export | **Release blocker** |
| Progress photos | **Privacy blocker**; real-device capture verification needed |
| Equipment Scanner / Form Coach / Posture | Experimental; accuracy promises not validated |
| Social/community/marketplace | Largely mock/demo |
| Wear OS | Nonfunctional scaffold |
| iOS | Not supported at the checkpoint |
| E2E and release pipeline | Red, insufficient |

## Confirmed release blockers — original source findings

### 1. Account deletion left user-linked data behind

The source found `deleteAccount` removed only `users`, `donor_wall` and `coach_listings` while leaving `coach_bookings` and `equipment_reports`. On the client, the post-server-call path only signed out.

Source evidence:

- `functions/src/index.ts:1287-1332`
- `functions/src/__tests__/delete_account.test.ts:122-143`
- `mobile/lib/features/account_deletion/state/account_deletion_providers.dart:32-50`

The report additionally found incomplete local cleanup:

- Sensitive health blob remained on the device.
- Progress photos shared a directory and AES key **without UID separation**.
- Another account signing into the same device could potentially access the previous account's content.
- The server test encoded incomplete deletion as an expected result.

These behaviors conflicted with the "delete everything" promises in `public/privacy.html:65,85,88-89` and `public/terms.html:86`.

**Required action at that time:** Inventory and delete or intentionally anonymize **all** account-linked server/local data; make legal terms, UI copy and actual behavior agree.

### 2. Personal-data export was incomplete

The export contained profile, workouts, schedules, programs and photo **metadata**, but omitted image bytes and the following classes:

- Recognition history
- Saved machine cards and notes
- Generated exercises
- Subscriptions and receipts
- Equipment reports
- Coach bookings
- Donor entry
- Debug telemetry

Implementation reference: `mobile/lib/features/data_export/data_export.dart:13-22,33-86`.

The source required either a complete supported export contract **or** corrected legal and UI claims. It concluded the documented product contract and implementation did not match.

### 3. Multiple live Stripe subscriptions could be created

Checkout requests lacked an idempotency key and a server-side check for an already active subscription. The webhook stored only **one** `stripeSubscriptionId`; account deletion cancelled only that ID.

Original failure scenario:

1. The same user opened/repeated two Checkout sessions.
2. Stripe could create two recurring subscriptions.
3. The most recent webhook overwrote the single saved ID.
4. Account deletion cancelled only one subscription.
5. The other could continue charging although the user no longer had a usable app account.

Source locations:

- `functions/src/index.ts:413-457`
- `functions/src/index.ts:607-617`
- `functions/src/index.ts:1287-1300`

This was a **potential billing/data-lifecycle failure**, not proof that any particular customer was actually double-billed. The remedy required idempotent checkout, active-subscription reconciliation and cancelling **all** linked subscriptions.

### 4. Live production Firebase differed from the local repository

On **August 11, 2026**, the report found **App Check UNENFORCED** for Firebase AI/ML, Firestore and Identity Toolkit. Cloud Functions lacked `enforceAppCheck`; anonymous Firebase authentication was enabled.

This created an AI/Functions/trial **cost and abuse** exposure through automated anonymous-account rotation. It was **not** demonstrated as an actual Firestore Rules bypass.

Other reported deployment drift:

- Deployed Stripe Functions dated **August 5**.
- A key Acacia/Basil API compatibility fix from **August 8** had **not** been deployed.
- Live Firestore Rules lacked the local `debug_sessions` block.
- Hosted privacy/terms differed from local files.
- Documentation said App Check was already enforced even when the inspected live setup contradicted that claim.

These were **checkpoint observations**, not verified current cloud configuration.

### 5. ML features could not be advertised as validated

The source distinguished **three** methodological issues.

#### 5.1 Equipment recognition

Local recognition produced high-confidence out-of-distribution errors as high as **0.892**. Temporal smoothing tested answer consistency, not correctness or whether an image belonged to the known catalogue.

Live recognition was disabled by default, making this a **feature-level blocker**, not by itself a blocker for the entire mobile application.

Evidence:

- `mobile/lib/features/visual_equipment/data/mlkit_live_equipment_service.dart:116-129`
- `mobile/lib/features/visual_equipment/domain/live_recognition.dart:29-96`
- `mobile/lib/features/visual_equipment/state/live_equipment_providers.dart:41`

#### 5.2 Form Coach and repetition counting

MM-Fit evaluation used a **different** algorithm: averaged bilateral **3D** joint angles with a simple two-phase counter. Production used **one-sided 2D** input and a **four-phase** counter.

Reported accuracy figures from the former did **not** establish the quality of the latter.

Evidence:

- `scripts/pose/extract_mmfit_targets.py:104-136`
- `mobile/lib/features/form_check/data/measured_rep_configs.dart:103-228`
- `mobile/lib/features/form_check/domain/rep_counter.dart:224-387`

#### 5.3 Posture

Posture screening requested a **side-view** image, but shoulder/pelvis symmetry relies on **front-facing** geometry; forward-head assessment does require a profile. Calculating all measures from a single image introduced incompatible geometry.

Evidence:

- `mobile/lib/features/posture/domain/posture_metrics.dart:24-79`
- `mobile/lib/features/posture/data/measured_posture_config.dart:1-20`

## Progress Photos — correction after the adversarial review

The first reviewer pass called capture **guaranteed broken** because the sheet was closed, camera stopped, then `captureStill()` was called.

The adversarial pass **weakened that assertion**: the Future from a bottom sheet may resolve before final disposal finishes its reverse animation. Therefore **always returns null** was **not proven**. The narrower actual finding was a nondeterministic **capture/dispose ordering race**.

Source's retained outcome:

- A guaranteed failure was **not proven**.
- Ordering race remained.
- A complete `shutter → capture → encryption → visible tile` device test was absent.
- Real-device testing was required **before** choosing a fix.
- Privacy defects were independent of the capture race.

Privacy observations:

- AES key stored as base64 in `SharedPreferences`.
- Directory and key not scoped by UID.
- Plaintext camera temp file not deleted after encryption.
- Indexed photo metadata not encrypted.
- UI described the mechanism as **end-to-end encryption**, even though it was local at-rest encryption with the key stored near the data.

Original file/line references:

- `mobile/lib/features/progress_photos/widgets/photo_capture_sheet.dart:75-81,153-169`
- `mobile/lib/features/progress_photos/progress_photos_page.dart:81-89`
- `mobile/lib/features/progress_photos/state/progress_photos_providers.dart:69-75`
- `mobile/lib/features/progress_photos/data/photo_key_store.dart:8-65`
- `mobile/lib/features/progress_photos/data/local_progress_photos_repository.dart:35-39`

**Historical claim precision matters:** Do not silently transform this race into an "always fails" defect, or pretend local encryption is end-to-end.

## Functional and design gaps

### Product

- `/community` used an undisclosed in-memory mock: posts/likes vanished on restart and were invisible to other users.
- Marketplace/team feed were also mocks, though labeled as demos.
- **Edit health questionnaire** routed an already onboarded user back into onboarding, which immediately bounced to Home.
- Paywall sold a QR scanner feature the Scanner reported as removed.
- "AI Planner" used a deterministic greedy heuristic, ignored available user equipment and generated some English-only copy.
- Subscription load/error collapsed visually into **Free tier**, potentially restricting a paying customer incorrectly.
- Notification setting saved optimistically, without assuring permission or actual reminder scheduling.

Evidence:

- `mobile/lib/features/social_feed/state/social_feed_providers.dart:6-10`
- `mobile/lib/features/social_feed/data/social_feed_repository.dart:17-89`
- `mobile/lib/features/profile/profile_page.dart:90-101,176-189`
- `mobile/lib/core/router/app_router.dart:92-94,337-339`
- `mobile/lib/features/ai_planner/plan_builder.dart:19-98`
- `mobile/lib/features/subscription/state/subscription_providers.dart:36-41,102-103`

### UI and accessibility

- Home CTA overflow reproduced at **320 dp**, measured **19 px**, where `Row` text lacked `Flexible`/`Expanded`: `mobile/lib/features/home/home_page.dart:452-476`.
- Subscription error card had almost identical foreground/background colors and exposed raw exceptions/stack traces.
- Onboarding CTAs, choice selection, timer controls and difficulty options used bare `GestureDetector` without button/selected semantics, keyboard activation or disabled announcements.
- Some touch targets were **36–40 dp** instead of **44/48 dp**.
- Login was not scrollable and risked overflow with keyboard or larger text.
- Dynamic Form Coach/Posture outcomes were not live-region announced.
- Basic `ShellRoute` discarded tab scroll/filter/transient state when changing tabs.
- Runtime Google Fonts were not bundled; offline/TLS failure could trigger fallback and layout shift.

### Reliability and performance

- Optional services were awaited **before** `runApp`; Firebase/plugin/prefs/assets failure could strand the native splash without recovery UI.
- Progress Photo grid built the whole history and kept decrypted JPEG images in memory without bounded thumbnails/cache.
- Video cache lacked quota/LRU; `.part` files could remain after errors.
- `PoseDetector` might not close after failed camera start.
- AI Coach lacked timeout and could consume further Gemini requests after its sheet was closed.
- Providers frequently turned loading/errors into deceptive empty data through `.valueOrNull ?? []`.

### Platform scope

- iOS folder/configuration was absent and Firebase threw `UnsupportedError`. This was acceptable only if the actual product was formally **Android-only**, otherwise a platform-scope blocker.
- Wear OS remained a scaffold: missing Gradle wrapper, broken build script, no implemented Done action or actual production sync clients.
- Android compile SDK was **35** while `flutter_tts` required **36**.
- Release Gradle could fall back to debug signing when `key.properties` was missing.
- `npm audit --omit=dev` flagged **15 advisories: 1 critical, 3 high, 10 moderate, 1 low**. Reachability through any specific production handler was **not** individually proven.

## Backend, security and deployment findings

### App Check and abuse protection

- Live enforcement absent at that checkpoint.
- Client App Check activation did not equal server enforcement.
- Anonymous-account rotation bypassed a simple trial-per-UID budget.
- `maxInstances` bounded burn rate but did **not** replace quotas or abuse detection.

Recommended safeguards: staged enforcement, verified release attestations, per-UID/device/IP quotas, rotating-account trial protection and cost anomaly alerts.

### Stripe deployment

The deployed webhook lacked local Acacia/Basil helpers. That was a confirmed **deployment drift**; whether it caused an actual production incident depended on the real webhook API version.

Required before launch: verify Stripe endpoint API version and replay **test-mode** events for both supported formats.

### Invalid billing redirect domains

Billing Portal and Stripe Connect used `fitnessapp.example.com`:

- `functions/src/index.ts:495-498`
- `functions/src/index.ts:1031-1035`

On returning from the external Stripe flow a user could reach a browser error.

### Firestore Rules

- Ownership generally protected.
- Insufficient schema/type/size validation on user documents.
- No Rules emulator negative tests.
- Live rules differed from the source and did not allow `debug_sessions`, so live debug telemetry was **default-denied** at the checkpoint.

### Release integrity

- Release build could pass with **debug signing** if release keys were absent.
- Script did not verify the final APK/AAB signer.
- Script did not require clean Git and completed gates.
- Canonical debug daemon used a different Firebase project ID, `traidingbot-b4061`, potentially hiding real production errors.

## Historical test results — exact original counters

| Test/verification area | Original August 11 result |
| --- | --- |
| Flutter unit/widget | **1,886 / 1,886 PASS** |
| Firebase Functions Jest | **107 / 107 PASS** |
| TypeScript build | PASS |
| Catalogue pytest | **169 / 169 PASS** |
| Flutter analyze | **7 diagnostics**; no production compile errors |
| Android integration | **3 PASS / 7 FAIL**, **290.9 seconds** |
| Wear build | Failed immediately: missing `gradlew.bat` |
| Documentation link audit | Red, **87 current + 13 planned references**, with some validator false positives |
| ARB localization parity | **910/910 RU/EN keys** |

**Interpretation of 3 pass / 7 fail:** Not seven independent confirmed production defects.

- Home overflow was a **real** failure.
- A test expected the old singular Russian label for a workout, but the UI used plural; stale assertion.
- A test expected **only squat** when the product supported **six motions**; stale assertion.
- An older Home-copy expectation was also stale.
- Several scenarios failed in cascade due to shared `boot()`.

Nevertheless the **release integration gate was red**, and the suite barely covered real authentication, payment, photo capture, workout logging, community and posture.

## Confirmed silent failures

- Provider errors/loading silently looked like empty lists, Free tier or no data.
- Denied notification permission left a successfully saved session without a real reminder.
- Live `debug_sessions` denied by production Rules; upload error only printed locally.
- AI Coach could hang without timeout.
- Subscription error card revealed a technical exception instead of a safe recovery path.
- Scanner and Progress Photos left unencrypted plaintext temporary files.
- Runtime font download failure silently fell back to a different face/layout.

## Missing critical verification

- Complete delete/export inventory for every server/local collection.
- Account A → delete/sign out → Account B isolation **on the same device**.
- Two concurrent Checkout sessions and deletion with several active subscriptions.
- Stripe Acacia/Basil webhook test-mode replay.
- Billing Portal/Connect redirect contract tests.
- Firestore emulator Rules negative cases.
- App Check enforcement and trial/quota abuse scenarios.
- Hosted legal text/rules/functions deployment-drift checks.
- Final APK/AAB signing-identity verification.
- End-to-end photo shutter → capture → encryption → visible tile.
- Capture timeout/null/permission denial with visible recovery.
- Real auth/onboarding/profile offline/error behavior.
- Subscription purchase, restore, downgrade and revoked entitlement.
- Notification denial/re-enable/reboot reconciliation.
- Camera/ML retry and background/foreground leak tests on hardware.
- **320 dp**, landscape, split-screen and **200–300%** text scale.
- Semantics, keyboard focus traversal/restoration and live-region tests.
- **50–200** high-resolution photo heap/jank profiling.
- Offline cold start without font cache.
- Real Wear round trip and real iOS smoke if those platforms are in scope.

## What the audit found to be working well

- Large unit/widget suite green at the historical snapshot.
- RU/EN ARB key parity complete.
- Camera session readiness, watchdog and lifecycle safeguards.
- Posture page handles pause/resume and stale async starts carefully.
- Form Coach distinguishes per-frame noise from per-rep verdict.
- Navigation has selected/button semantics and adequate main touch areas.
- Semantic light/dark palette and shared button tokens exist.
- Stripe webhook validates raw-body signature.
- Secrets use `defineSecret`; no committed Stripe secret/private key found.
- Firestore prevents the client from editing subscription fields directly.
- Customer creation has its own idempotency.
- Functions have `maxInstances` bounds.

**A green unit/widget suite is evidence of those tested units — not of correct end-to-end user flows.**

## Git audit — historical workstation state

At the August 11 checkpoint:

- Working tree clean before this report was saved.
- Application sources not modified by the review.
- Nothing pushed to remote.
- Local `master` was one commit ahead of `origin/master`.
- Local HEAD `3cc81266579f012f0583ec39e150adbe16632adc`.
- Remote HEAD `8092b871861ecac4974d4dc32de819f66b8fd35c`.
- Local commit contained navigation/UI changes but had **not** passed GitHub CI.
- `git diff --check` clean.
- No committed private keys/Stripe secrets found.
- Live GitHub Actions status could not be inspected because `gh` was unavailable and the then-accessible GitHub connector could not inspect that repository.

This local Git condition is **not asserted to be the repository state today**.

## Prioritized remediation plan

### P0 — before any public release

1. Complete account-linked data inventory and delete/documentedly anonymize server **and** local data.
2. Scope photo directories, index and keys to UID, use Android Keystore and clear plaintext camera temporary files.
3. Bring export, privacy policy, terms and UI copy into one real contract.
4. Idempotent Stripe Checkout, prevent double subscriptions and cancel **all** during account deletion.
5. Check Stripe webhook API version and deploy/replay Acacia/Basil compatibility fix.
6. Staged App Check enforcement, quotas and cost anomaly alerts; stop anonymous-trial account rotation.
7. Disable or explicitly mark experimental live recognition, repetition accuracy and posture evaluation until validated.
8. Fix Home overflow and obtain green E2E on the exact candidate commit.

### P1 — before broader beta

1. Firestore Rules emulator tests with schema/size checks.
2. Full account deletion and same-device multi-account isolation tests.
3. Concurrent Checkout and Stripe reconciliation tests.
4. Real-device photo capture/dispose ordering tests.
5. Do not market demo social/community/marketplace as production.
6. Fix entitlement loading/error, cold-start recovery and notification state reconciliation.
7. Fail-closed CI including Functions, integration, signer, dependency and deployment drift checks.
8. Explicit Android/iOS/Wear product scope decision.

### P2 — quality and scale

1. Bundle fonts and complete semantic color migration.
2. Correct accessibility tap targets, semantics, live regions and **200–300%** scaling.
3. Photo thumbnails, pagination and bounded cache quotas/LRU.
4. Split giant pages/`main.dart` into focused components/controllers.
5. Update CODEMAP, AGENTS and release documentation to actual state.
6. Add a production manifest: Git SHA, Function revision, Rules ID, Hosting version and App Check mode.

## Historical final verdict

The source concluded that feature/architectural breadth was above a basic prototype, but **privacy, payments, cloud deployment drift and ML validation** were not suitable for public production.

After P0 closure, a new release-candidate review could be attempted. At **August 11** the allowed status was **closed Android beta**, with AI, progress photos, social, marketplace and Wear disabled or visibly experimental.

**This is the original verdict, not a current go/no-go decision.**

## Audit limits and side effects

- Full store-signed release build **not** performed.
- No real Stripe transactions executed.
- No fresh independent gym/out-of-distribution ML dataset evaluated in that audit.
- Remote GitHub Actions status inaccessible.
- Android E2E encountered a signature conflict. The original APK was restored, but Welcome/Login appeared afterward; the emulator's previous authenticated session was likely reset.
- Emulator stopped after inspection; temporary APK/screenshots removed.
- No app source changed; that audit created **only its report**.

## Translation control

English historical companion prepared from the **exact source Git blob**. Line references, dates, test counters, feature-status classes, BLOCK/FAIL/NOT_RUN qualifiers, primary risks, source omissions and the adversarial correction of the capture finding have been preserved. Unquoted Russian locale/test phrases have English explanations; their exact original literal spelling remains available in the linked source. No user data or live application was accessed, no tests were executed, and no external reviewer participated in this translation.

**Review disposition: SOURCE-BOUND HISTORICAL ENGLISH TRANSLATION — INDEPENDENT SEMANTIC SIGNOFF AND CURRENT-HEAD VERIFICATION STILL REQUIRED.**
