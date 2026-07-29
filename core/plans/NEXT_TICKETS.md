# Next implementation tickets

**As of 2026-05-11.** Refreshed after the 6-commit roadmap-closure
sprint (`9849d2a` → `7c4b845` → `ee72853` → `e25101e` → `64d0cdb` →
`f9b25e2` → plus this commit). Most original tickets are shipped;
what's left here is either operator action or genuinely new scope.

Sequenced by leverage / blockers, not roadmap tier. Mark items done
by editing this file.

---

## Operator action (no eng work to do here)

### 1. Create 5 Stripe price IDs + wire secrets

**You do (Stripe dashboard, ~10 min):**
- Standard product → add 3 prices: $59.99/yr annual, $14.99/mo family-2,
  $19.99/mo family-4.
- Celebrity product → add 2 prices: $119.99/yr annual, $499 one-time
  lifetime.

**Then run** (already implemented):
```pwsh
pwsh scripts/ops/setup_stripe_secrets.ps1 `
  -StandardAnnual    price_1Ab... `
  -CelebrityAnnual   price_1Cd... `
  -StandardFamily2   price_1Ef... `
  -StandardFamily4   price_1Gh... `
  -CelebrityLifetime price_1Ij...
```
The script prints the redeploy command.

### 2. Train + bundle `equipment_v1.tflite`

**You do (~45 min in Teachable Machine):**
- See `mobile/assets/models/README.md` for the label set + generation
  paths.
- Drop the file at `mobile/assets/models/equipment_v1.tflite`.
- `AssetBootstrap.ensureBundledAssets()` copies it to docs/ on launch.

### 3. Generate iOS scaffold

```pwsh
cd "D:\test 2\Fitness App\mobile"
flutter create -i swift --platforms=ios .
```
Then apply the Info.plist keys + entitlements from
`mobile/IOS_PERMISSIONS_TODO.md`.

### 4. Wear OS smoke test

Boot a Wear OS emulator, then:
```pwsh
pwsh scripts/dev/build_wear.ps1 -EmulatorSerial <serial>
```

### 5. Nonprofit launch blockers (from `core/business/NONPROFIT_PLAN.md`)

- Decide fiscal-sponsor vs direct 501(c)(3) (2 weeks vs 3–6 months).
- Recruit a DPT board member (solves the physio-review credibility
  story without spending $5k).
- Apply for Google for Nonprofits + Microsoft Startups for Nonprofits.

---

## Optional next-eng pickup (not blocking)

### 6. ~~Push offline cache prefetch through to actual video URLs~~ DONE (`366fd58`)

Fixed: `videoUrlResolverFor(catalog)` in `offline_video_providers.dart` resolves each
session's `exerciseId` -> `ExerciseItem.videoUrl` via `allExercisesProvider`, used both as the
provider's default and at the `workouts_page.dart` call site. New test:
`test/features/workouts/state/offline_video_providers_test.dart`.

### 7. AES-GCM swap for the photos page wiring

`AesPhotoCipher` is implemented and tested but the page still uses
the test-only XOR cipher (the `MockProgressPhotosRepository` never
actually encrypts). When you wire a Firestore/Storage repo for
production photos, plumb `AesPhotoCipher.newKey()` through
SharedPreferences (or Keystore for hardened deployments).

### 8. Stripe Connect onboarding return-url wiring

`startCoachOnboarding` returns a Stripe URL; we open it via
`url_launcher`. The return URL is currently a placeholder
(`fitnessapp.example.com/coach/onboarding-done`). Once the marketing
site exists, swap the URL and add an in-app deep link to refresh the
coach listing on return.

### 9. ~~Cloud Function tests~~ DONE (2026-07-29)

Done: pure-unit jest suite at `functions/src/__tests__/index.test.ts` — 22 tests:
`startFreeTrial` (4), `createCheckoutSession` (7), `generateAnnualReceipt` (5),
`bookCoachSession` (6); happy paths + auth/validation failures, asserting both
return payloads and Firestore/Stripe mock call args. firebase-admin + stripe
fully jest-mocked, secrets = fake env values in `jest.setup.js` (no emulator
suite, no Java dep). `npm test` 22/22 PASS; `npm run build` still clean — test
files excluded from `lib/` via tsconfig `exclude`. Still uncovered (out of
scope, next candidates): `stripeWebhook`, `createPortalSession`,
`optInDonorWall`, `optOutDonorWall`, `startCoachOnboarding`, `reportEquipment`.

### 10. Visual model: ship a real catalog of stock videos via the
moderation queue

`scripts/catalog/seed_stock_videos.ps1` documents the Pexels +
community-moderation path. Either run a 50-clip seed yourself or
open the contribute page (`/contribute`) to a small group of users
and clear the queue at `/moderate`.

---

## Tier MK / strategic features (post-paid-ramp)

The seven Tier-MK foundations are in place (cycle-aware, insurance,
SDK, body comp, recovery-as-workout, goal-photo, form-coach). What's
not done yet is the integration work on each:

- **MK.1 Live Form Coach with Voice** — voice grammar + form check
  exist separately. Need a state machine that listens to voice while
  the form classifiers run. ~5d.
- **MK.2 Goal-photo → program** — the GoalPhotoRequest envelope is
  defined; the Cloud Function calling Claude Vision is not. ~5d eng
  + ~$2/mo Claude API budget.
- **MK.3 Cycle-aware programming** — `phaseFor` + `hintFor` are pure
  helpers; we need an Onboarding question for cycle-tracking opt-in +
  a UI surface on the AI plan page that respects the phase. ~3d.
- **MK.4 Insurance partner attestations** — `qualifiesFor` predicate
  exists; the Cloud Function that signs the attestation and POSTs to
  a partner doesn't. ~5d + 6-18mo BD work.
- **MK.5 White-label SDK** — config + JWT envelope defined; building
  the actual SDK package + the partner SSO Cloud Function is the bulk.
  ~60d + dedicated devrel hire.
- **MK.6 Body comp via camera** — Navy formula + onboarding-time
  measurements work; the photo-silhouette estimator is not built.
  Needs a TFLite silhouette model. ~20d + $10-15k content.
- **MK.7 Recovery as a workout** — `RecoveryBlock` model + 7
  recovery kinds defined; need the UI for scheduling a recovery
  session like a strength session. ~5d.

---

## What's already shipped

(Historical reference — see commits `9849d2a` through latest.)

**Roadmap v2:**
- P0.1 Annual / family / lifetime SKUs (eng done; price-IDs operator)
- P0.3 Wear OS minimal companion (data layer + native scaffold)
- P0.4 Catalog: community video moderation pipeline (Pexels seeder)
- P0.5 Health Connect / HealthKit abstraction
- P0.6 Plate calculator + warm-up + rest timer
- P0.7 Plate / warm-up on EquipmentDetailPage
- P0.8 Offline workout download
- P1.1 Post-workout difficulty rating
- P1.2 Programmatic progressive overload
- P1.3 MediaPipe form check (rule classifiers + page + live camera)
- P2.1 Team feed for Celebrity tier
- P2.3 Progress photos (AES-GCM encrypted)
- P2.4 Celebrity-led video plans page
- P3 AI workout generator (`/plan`)

**Tier X:**
- TX.1 Injury Recovery Coach (2 seeded protocols)
- TX.2 Visual equipment recognition (image picker + ML Kit)
- TX.3 Buddy matching (BuddyProfile + ranker)
- TX.4 Auto-deload detection + banner
- TX.5 Coach Marketplace (Stripe Connect + bookings)
- TX.6 Voice-only command grammar
- TX.7 Equipment failure reporting

**Tier MK foundations** (7/7 model + repo layers).

**Nonprofit eng:**
- Subscription copy → donation framing
- /about (mission) + /donors (wall) + /community (social feed)
- Annual receipt Cloud Function
- Donor-wall opt-in Cloud Function

**Infra:**
- 8 production service bindings in main.dart
- Asset bootstrap (TFLite model copy)
- GitHub Actions CI (flutter analyze + test + Cloud Functions tsc)
- Debug daemon + run-with-debug + run-tests scripts
- Stripe secrets setup script
- Wear OS build script
- Discovery surfaces on Home + Train + Profile pages

**Test suite:** 365 tests passing, 0 failing, ~2 min runtime.
**Build:** `flutter build apk --debug` produces a 380 MB APK
end-to-end (debug; release build untested).
