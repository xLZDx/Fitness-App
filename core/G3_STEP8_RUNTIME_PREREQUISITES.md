# MVP1.G3 Step 8 -- runtime-monitor prerequisites

Rosetta plan `Fitness_App-2026-08-27T01-44-56-612Z-f57b28`
(hash `9f5e9bbd0aeb97b33b3d078dcbc49765bdf88f8569634959e0474879f61dfa09`),
APPROVED by GPT-PM 2026-08-27 with a 12-item binding DoD (see
`core/DECISION_LOG.md`'s Step-8 entry for the full exchange). This document is
the design record for the parts of that DoD that are evidence-and-design work,
not yet the live infrastructure change -- creating and binding the actual
production alert channel is explicitly on HOLD pending the operator's own
confirmation of `DECISION G3-RUNTIME-OWNER` (see bottom of this file).

## 1. Alert destination -- design, not yet created

**Mechanism:** one Cloud Monitoring email notification channel on
`fitness-app-korostelev`, type `email`, pointed at the project owner's Google
account. Additive to the budget's existing default IAM-role recipients per
GPT-PM's correction -- `disableDefaultIamRecipients` stays at its default
(`false`); this is redundancy, not a replacement.

**Verification GPT-PM requires before Step 8.2 counts as DONE:** a temporary,
harmless Cloud Monitoring alerting policy (a condition guaranteed to fire
almost immediately, e.g. "log entry count > -1 in the last minute") is created,
its incident is confirmed to actually produce an email at the recipient, and
the temporary policy is then deleted. Configuration existing is not sufficient
proof by itself -- GCP's own documentation is explicit that a misconfigured
notification channel can fail silently with no separate failure signal.

**Not done yet:** creating the channel and running that verification requires
actually sending mail to a real address and binding production alerting to a
human recipient -- both are the operator's call per `DECISION
G3-RUNTIME-OWNER` below, not something to do on an inferred default.

## 2. Cloud Scheduler -- job-budget evidence (real, not assumed)

GPT-PM corrected the original proposal: Cloud Scheduler's free tier is
**3 jobs/month per BILLING ACCOUNT, not per project** -- additional jobs are
$0.10/job/month. Checked live, 2026-08-27, against every project on this
billing account (`019944-23376A-5C1743`):

| project | Scheduler API enabled | jobs (any region checked) |
|---|---|---|
| `fitness-app-korostelev` | Was No; **enabled 2026-08-27** (`gcloud services enable cloudscheduler.googleapis.com`, per GPT-PM's explicit "Scheduler/API readiness" GO -- reversible, zero cost, does not bind any alert to a human recipient) | 0 |
| `traidingbot-b4061` | No | 0 |
| `trading-bot-496818` | No | 0 |
| `erp-moldova-staging-20260819` | Yes | 0 (checked `us-central1`) |

**Current billing-account-wide Scheduler usage: 0 of 3 free jobs.** GPT-PM's
recommendation -- one consolidated scheduled dispatcher for Step 9's runtime
probes rather than one `onSchedule` function per monitor -- fits inside the
free allowance with headroom for two more jobs elsewhere on this billing
account before any cost is incurred. This replaces the original "free tier is
generous, assumed zero cost" claim GPT-PM flagged as unverified with an actual
number.

## 3. Canary identity -- design (per GPT-PM's amended invariant)

GPT-PM's required shape:

```
synthetic identity -> real Firebase Auth token exchange -> authenticated
Firestore request -> only /_canary/<its-own-id> -> read/write/delete ->
actionable alert on failure
```

Two hard constraints from the review: the canary must not use the Admin SDK
for the Firestore read/write if the report will claim it proves the
client-facing Auth+Firestore path (Admin SDK bypasses Security Rules
entirely), and the design must inspect this app's ACTUAL production sign-in
providers rather than adding a new one purely because it is easy to automate.

**Actual production sign-in providers (verified against
`mobile/lib/features/auth/data/firebase_auth_repository.dart`):**
- Anonymous (`signInAnonymously`, line 76-78).
- Google Sign-In (`signInWithGoogle` -> `GoogleAuthProvider.credential`, line
  132-143, with anonymous-to-Google account linking via `linkWithCredential`).
- No email/password provider -- the file's own comment (line 183) records
  that this was already checked and confirmed absent.

Google Sign-In is not safely automatable headlessly without storing a real
Google account's credentials somewhere (exactly the "credential stored in
repo/env file" failure GPT-PM's DoD 8.11 forbids). Per GPT-PM's own fallback
("a custom-token exchange can test core Firebase Auth availability, but its
narrower coverage must be recorded"):

**Chosen design:** the canary function (Admin SDK, server-side) mints a
Firebase custom token via `admin.auth().createCustomToken(canaryUid, {canary:
true})` for a single dedicated, fixed UID reserved for this purpose. The
canary CLIENT step -- the part that must prove the real path -- then calls
the Firebase Auth **Client SDK's** `signInWithCustomToken()` with that token
to obtain a genuine ID token issued through the real Firebase Auth token
exchange, and uses that authenticated client session (not the Admin SDK) to
read/write/delete `/_canary/<canaryUid>`. This is Firebase's own documented
mechanism for a server-provisioned service/test identity -- it is not a new
sign-in provider in the Console/App sense, and it correctly separates
"provision an identity" (Admin SDK, server-side, no Security Rules bypass
claim) from "prove the client path" (Client SDK, real Security Rules
enforcement).

**Honest scope statement, required by GPT-PM's DoD 8.6/8.7:** this design
proves Firebase Auth token issuance/validation and Firestore Security Rules
enforcement for an authenticated identity. It does **not** exercise the
Google Sign-In OAuth flow specifically -- that remains unmonitored by this
canary, and this document records that gap rather than silently claiming full
sign-in coverage.

**Firestore isolation:** Security Rules must require BOTH request
`auth.uid == canaryUid` AND the custom claim `request.auth.token.canary ==
true` (not UID possession alone -- GPT-PM's explicit requirement), scoped to
`/_canary/{docId}` only, with no rule anywhere in the ruleset granting that UID
or that claim access to any real user-data collection. Positive proof (canary
can read/write/delete its own `_canary/` doc) and negative proof (same
identity denied on a real user-data path, e.g. `/users/{anyId}`) are both
required before this counts as built, per DoD 8.8 -- not yet implemented,
this section is the design GPT-PM reviews before Step 9 builds against it.

**Synthetic-data hygiene (DoD 8.9):** canary documents live only under
`_canary/`, a namespace prefix already outside every real per-user or
per-workout collection path in this schema, and are deleted by the canary run
itself immediately after use (read-write-delete in one pass, not a lingering
write). Any future data-lifecycle/export/deletion monitor (Step 9) must
explicitly exclude the `_canary/` collection from its counts so synthetic
writes cannot be mistaken for real user data.

## 4. App Check -- truthful scope (DoD 8.7)

If App Check enforcement is active on the callables/paths this canary
exercises, the canary's server-side step can mint a synthetic App Check token
via Admin SDK's `appCheck().createToken(appId)`. Per GPT-PM's correction, this
proves **enforcement/token acceptance only** -- it does not exercise real
Android/Play Integrity device attestation, since that path only exists on a
genuine client device. Any future report citing this canary must state that
distinction explicitly rather than imply full App Check health coverage.

## 5. DECISION G3-RUNTIME-OWNER -- pending operator confirmation

GPT-PM's ruling, verbatim: *"This does require direct operator confirmation,
because our previously agreed escalation policy explicitly classifies a human
on-call/notification obligation as a real ownership decision rather than
something an agent may infer."*

**Decision text, as GPT-PM framed it:**
> The operator accepts responsibility as the primary alert owner/on-call
> recipient for MVP1.G3 runtime alerts, using the project-owner Google account
> as the primary email notification destination, until explicitly changed.

**Status: PENDING.** Not yet answered by the operator as of this writing.
Per GPT-PM's authority ruling: Step 8's design/investigation/reversible
infrastructure-prep work may continue without it (this document is exactly
that work), but Step 8 cannot be marked fully DONE, and no production alert
policy may be bound to a human recipient, until this is explicitly confirmed.

## 6. Step 9 monitor mapping (DoD 8.10) -- per-monitor technical surface

Real technical surface for each of the 6 Step 9 monitors, gathered by direct
investigation of `functions/src/` and `mobile/lib/` (not invented), per
GPT-PM's required columns. `owner`/`channel` for every row is the same
FA-D1-pending destination (Sec 5) -- not repeated per row below.

### 6.1 Auth -> Firestore canary
- **Signal source:** the canary's own scripted run (Sec 3 design).
- **Execution mechanism:** one Cloud Scheduler job -> Cloud Function ->
  `createCustomToken` (Admin SDK) -> `signInWithCustomToken` (Client SDK,
  real token exchange) -> Firestore read/write/delete on `/_canary/<uid>`.
- **Identity:** dedicated fixed canary UID, custom claim `canary: true`.
- **Real-path fidelity confirmed:** investigated what a genuine sign-in
  actually touches -- `firebase_auth_repository.dart`'s `signInAnonymously`/
  `signInWithGoogle` touch ONLY Firebase Auth, no Firestore import in that
  file at all; `users/{uid}` is created later, on demand, only by
  `firestore_profile_repository.dart:188`'s `saveProfile`. So a bare Auth
  canary with no Firestore write would already match a real anonymous
  sign-in's footprint faithfully; the `_canary/` Firestore write is
  deliberately ADDED beyond that baseline specifically to also exercise
  Security Rules enforcement, which a pure Auth-only canary would not touch.
- **Data written:** one `_canary/<uid>` doc, deleted same run.
- **Threshold / controlled failure:** alert if the run doesn't complete
  (auth failure, rules-denial, or timeout) within N consecutive scheduled
  runs. Controlled-failure test: revoke the canary UID's custom claim
  temporarily and confirm the Firestore step is denied and alerts.
- **Cost:** 1 of the 3 free Scheduler jobs (Sec 2); Function invocation,
  Auth verification and Firestore ops all within Blaze free-tier volume at
  a low run frequency (e.g. every 15-30 min).

### 6.2 App Check / enforcement visibility
- **Signal source:** `abuse_guard.ts:48-67`'s existing `noteAppCheck(request,
  fn)` -- ALREADY logs `{ fn, attested: request.app !== undefined }` at
  `info` level on every call to a callable that invokes it. This is a
  measurement mechanism, not a rejection log: enforcement itself is
  currently OFF everywhere (`scaling.ts:120,127-128,137-138`'s
  `APP_CHECK_ENFORCED*` flags default false; `main.dart:238` states no
  callable currently sets `enforceAppCheck: true`; `abuse_guard.ts:38-41`
  documents this as an already-audited finding from 2026-08-11).
  There is nothing to "reject" today, so a rejection-count monitor would be
  vacuous -- the honest monitor for THIS gate is an attested-ratio metric
  (share of calls with `attested: true` over time), which is exactly the
  visibility needed before enforcement is ever flipped on, and a distinct,
  separate monitor to add the day enforcement actually turns on.
- **Execution mechanism:** a log-based Cloud Monitoring metric over the
  existing `noteAppCheck` log line (no new code in the callables).
- **Data written:** none new -- reads existing Cloud Logging entries.
- **Threshold:** informational dashard for now (attested-ratio trend); a
  hard alert threshold only makes sense once enforcement is scheduled,
  which is a separate, not-yet-approved decision.
- **Controlled failure:** call a metered callable from a debug-provider
  client with App Check intentionally misconfigured and confirm the
  `attested: false` log line appears and the metric moves.
- **Cost:** log-based metrics are free at this project's volume.

### 6.3 Stripe billing-integrity
- **Signal source:** two concrete existing silent-failure spots in
  `functions/src/index.ts`'s `reconcileDuplicateSubscriptions` (:1862-1917):
  `logger.error("could not cancel duplicate subscription", ...)` (:1904-1908)
  and `logger.error("duplicate reconciliation failed", ...)` (:1911-1915) --
  both already fire today but nothing currently reads them. A third, lower-
  severity signal: the `default:` branch (:1115-1116) that silently drops
  any Stripe event type not explicitly handled (e.g. a future
  `charge.refunded`) with only a `debug` log -- worth a LOW-severity watch
  since a debug-level silent drop is easy to miss even by a human reading
  logs directly.
- **Execution mechanism:** log-based metrics + alerting policies over the
  two existing `logger.error` call sites (no new code needed for those two);
  optionally bump the `default:` branch's log level or add a distinct
  metric if unmatched-event coverage becomes a real concern later --
  flagged as a design option, not decided here.
- **Real gap this does NOT close:** there is no standalone reconciliation
  job that independently polls Stripe as ground truth -- reconciliation is
  purely reactive, triggered only by an incoming `customer.subscription.*`
  webhook. A customer whose webhooks stop arriving entirely (Stripe-side
  delivery failure) has no detection path today. Recording this as a real,
  named residual gap rather than silently treating "watch the two log
  lines" as if it were full coverage.
- **Threshold:** alert on ANY occurrence of either `logger.error` (both are
  already rare-path, unswallow-worthy failures per their own doc comment).
- **Controlled failure:** in a test/emulator context, force
  `cancelSubscriptionItem` to throw and confirm the metric/alert fires.
- **Cost:** log-based metric, free at this volume.

### 6.4 Data-deletion / export coverage
- **Signal source:** none exists today beyond point-in-time human review.
  `deleteAccount` (`index.ts:2060`) covers `users/{uid}`, `donor_wall/{uid}`,
  `coach_listings/{uid}` (`recursiveDelete`, :2151-2156) plus
  `sweepSharedRecords` for `coach_bookings`, `equipment_reports`,
  `debug_sessions` (:1985-2058) -- based on the "A0" shared-data inventory
  (`core/DECISION_LOG.md:2389-2437`), not an enforced, self-updating
  invariant. **No CI or runtime check currently verifies that every
  Firestore collection actually in use is covered** -- a new collection
  added later without updating `deleteAccount`/`sweepSharedRecords` would
  not be caught by anything that exists today.
- **What this means for Step 9 scope:** a true "coverage" monitor needs a
  canonical, machine-readable list of collections-containing-user-data
  compared against `sweepSharedRecords`' hardcoded list -- structurally a
  `[CI]` drift check (like item 4's equipment-registry parity), not a
  runtime probe, since the failure mode is "code changed, deletion coverage
  didn't," not "something broke at runtime." Recommending this be logged as
  a roadmap item for a future `[CI]` gate rather than force-fit into Step 9
  as a runtime monitor it structurally isn't -- flagging for GPT-PM's
  review rather than deciding unilaterally.
- **What Step 9 CAN honestly cover as a runtime monitor:** error-rate/
  failure alerting on the `deleteAccount` and `exportAccountData` callables
  themselves (did an invocation throw), using the same log-based-metric
  pattern as 6.3 -- narrower than "coverage" but real and buildable now.

### 6.5 Client/camera/inference/performance telemetry
- **Signal source, confirmed absent today:** `firebase_crashlytics` IS a
  dependency (`pubspec.yaml:95`) but is NOT called anywhere inside the
  three feature areas that most need it. Exact swallowed catches found:
  `mlkit_live_equipment_service.dart:178-180` (`debugPrint` only, returns
  null, continues silently), `scanner_page.dart:179-186` (sets UI error
  state, no Crashlytics report), `gemini_equipment_service.dart:141-145`
  (rethrows without first logging to Crashlytics). `firebase_performance`
  is confirmed absent from `pubspec.yaml` entirely (re-verified, zero
  matches).
- **What this means for Step 9 scope:** there is currently NO signal to
  monitor here at all -- this "monitor" is actually a small, targeted CODE
  CHANGE (wire `FirebaseCrashlytics.instance.recordError` into these three
  named catch blocks, matching the pattern `main.dart:132-218` already
  established for the app's top-level error handling) followed by a
  Crashlytics-issue-velocity alert. Flagging this distinction explicitly
  for GPT-PM rather than quietly scoping Step 9 down to "add an alert on
  nothing" -- the fix has to land before the monitor has anything to watch.
- **Cost:** Crashlytics is already a free-tier Firebase product in use.

### 6.6 AI Gateway monitor (4 G1 callables)
- **The 4 callables, confirmed by name and location:** `aiCoachAdvice`
  (`ai_coach_advice.ts:128`), `aiEquipmentRecognition`
  (`ai_equipment_recognition.ts:108`), `aiExerciseGeneration`
  (`ai_exercise_generation.ts:260`), `aiMachineDescription`
  (`ai_machine_description.ts:87`) -- all route through the shared
  `ai_gateway.ts::generate()` (:213-261) and all already enforce a
  per-user/per-UTC-day quota via `enforceDailyQuota`
  (`abuse_guard.ts:84-`, storage at `users/{uid}/usage/{yyyy-mm-dd}`).
- **Real gap:** no token-usage or dollar-cost accounting anywhere in
  `generate()` -- quota LIMITS calls per user but nothing tracks actual
  spend. No per-callable error-rate metric either; only generic
  `logger.warn`/`logger.error` inside the shared gateway itself
  (:253-257), not attributed per calling function.
- **Execution mechanism:** log-based metrics on `generate()`'s existing
  warn/error log lines, labeled by the calling function name (already
  passed into `generate()` -- confirm exact parameter name before
  implementing); a quota-exhaustion-rate metric off `enforceDailyQuota`'s
  own rejection path.
- **Threshold:** alert on an error-rate spike (e.g. >X% of calls to
  `generate()` failing in a rolling window) and separately on sustained
  quota exhaustion (a signal that per-user limits may need revisiting, a
  product decision, not something this monitor should auto-adjust).
- **Controlled failure:** force `generate()`'s underlying Vertex call to
  fail in a test context (bad model name / injected timeout) and confirm
  the metric/alert fires.
- **Cost:** log-based metrics, free at this volume; no new Cloud Monitoring
  custom-metric ingestion needed if built on existing log lines.

## 7. IAM / secrets (DoD 8.11)

- **Canary identity:** the custom-token-minting Cloud Function's own service
  account needs `firebaseauth.customTokenMinter` (or equivalent minimal
  Auth-admin scope) and NOTHING else beyond default Functions execution
  permissions -- no broader Firestore/Storage admin role, since the
  Firestore step deliberately goes through the Client SDK under Security
  Rules, not the Admin SDK.
- **No credential in source:** the canary UID and its custom claim value are
  not secrets (a UID is not sensitive, and the claim is boolean); nothing
  about this design requires a password, API key, or refresh token to be
  stored anywhere -- `createCustomToken` uses the Function's own runtime
  service-account identity, already how every other Admin SDK call in this
  codebase authenticates.
- **Log-based metrics (6.2-6.6):** read existing Cloud Logging entries via
  the Function/Console's own IAM, no new permission surface.
- **Notification channel:** Cloud Monitoring's own IAM (`roles/monitoring.
  notificationChannelEditor` or equivalent) for whoever creates it manually
  or via `gcloud` -- not a runtime credential, a one-time admin action.

## 8. Alert-path test plan (DoD 8.12)

Each monitor's own "controlled failure" cell in Sec 6.1-6.6 IS this item's
per-monitor entry; consolidated here as the batch-level plan GPT-PM asked
for:

| monitor | controlled failure | expected signal | reset |
|---|---|---|---|
| 6.1 canary | revoke canary UID's custom claim temporarily | Firestore step denied, alert fires | restore claim |
| 6.2 App Check | call from debug-provider client with App Check misconfigured | `attested:false` log line, metric moves | none needed (no state changed) |
| 6.3 Stripe | force `cancelSubscriptionItem` to throw (test/emulator) | `logger.error` metric/alert fires | none (test env only) |
| 6.4 deletion/export | force `deleteAccount`/`exportAccountData` to throw (test/emulator) | error-rate metric/alert fires | none (test env only) |
| 6.5 telemetry | throw inside one of the 3 named catch blocks (test build) | Crashlytics issue appears, velocity alert fires | none (test build only) |
| 6.6 AI Gateway | inject a bad model name / forced timeout in `generate()` (test env) | error-rate metric/alert fires | none (test env only) |

None of these require touching production data or spending real money to
prove; each is either a test/emulator-context injection or a reversible
temporary state change with an explicit reset step.

## 9. GPT-PM round 2 rulings (2026-08-27) -- binding amendments

Full exchange in `core/DECISION_LOG.md`'s "GPT-PM round 2" entry. Summary of
what changes in Sec 6-8 above, superseding the affected parts of those
sections rather than duplicating them:

- **6.4 does not move to roadmap.** Becomes **G3-CI-8 "Data Lifecycle
  Coverage Drift Guard"**, built inside this gate: mechanical discovery of
  Firestore collections in use, each requiring an explicit
  `DELETE`/`EXPORT`/`BOTH`/`EXEMPT` + reason classification; a new
  unclassified collection fails CI. The Step 9 error-rate monitor on
  `deleteAccount`/`exportAccountData` is still built, but as a supplemental
  signal, not a substitute.
- **6.5's Crashlytics wiring has real design constraints, not a bare
  `recordError()` drop-in:** dedupe/rate-limit the OCR-loop error path;
  expected camera-permission-denied must not alert as an incident; the
  Gemini catch logs non-fatal with `(error, stackTrace)` ONLY -- no
  photo/prompt/health/profile content, then rethrows unchanged. Also
  requires a bounded latency/performance signal for the camera/inference
  path, since the original OBS-1 item was failures AND performance, not
  failures alone.
- **6.6 needs a structured per-call observability event, not the
  error-rate/quota-exhaustion metrics alone:** operation (bounded to exactly
  the 4 callable names), outcome, latencyMs, timeout, quota-exhaustion, and
  the provider's own `usageMetadata`/token counts when available -- NOT a
  hand-built dollar ledger or hardcoded pricing. Requires adding an
  `operation` identifier parameter to `ai_gateway.ts::generate()`, which
  does not currently accept one.
- **Sec 6.1 canary design, 2 corrections:** Security Rules must EXPLICITLY
  exclude the canary identity from `/users/{uid}` and other real-data paths,
  not merely add a `_canary/` allow-clause; the Sec 8 negative-proof test
  ("revoke the custom claim") is invalid as designed since
  `createCustomToken` re-mints the claim fresh every call -- corrected to
  minting a token with no `canary` claim (or the wrong UID) and confirming
  that is denied.
- **Cost claims tightened:** "log-based metrics are free at this volume" was
  too general -- prefer direct log-match alerting (no metric ingestion)
  where possible; any genuinely chargeable custom metric needs its real
  recurring cost computed before being claimed as acceptable, not asserted
  free by default.

**Authority (GPT-PM's own words):** these are the RESULT of Step 8's
already-authorized investigation, not new scope -- no new Rosetta re-plan
needed. GO: AUTHORIZED for G3-CI-8, canary rules/tests (corrected), Crashlytics/
performance instrumentation (constrained), AI Gateway observability plumbing,
log/metric definitions, and all other reversible implementation work. HOLD
unchanged on binding a human alert recipient (FA-D1). HOLD (new): deploying
any monitoring with confirmed nonzero recurring custom-metric cost after
minimization -- that becomes its own named operator cost decision.

## 10. G3-CI-8 -- built (see core/DECISION_LOG.md for the full entry)

Data Lifecycle Coverage Drift Guard shipped in commit `2e739a3`:
`scripts/ci/check_data_lifecycle_coverage.js` + `data_lifecycle_policy.json`,
wired into `.github/workflows/functions.yml`. Found and fixed 2 real gaps
(`equipment_setup_notes`, `receipts` missing from `exportAccountData`) and 1
rules gap (`coach_listings` had no `firestore.rules` entry at all). 34/34
collections classified; 108/108 (then 113/113 after the canary rules below)
rules-emulator tests pass; 382/382 functions unit tests pass.

## 11. Canary Security Rules + tests -- built, corrections applied

Implemented the Sec 3 canary design in `firestore.rules`, with GPT-PM's two
required corrections from Sec 9 both applied:

- **Explicit exclusion, not reliance on absence of data:** `isCanaryToken()`
  (`request.auth.token.get('canary', false) == true`) is added as an
  additional `&& !isCanaryToken()` condition on BOTH the read and write
  clauses of the generic `/users/{uid}/{coll}/{document=**}` wildcard --
  so a request authenticated as the canary's own uid cannot inherit the
  ordinary per-user grant, structurally, not just because no real data
  happens to live under that path today.
- **The canary's entire grant** lives in one new block:
  `match /_canary/{canaryUid} { allow read, write, delete: if
  isCanaryToken() && request.auth.uid == canaryUid; }` -- both the custom
  claim AND uid-equals-docId are required, so a second canary identity (if
  one is ever minted) could not reach the first one's document.
- **Corrected negative-proof test** per Sec 9's second finding: rather than
  the originally-planned "revoke the claim" (invalid, since
  `createCustomToken` re-mints it fresh every call), the test suite mints a
  token with NO `canary` claim (an ordinary authenticated user) and confirms
  it is denied on `_canary/`, and separately confirms a canary-claimed token
  cannot reach a DIFFERENT canary uid's document.

**Positive proof:** `npm run test:rules` -- 113/113 pass (108 existing + 5
new: own-document read/write/delete succeeds, ordinary-user denied,
cross-canary-uid denied, wildcard-exclusion denied for both the canary's own
uid and another real user's uid).

**Negative proof -- the one that matters most, per GPT-PM's own framing:**
temporarily replaced both `&& !isCanaryToken()` conditions on the wildcard
rule with `&& true` (functionally: no exclusion at all) and re-ran the
suite -- exactly 1 test failed
("cannot read or write under /users/{canaryUid}/... via the general
wildcard"), the other 112 stayed green. This is the concrete, executable
proof that the exclusion is load-bearing: before it existed, a canary
request against its own uid's ordinary user-data path would have
**succeeded**, exactly the gap GPT-PM's review required closing. Restored
immediately, re-confirmed 113/113 green.

**Not yet built:** the actual Cloud Function that mints the custom token
(`admin.auth().createCustomToken(canaryUid, {canary: true})`) and any
Cloud Scheduler job invoking it. GPT-PM's GO named "canary rules/tests" as
the Step-8-authorized item; assembling the full scheduled monitor (the
function, its registration, and the Scheduler job) is Step 9's job, and
waits on `FA-D1` regardless -- a canary with no alert destination to report
to is incomplete even once it runs.

## 12. Sec 6.5 (client/camera/inference/performance telemetry) -- built

Wired `FirebaseCrashlytics.instance` into the three named catches, matching
all of Sec 9's constraints (dedupe the OCR-loop path, exclude expected
camera-permission-denied from alerting, sanitize the Gemini catch to
`(error, stackTrace)` only and rethrow unchanged), plus the still-open
"bounded latency/performance signal" requirement -- full detail and proof in
`core/DECISION_LOG.md`'s "Step 8/9 (6.5): client/camera/inference
Crashlytics + performance signal" entry. Summary:

- `mlkit_live_equipment_service.dart`: reports the OCR anchor's failure once
  per live session (`_ocrAnchorFailureReported`, reset in `start()`), not
  once per frame.
- `scanner_page.dart`: reports only `CameraUnavailableReason
  .initializationFailed`; the other three reasons are expected states, not
  incidents.
- `gemini_equipment_service.dart`: catch now captures a stack trace, reports
  `(error, stackTrace)` only (no photo/prompt/health content), rethrows the
  same `VisualEquipmentException` unchanged.
- **Performance signal:** a `Stopwatch` around the cloud call, checked only
  on the SUCCESS path, reports when a successful call still took >= 20s
  (this file's own documented server-budget anchor) -- disjoint from the
  failure report, so a timeout cannot double-count as "slow". Reuses
  Crashlytics rather than adding `firebase_performance` as a new dependency
  (Sec 9 tightened cost claims; this file's own Sec 6.5 cost line already
  treats Crashlytics as free-tier and in use).

**Regression caught, not a clean first pass:** the first version called
`FirebaseCrashlytics.instance` directly with no guard. `FirebaseCrashlytics
.instance`'s getter throws synchronously in a plain `flutter test` run (no
`Firebase.initializeApp()` in this project's test harness) -- 3 of 71
`scanner_page_test.dart` cases genuinely failed. Fixed by wrapping each call
site in its own `try { unawaited(...) } catch (_) {}`, matching the guard
`main.dart:160-166` already established for its own Crashlytics call.
Re-running the same suites afterward returned to fully green.

**Proof gap, stated rather than implied:** no test in this repository can
assert that `FirebaseCrashlytics.instance.recordError` is actually invoked
at runtime with the right arguments -- there is no method-channel mock for
`firebase_core`/`firebase_crashlytics` anywhere in this suite today (the
same boundary `live_text_anchor_test.dart` already documents for the OCR
path: the service "cannot be driven end-to-end on a desktop runner"). What
IS proven by executed tests: the dedupe/gating/rethrow-unchanged logic
around each call, and that adding the calls introduces no regression. The
wiring itself is verifiable only on a real device/emulator build -- which is
exactly Sec 8's own alert-path test plan for row 6.5 ("throw inside one of
the 3 named catch blocks (test build) -> Crashlytics issue appears, velocity
alert fires"), still the real verification step and still pending.

## 13. Sec 6.6 (AI Gateway monitor) -- observability plumbing built

Built the structured per-call event Sec 9 required -- full detail and proof in
`core/DECISION_LOG.md`'s "Step 8 (6.6): AI Gateway per-call observability plumbing" entry. Summary:

- New exported `AiGatewayOperation` union type in `ai_gateway.ts`, exactly the 4 callable names --
  bounded at compile time, not by runtime convention.
- `operation: AiGatewayOperation` is now a REQUIRED field on `GenerateOptions`; all 4 `ai_*.ts`
  callables pass their own name.
- `generate()` emits one `logger.info("ai_gateway: call", {...})` event per call from a single
  `finally` block (fires on both the success path and every throw): `operation`, `outcome`
  (`success`/`timeout`/`error`), `latencyMs`, and the provider's own `usageMetadata` token counts
  when the response carried them.
- `quota-exhaustion` is deliberately not a field on this event -- a quota-rejected call never reaches
  `generate()`. Verified instead that `enforceDailyQuota`'s existing `"quota exceeded"` log already
  carries the same operation identity via its `action` argument, so the two log lines join on that
  field without duplicating the quota check's own logic -- the design this section's own 6.6 already
  anticipated.

**Proof:** `npm run build` clean; `npx jest ai_gateway` 24/24 (6 new tests directly asserting the
event fires with the right shape for success/timeout/error/empty-answer, that absent usage data
produces absent fields rather than `undefined` ones, and that the event fires exactly once per call
-- this repo's existing SDK-client mock makes this directly assertable, unlike the mobile side in
Sec 12); full functions suite 388/388, including all 4 callable suites unchanged.

**Deliberately not built here:** the actual Cloud Monitoring log-based metrics and alerts that READ
this event (error-rate spike, quota-exhaustion-rate) -- Sec 6.6's own scoping puts assembling those
in Step 9, which also waits on `FA-D1` for an alert destination regardless. This item is the event
existing to be read from.

## 14. Step 9 status vocabulary and 9A (canary probe) -- IMPLEMENTED/TESTED/READY_TO_ACTIVATE

GPT-PM ruling (2026-08-27, full exchange in `core/DECISION_LOG.md`'s "Step 9A" entry): Step 9 does
NOT wait on `FA-D1` as a single unit. Alert-independent groundwork across all 6 planned monitors is
GO now, under binding status vocabulary:

- `IMPLEMENTED` / `TESTED` / `READY_TO_ACTIVATE` -- allowed before `FA-D1`.
- `ACTIVE` / `VERIFIED` / `DONE` -- only after `FA-D1` clears AND a live end-to-end delivery proof.
- `BLOCKED_FA-D1` -- for the final activation/delivery step specifically, not for the whole item.

What stays on HOLD regardless: the production human-facing alert binding, and any live deployment
whose real recurring cost (after minimization) is confirmed nonzero and not already accepted.
Everything else -- production implementation code, tests, controlled-failure fixtures, filters/query
definitions, deployment config, cost estimates -- is explicitly not blocked.

**9A (canary auth->Firestore probe): IMPLEMENTED/TESTED/READY_TO_ACTIVATE.** Full detail and proof in
`core/DECISION_LOG.md`'s own entry. Summary: `functions/src/canary_probe.ts`'s `runCanaryProbe()` --
mint (Admin SDK) -> exchange (real Client SDK `signInWithCustomToken`) -> write/read/delete through
the exchanged identity against the already-shipped `_canary/` Security Rules (commit `6e91b10`) ->
fail-safe cleanup -> bounded, non-sensitive result. Not a public endpoint, not wired to any Scheduler
or alert. Moved `firebase` (Client SDK) from `devDependencies` to `dependencies` (a real deploy-time
gap GPT-PM's DoD named explicitly). Found and fixed a second, unrelated real gap while building this:
`_canary` had no G3-CI-8 lifecycle-policy entry (the earlier canary-rules commit never re-ran that
check after adding the collection) -- now classified `EXEMPT`.

Proof: `npm run test:e2e` (real Auth+Firestore emulators -- `npm run test:rules` alone was explicitly
rejected by GPT-PM as insufficient proof of the Auth exchange) 17/17, covering the full positive
mint->exchange->write->read->delete->verify cycle, an injected-failure cleanup proof, and all 3
required negative-security proofs via the real client path. Two real regressions found and fixed
while building this proof (an emulator-only `apiKey` requirement, and a leaked Firestore gRPC
channel) -- both documented with what was actually broken and how the fix was confirmed load-bearing,
not just applied and assumed. Stated proof gaps: the 15s timeout has no induced-hang test yet; the
real Web API key needed for actual production Auth calls (`FIREBASE_WEB_API_KEY`) has no value
configured anywhere, since this sandboxed session has no live GCP credentials to obtain or verify it.

**Not built:** the Cloud Scheduler job, any `onSchedule` deployment, or any alert/notification
channel -- Step 9B, waiting on `FA-D1`, per GPT-PM's explicit scope split.

**9A final status, after 2 remediation rounds (full detail in `core/DECISION_LOG.md`): FINAL-APPROVED,
CLOSED.** GPT-PM's independent adversarial review of the initial closure found 2 real MAJORs --
unbounded cleanup/teardown, and an API-key placeholder that fell open unconditionally including
outside emulator mode. Round 1 (commit `0d74912`) added per-call cleanup/teardown budgets, an outer
45s hard deadline (`Promise.race` over the whole function body), a tri-state `cleanupSucceeded`
(`boolean | "unknown"`), a bounded pre-flight cleanup against prior-run residue, and gated the
placeholder behind emulator-mode detection -- closing MAJOR 1 outright and partially closing MAJOR 2
(GPT-PM found the emulator check used `OR` across two independently-connected services, letting a
partial configuration still receive the placeholder). Round 2 (commit `fbd6978`) required both
emulator host vars to agree before permitting either a real key or the placeholder, closing MAJOR 2
completely. Both rounds added real e2e proof, not just code changes: a genuine 15s induced-hang test
proving `runCanaryProbe()` returns within budget with `failureClass: "TIMEOUT"`, and 4 config tests
covering all 4 combinations of the two emulator host vars. Final e2e suite: 22/22. GPT-PM's closing
verdict: "Remaining scoped BLOCKER/MAJOR/MINOR -- NONE... Do not reopen it without concrete regression
evidence." Bounded-execution dimension: `READY_TO_ACTIVATE`. Production-Auth-connectivity dimension:
`IMPLEMENTED`/`TESTED`/`BLOCKED_CONFIG` (unchanged real gap -- no live GCP credentials in this session
to obtain the project's real Web API key). Not `ACTIVE`/`DONE` as a production runtime monitor: no
Scheduler, no Monitoring alert, `FA-D1` untouched, exactly as scoped throughout all 3 commits.
