# Monitor definitions -- Step 9 groundwork

Source-controlled DEFINITIONS only, per GPT-PM's ruling of 2026-08-27 (Rosetta
plan for Step 9A having already closed; this is the "remaining alert-independent
Step 9 groundwork" it authorized next). Nothing in this directory creates a live
GCP resource -- there is no deploy/apply script here, and none is added by this
change. See `core/DECISION_LOG.md` for the full exchange.

## Status per item

**Table below is not yet the authoritative status** -- MVP1.G3 Step 10C (`core/DECISION_LOG.md`,
2026-08-27) is a dedicated reconciliation pass over all 13 original OBS-1 items against current
HEAD + live production, and is the actual source of truth once it runs. The rows below are updated
opportunistically (Step 9B's closure, this file's own Step 10A addition) but have not all been
independently re-verified since Step 9B closed.

| Item | Definition | Live resource |
| --- | --- | --- |
| Stripe reconciliation-failure alert | `DEFINED`/`TESTED` | **LIVE** -- permanent policy active, FA-D1 channel attached and verified, real end-to-end proof (`core/DECISION_LOG.md`, Step 9B closure remediation) |
| Delete/export operational-failure alert | `DEFINED`/`TESTED`, see audit below | **LIVE** -- same, both permanent policies active with real end-to-end proof |
| App Check attested-ratio metric | `DEFINED`/`TESTED` | **LIVE** -- corrected 2026-08-27 (GPT-PM's Step 10A review MINOR: this row wrongly still said `HOLD`, contradicting Step 9B's own logged evidence). `appcheck_attestation` is one of the 5 metrics Step 9B created and live-verified (SHA-256 source==live match, `core/evidence/step9b_live_readback_2026-08-27.json`); the cost-model section below is now historical context for that earlier decision, not the current gating status |
| AI Gateway metrics (calls, latency, tokens, quota exhaustions) | `DEFINED`/`TESTED` | **LIVE_METRIC_CREATED / NO_PRODUCTION_PRODUCER** -- 4 metrics created in Step 9B without generating synthetic AI traffic; the 4 AI Gateway callables remain undeployed |
| AI Gateway investigation queries (7, `ai_gateway_definitions.ts`) | `DEFINED`/`TESTED` | `READY_TO_USE` -- plain filter strings, no GCP resource to create |
| Production canary probe-failure alert | `DEFINED`/`TESTED` | **LIVE** -- `runProductionCanary` deployed and scheduled, permanent policy active with real end-to-end proof |
| Enforcement-state check degraded/failed alert | `DEFINED`/`TESTED` (this entry) | Not yet activated -- see "Step 10A: enforcement-state visibility" below |

Every alert policy renders the real `google.monitoring.v3.AlertPolicy` REST
shape (`toAlertPolicyJson` in `types.ts`) with `notificationChannels: []` --
attaching a channel is exactly the FA-D1-gated step, and a policy with no
channels notifies nobody even if it were applied today. Every counter/
distribution metric in this directory, App Check included, renders the real
`google.logging.v2.LogMetric` REST shape
(`toCounterLogMetricJson`/`toDistributionLogMetricJson` in `types.ts`) with
`metricDescriptor.labels` + `labelExtractors`, not a bare filter string.

**App Check retrofit, 2026-08-27:** `APP_CHECK_ATTESTED_RATIO_METRIC` now
uses `CounterLogMetricSpec`, closing the inconsistency GPT-PM flagged (as a
non-blocking follow-up, not a finding) when it approved the AI Gateway
batch. One genuine difference from the AI Gateway metrics remains, stated
rather than glossed over: `noteAppCheck`'s `fn` parameter is a plain
`string`, not a closed TypeScript union the way `AiGatewayOperation` is --
there is no compile-time source of truth to derive `APP_CHECK_KNOWN_
CALLABLES`'s 17 values from. That list is a maintained copy (grep-verified
current, in `alert_definitions.ts`'s own comment), the same class of risk
the AI Gateway operation list had before its fix -- a new callable added
later will not appear in this metric until the list is updated by hand.
The separate guarantee that every real callable calls `noteAppCheck` at all
is `__tests__/scaling.test.ts`'s own source-scanning test -- extracted
(2026-08-27) into a shared `__tests__/discover_callables.ts` helper so it
has exactly one implementation, reused by
`__tests__/app_check_metric_parity.test.ts`, which mechanically compares
that discovered inventory against `APP_CHECK_KNOWN_CALLABLES` as exact
sets in both directions: a callable missing from the list, or a stale
entry with none discovered, both fail the test. `attested` needed one more
fix: it is a genuine boolean, and the shared `boundedLabelFilterClause`
renderer originally quoted every value as a string (`="true"`); GPT-PM's
correction (2026-08-27) on this file's own earlier wording: Cloud
Logging converts a filter's right-hand value to the field's own type
before comparing, so the quoted form was not established as failing to
match -- rendering BOOL-typed labels unquoted (`=true`) is the
type-correct form, not a fix for a proven mismatch.

## Resource shape: Gen2 (Cloud Run), corrected 2026-08-27

GPT-PM's review of the first version of this module (commit `41cb872`) found
it used `resource.labels.function_name` -- the Gen1 Cloud Functions Cloud
Logging shape. Every function in this project deploys via
`firebase-functions/v2` (Gen2, confirmed: `index.ts:44-45` imports `onCall`/
`onRequest` from `firebase-functions/v2/https`), which runs on Cloud Run.
Independently verified (not taken on GPT-PM's word alone, per the standing
evidence-over-assumption rule) via Google's own documentation and community
reports: Gen2 function log entries carry `resource.type="cloud_run_revision"`
and `resource.labels.service_name`, never `function_name` -- that shape is
Gen1-only. A Gen1-shaped filter against a Gen2 function matches zero real log
entries: a monitor that is silently green during an actual failure, the
precise failure mode this groundwork exists to prevent.

`toCloudRunServiceName` (`types.ts`) derives the Cloud Run service name from
each function's TypeScript export name using firebase-tools' documented
Gen2 deploy-time transform: uppercase -> lowercase, underscore -> hyphen
(Cloud Run service names are RFC1035 labels, which permit neither). E.g.
`deleteAccount` -> `deleteaccount`. **This transform is sourced from
firebase-tools' own release notes and issue tracker, not independently
confirmed against this project's live deployment** -- this session has no
`gcloud`/Cloud Logging access to read the actual deployed service names.
Treat the three service names used here as `READY_TO_ACTIVATE`, not as
already proven correct in production: before wiring a notification channel
(the FA-D1-gated step), confirm the real service names with one
`gcloud logging read` or a Cloud Console lookup against the live project.

## Failure-path inventory audit: `deleteAccount` / `exportAccountData`

GPT-PM's binding acceptance criterion (2026-08-27): before declaring the
delete/export monitor `DONE`, prove that its filter covers every operational
failure path, not only the ones with an explicit `logger.error(...)` call --
because a monitor that is silently green during a real failure outside its
known catch blocks is worse than no monitor.

**`deleteAccount` (`functions/src/index.ts:2060-2212`)** has three explicit
catch blocks, each already logging a distinct message (`DELETE_ACCOUNT_STRIPE_
CANCEL_FAILED`, `DELETE_ACCOUNT_FIRESTORE_DELETE_FAILED`, `DELETE_ACCOUNT_AUTH_
DELETE_FAILED`) and re-throwing as `HttpsError("internal", ...)`. One path is
NOT inside any of those three try blocks: the initial subscription-document
read at `index.ts:2086` (`await db.doc(...).get()`), which runs before the
first `try`. If that read throws, none of the three named messages fires.

**`exportAccountData` (`functions/src/account_export.ts:174-320`)** has one
explicit catch, logging `EXPORT_ACCOUNT_FAILED`. Its own top of function has no
equivalent pre-try read, but the same class of gap -- any future line added
before or between guarded sections -- would have the identical property: a
real failure with no named log line.

**What actually covers the gap (verified, not assumed):**
`functions/node_modules/firebase-functions/lib/common/providers/https.js:545-
570` wraps every `onCall` handler invocation in one try/catch:
`result = await handler(arg, responseProxy)` inside a `try`, and the `catch`
logs `logger.error("Unhandled error", err)` for anything that is **not**
already an `HttpsError` instance, before converting it to a generic
`HttpsError("internal", "INTERNAL")` for the client. Since every intentional
refusal in both functions (`unauthenticated`, quota, the three named
`deleteAccount` failures, the one named `exportAccountData` failure) is thrown
as `HttpsError`, that platform-level catch **only** fires for a genuinely
unclassified failure -- which is exactly the gap the pre-try Firestore read
represents, and exactly the property Option A of GPT-PM's DoD asked to have
proven rather than assumed.

This is Option A from GPT-PM's DoD: an existing platform-level signal, proven
(not merely believed) to catch every path the three-plus-one named messages do
not. No new application log line was needed (Option B). Both alert filters
therefore include `PLATFORM_UNHANDLED_ERROR` alongside their function's own
named messages, scoped by `resource.labels.service_name` (see "Resource
shape" above) so `deleteAccount`'s backstop entry never matches
`exportAccountData`'s and vice versa (see the negative-proof tests in
`__tests__/alert_definitions.test.ts`).

**Residual, stated rather than hidden:** this backstop depends on
`firebase-functions`' own internal implementation not changing shape on a
future SDK upgrade -- `functions/node_modules/.../https.js` is vendored
library code, not something this repo controls. If a future `firebase-
functions` major version stops logging under this exact message (or stops
distinguishing `HttpsError` from everything else the way v2's `onCall` does
today), the backstop silently stops working and only the three-plus-one named
paths would still fire. Re-verify this specific behavior against the then-
current `firebase-functions` version at the next major dependency bump.

## App Check attested-ratio metric: cost model (historical -- resolved, metric is now LIVE)

**Superseded 2026-08-27**: Step 9B's own production activation created this metric live
(`appcheck_attestation`, one of 5 metrics, SHA-256-verified against source in
`core/evidence/step9b_live_readback_2026-08-27.json`). The reasoning below is kept for the
record of how that HOLD was originally justified, not because the HOLD is still in effect.

GPT-PM's original ruling: a log-based metric DEFINITION may be written immediately (no CEO
decision needed for the definition itself), but creating the live GCP metric
resource requires either a real incremental-cost figure of $0 within the
current billing account's existing Monitoring allowance, or a separate
operator cost decision if it's nonzero or unknown.

This session has no access to the project's live GCP billing/usage data, so it
cannot supply a measured cost figure -- only a structural bound:

- **Cardinality is bounded, not traffic-dependent.** Labels are `fn` (the
  fixed set of ~13 `noteAppCheck` call sites enumerated in
  `alert_definitions.ts`'s comment, a compile-time-known list, not a
  user-supplied value) and `attested` (boolean). Maximum time series is
  therefore ~26, regardless of request volume -- log-based metric cost scales
  with the number of distinct label combinations (time series), not with the
  number of matched log entries themselves for a counter metric.
- **What is NOT known:** whether ~26 time series plus this project's other
  existing Monitoring usage together still fall inside the free allowance, or
  whether some of that allowance is already consumed by other metrics in this
  or a sibling GCP project on the same billing account. That is exactly the
  live-billing-data question this session cannot answer from the repository
  alone.

**Status:** definition `READY_TO_ACTIVATE`; live metric creation `HOLD` until
someone with GCP Console/billing access either confirms the incremental cost
is genuinely $0, or brings a nonzero/unknown figure to the operator as its own
cost decision -- per the global contract's standing rule that no monitoring
with confirmed-nonzero recurring cost ships without that decision.

## AI Gateway metrics and investigation queries (`ai_gateway_definitions.ts`)

GPT-PM's binding DoD (2026-08-27) named five dimensions the G3 AI Gateway
scope had already committed to covering: request rate, failures, timeout/
latency, quota-exhaustion pressure, and token/usage pressure. All five are
sourced from `ai_gateway.ts:312`'s single structured `ai_gateway: call` event
plus `abuse_guard.ts`'s two quota-enforcement log lines -- no new application
log line was needed.

- **`ai_gateway_calls`** (counter): `operation` x `outcome`, 4 x 3 = 12 max
  time series. Source for request rate, success rate, error rate, and
  timeout rate without choosing a threshold.
- **`ai_gateway_latency_ms`** (distribution): explicit buckets centered on
  this codebase's own configured per-operation timeouts (20s for equipment
  recognition/machine description, 25s for exercise generation, 45s for
  coach advice -- grep-verified against each callable's `timeoutMs`), with
  headroom to 90s to see genuine overshoot before the AbortSignal lands.
- **`ai_gateway_total_tokens_per_call`** (distribution): deliberately NOT
  filtered to `outcome="success"`. Verified by reading `ai_gateway.ts:278-
  286` directly: `usage = result.usageMetadata` is captured BEFORE the
  empty-answer check that can still throw and leave the final event at
  `outcome:"error"` -- a call that spent real tokens on an unusable response
  is exactly the pressure this metric exists to surface, not hide. The
  `jsonPayload.totalTokenCount:*` existence clause means "no usage field
  present" (a timeout before any response) is excluded rather than counted
  as zero.
- **`ai_gateway_quota_exhaustions`** (counter): reads `abuse_guard.ts:103`'s
  `"quota exceeded"` line, not the gateway event -- `generate()` cannot see
  a quota refusal because `enforceDailyQuota` runs and can throw BEFORE
  `generate()` is ever called (verified: grepped every `ai_*.ts` callable's
  call order). Bounded to exactly the four AI actions; `enforceDailyQuota`
  is also called for non-AI actions (`accountExport`, `clipUrl`, etc.),
  excluded by the filter itself, not just by comment.
- **7 investigation queries** (`queryAllCalls`, `queryFailures`,
  `queryTimeoutsFor(operation)`, `queryErrorsFor(operation)`,
  `queryUsagePresent`, `queryQuotaExhausted`, `queryQuotaCheckFailed`) --
  plain filter strings for Log Explorer / `gcloud logging read`, not metrics
  and not alert policies. `queryQuotaCheckFailed` is deliberately separate
  from `queryQuotaExhausted`: the former is the quota-enforcement backend
  itself failing (`abuse_guard.ts:124`, fails closed), not a caller
  legitimately over their limit.

**Drift resistance:** `"ai_gateway: call"`, `"quota exceeded"`, and `"quota
check failed"` now source from `log_signals.ts` the same way the Stripe/
delete/export literals do -- `ai_gateway.ts` and `abuse_guard.ts` import the
constants instead of retyping the strings. Purely mechanical, confirmed via
diff review: only the string literal became a named import at each call
site.

**Deliberately not built:** any threshold-based `AlertPolicy` (error rate,
p99 latency, token-cost paging). GPT-PM's own words: values like "alert if
error rate > 5%" or "latency > 8s" with no production baseline would be
invented. That is a separate, later operating-policy decision once real
traffic gives a baseline to set a threshold against -- not something to
guess a number for here.

## Step 9B: production activation (2026-08-27)

Unblocked the same day this groundwork batch closed: the operator corrected
an earlier session claim of "no live GCP access" -- both Firebase and GCP
access already existed and were verified live (`core/DECISION_LOG.md`'s
"CORRECTION" entry) -- and then chose, via `AskUserQuestion`, to activate
Step 9B in full immediately rather than defer it. Executed under a Rosetta
plan (`Fitness_App-2026-08-27T07-36-39-218Z-7e07c6`) with GPT-PM's GO, whose
own reply added one requirement beyond this session's original proposal: a
**4th, permanent canary-failure alert**, in addition to the three
business-failure policies above -- because a broken canary must read as an
incident, not silently stop proving anything.

- **`canary_schedule.ts`** wires `canary_probe.ts`'s `runCanaryProbe()`
  (built and approved in Step 9A, deliberately left without a trigger --
  see that file's own header) to a real `onSchedule` Cloud Function,
  `runProductionCanary`, every 30 minutes, `europe-west1`, bound to a
  `CANARY_WEB_API_KEY` secret via `defineSecret` -- the same pattern
  `index.ts` already uses for `STRIPE_SECRET_KEY`. **Not** `FIREBASE_WEB_
  API_KEY`, Step 9A's original working name: discovered live during Step 9B
  that Firebase's secret-name validation rejects `FIREBASE_`/`X_GOOGLE_`/
  `EXT_` as reserved prefixes, so both the secret and the env var
  `resolveFirebaseWebApiKey()` reads (`canary_probe.ts`) were renamed to
  `CANARY_WEB_API_KEY` in the same change -- a mechanical rename, no logic
  change, also applied to `__e2e__/canary_probe.e2e.test.ts`.
- A probe failure is thrown (not just logged), so it also surfaces as a
  genuine Cloud Run/Functions execution failure, on top of the structured
  `CANARY_PROBE_FAILED_EVENT` log line the new alert filter keys on. An
  unexpected REJECTION from `runCanaryProbe()` itself (a bug, not a
  captured failure -- that function is documented to never throw) is caught
  by the handler's own `SCHEDULE_HANDLER` backstop, which emits the same
  event before re-throwing -- covered by a direct regression test
  (`__tests__/canary_schedule.test.ts`, added in GPT-PM's round-2 review;
  round 1 had the fix but no test proving it).
- **`CANARY_PROBE_ALERT_POLICY`** (`alert_definitions.ts`) follows the same
  `LogMatchFilterSpec`/`AlertPolicySpec` shape as the three business-failure
  policies, matching only `CANARY_PROBE_FAILED_EVENT` -- deliberately NOT
  `PLATFORM_UNHANDLED_ERROR`, unlike those three: that message is specific
  to the onCall platform wrapper (`https.js`), and `runProductionCanary` is
  `onSchedule`, whose own wrapper never emits it (GPT-PM's round-1 finding,
  confirmed by reading both wrapper sources). `notificationChannels: []`
  until the FA-D1 channel is attached as a live, separate step (Step 3 of
  the Rosetta plan), same posture as the other three policies before this
  activation.
- **Scope limit, stated after GPT-PM's round-2 review corrected an
  overclaim**: this alert fires only when `runProductionCanary` actually
  EXECUTES and either the probe reports failure or the handler's own
  backstop catches an unexpected rejection. It cannot detect the Scheduler
  job being disabled/deleted or a Scheduler-to-Cloud-Run delivery failure --
  no function log exists to match if the function never runs at all. Real
  Scheduler-execution-health monitoring is a larger, separate scope, not
  built here.
- **Registered in `__tests__/scaling.test.ts`'s `ENTRYPOINTS`**, the same
  ceiling guard every other deployed function goes through, even though it
  is a scheduled function rather than a callable -- it still produces a v2
  `__endpoint` with `maxInstances`/`region`, and the file's own header says
  this list IS the registration.
- **Deploy constraint, binding from GPT-PM's GO:** only
  `firebase deploy --only functions:runProductionCanary` may be used for
  this change. A blanket `firebase deploy --only functions` would also
  redeploy the four AI Gateway callables (`aiCoachAdvice` and siblings),
  already exported from `index.ts` but deliberately kept undeployed --
  GPT-PM's explicit instruction was not to deploy them or generate synthetic
  AI traffic as part of this activation.
- **Not yet done as of this entry:** the live `gcloud`/`firebase` steps
  (secret creation, scoped deploy, FA-D1 notification-channel proof, live
  metric/policy creation, cleanup) -- see `core/DECISION_LOG.md` for
  per-step evidence as each one completes.

## Step 10A: enforcement-state visibility (2026-08-27)

GPT-PM's ruling on what remains of MVP1.G3 after Step 9B (`core/DECISION_LOG.md`, 2026-08-27):
OBS-1 item #3 (enforcement-status visibility) was left `PARTIAL` at the original G3 re-baseline --
`scripts/dev/production_manifest.py` already reads live Functions/Firestore-rules/App-Check/Hosting
state honestly, but it is a **human-run script**, not a repeatable automated check with mechanically
detectable staleness.

- **`functions/src/enforcement_state.ts`** -- the automated counterpart. Reads four live sections
  with the deployed function's own ambient service-account credentials (confirmed to already hold
  `roles/editor` on this project, per `gcloud projects get-iam-policy` -- no new IAM grant needed):
  deployed Cloud Functions inventory (`cloudfunctions.googleapis.com` v2 list), the active Firestore
  ruleset release (`firebaserules.googleapis.com`, same endpoint `production_manifest.py` already
  uses), App Check enforcement mode per service (`firebaseappcheck.googleapis.com`), and a strict
  ALLOWLIST of Identity Toolkit/Auth config fields (`identitytoolkit.googleapis.com/v2/.../config`).
  Every REST call is behind an injectable `deps` seam (`getAccessToken`/`fetchJson`), so
  `enforcement_state.test.ts` exercises every section's success/failure/degraded path without any
  live GCP credentials or network access.
- **Why Identity Toolkit only extracts an allowlist, never the raw response**: probed live before
  writing this file (`core/DECISION_LOG.md` has the field inventory). The raw config response
  carries `signIn.hashConfig.signerKey` (the project's password-hashing signer key -- a real secret)
  and `client.apiKey` (the same Web API key value this project already treats as a secret,
  `CANARY_WEB_API_KEY` in Secret Manager). `extractIdentityToolkitState()` reads only 9 specific,
  independently-chosen-safe fields (which sign-in methods are configured, MFA state, multi-tenant
  flag, authorized-domain count, SMS region allowlist flag, email-privacy flag, request-logging
  flag, whether blocking functions are configured) -- a denylist would leak the next secret-shaped
  field Google adds to that API; an allowlist cannot. Covered by a direct regression test asserting
  neither `signerKey` nor `apiKey` ever appears in the serialized output.
- **Overall status computation**: `OK` when all four sections read cleanly, `DEGRADED` when some but
  not all fail, `FAILED` when none can be read at all (including the case where even the access
  token itself cannot be obtained) -- GPT-PM's explicit DoD requirement that "a failed/stale
  collection becomes FAILED/DEGRADED, not silently green."
- **`functions/src/enforcement_state_schedule.ts`** -- the Cloud Scheduler wiring, same
  one-export-nothing-else shape and SCHEDULE_HANDLER backstop pattern as `canary_schedule.ts`
  (`runEnforcementStateCheck()` is documented to never throw; the backstop covers a genuinely
  unexpected rejection). Runs every 6 hours (config/rules state moves far slower than the canary's
  user-facing path, so the canary's 30-minute cadence is unnecessary cost here).
  `maxInstances: 1` + `concurrency: 1`, same single-flight discipline as the canary, registered in
  `scaling.test.ts`'s `ENTRYPOINTS` (nineteenth entry) with its own dedicated single-flight test.
  Any non-`OK` result is both logged under `ENFORCEMENT_STATE_DEGRADED_OR_FAILED_EVENT` (the literal
  the new `ENFORCEMENT_STATE_ALERT_POLICY` keys on, same 4th-policy-style pattern GPT-PM required
  for the canary) AND thrown, so it also surfaces as a genuine Scheduler execution failure --
  `gcloud scheduler jobs describe` then gives a second, GCP-native way to mechanically check
  "did the last run even succeed" without needing any new Firestore/storage write target.
- **Deploy constraint, same as Step 9B**: only
  `firebase deploy --only functions:runEnforcementStateCheck` may be used -- never a blanket
  Functions deploy, for the same reason (the four AI Gateway callables must stay undeployed).
- **Not yet done as of this entry**: the live deploy itself, the positive proof (a real run against
  live production), and the negative/staleness proof (a deliberately induced failure reading as
  DEGRADED/FAILED) -- see `core/DECISION_LOG.md` for evidence as each completes. `google-auth-library`
  added as an explicit `functions/package.json` dependency (was already present hoisted via
  `firebase-admin`, pinned at the already-resolved `9.15.1`).

### Step 10A remediation round (2026-08-27, same day)

GPT-PM's review of the first Step 10A submission found 4 real MAJORs and 1 real MINOR, all fixed
in one batch rather than argued over (`core/DECISION_LOG.md` has the full exchange):

1. **Reachability was being reported as correctness.** `OK` used to mean only "the API call
   succeeded," not "the returned state is actually what a healthy production should look like." Now
   `checkFunctions`/`checkFirestoreRules` fail closed (`UNAVAILABLE`) on a genuinely empty result --
   this project always has deployed functions and a published ruleset, so zero of either is far more
   likely to be a permission/API regression than reality. App Check is deliberately exempt (zero
   services is a real, meaningful state here, not an error) but now derives an explicit
   `anyEnforcementOff` signal from whatever services it does see.
2. **Malformed HTTP-200 responses used to fail open.** A non-object body, or a list key present but
   not an array, is now `UNAVAILABLE` with a named reason instead of silently defaulting to an empty
   list. Identity Toolkit additionally requires its own `name` field to be present -- the cheapest
   signal that a real config object, not some other 2xx-status body, actually came back.
3. **Pagination was unhandled.** `fetchAllPages()` now follows every list endpoint's
   `nextPageToken`, bounded to 20 pages so a malfunctioning API returning a repeating token cannot
   loop the function forever. Not currently exercised at this project's live scale (no endpoint
   returns a second page today, confirmed by direct probe before this remediation) but no longer a
   silent gap if that changes.
4. **Staleness detection relied entirely on this function's own log/execution.** Added
   `ENFORCEMENT_STATE_STALENESS_POLICY` (`alert_definitions.ts`) -- a genuinely independent,
   GCP-native `conditionAbsent` alert on `cloudscheduler.googleapis.com/job/execution_count`, a
   metric the PLATFORM emits automatically per Scheduler execution regardless of whether this
   codebase's own code or logging ever runs. Required extending `types.ts` with a
   `MetricAbsenceAlertPolicySpec`/`toMetricAbsenceAlertPolicyJson()` -- the first non-LogMatch alert
   condition type in this module. Also added per-request timeouts (`REQUEST_TIMEOUT_MS = 20_000`,
   via `AbortSignal.timeout`) well under the function's own 60s platform timeout, so one hung
   request can no longer silently consume the whole budget.
5. **MINOR, self-contradicting evidence**: this file's own status table said the App Check metric
   was still `HOLD` after Step 9B had already created and live-verified it -- fixed, see the table
   above and the cost-model section's new "superseded" note.

Found independently during this remediation, not one of GPT-PM's 5 named findings: a direct curl
probe against `firebaseappcheck.googleapis.com` (same `SERVICE_DISABLED`/quota-project 403 pattern
already known from Identity Toolkit and Firestore Rules) showed `checkAppCheck()` was the one
section missing the `X-Goog-User-Project` header. Fixed, with a dedicated regression test.

The Scheduler job ID `ENFORCEMENT_STATE_STALENESS_POLICY` filters on
(`firebase-schedule-runEnforcementStateCheck-europe-west1`) follows Firebase's documented naming
convention but is **not yet independently confirmed against a live deployment** -- this function has
not been deployed yet. Verify via `gcloud scheduler jobs list` once it is, same live-check
discipline every other identity in this file received before being treated as proven.

Also caught during verification (not a GPT-PM finding, a real bug in the new pagination test
itself): the four sections run concurrently (`Promise.all`), so their first-page `fetchJson` calls
interleave before any of them resolves -- a positional `mockResolvedValueOnce` chain, which every
other test in this file relies on safely because each section made exactly one call, silently broke
once the Functions section could make two. `npm run build` was clean but `npx jest` caught it
immediately (count 1 instead of 2). Rewritten to dispatch on the request URL instead of call order,
which is stable regardless of interleaving; full suite reconfirmed green (489/489) afterward.

### Step 10A remediation round 2 (2026-08-27, same day)

GPT-PM re-reviewed the round-1 commit and found the same 4 original findings still open in a
deeper form -- not new scope, the acceptance criterion for each wasn't actually met yet
(`core/DECISION_LOG.md` has the full exchange):

1. **App Check enforcement checking was silently dead on arrival.** Round 1's `anyEnforcementOff`
   compared `enforcementMode` against the literal `"OFF"` -- a live probe this round confirmed the
   real API only ever returns `"ENFORCED"`/`"UNENFORCED"`, so the comparison could never match
   anything real. Fixed to treat anything other than `"ENFORCED"` as not-enforced. Separately, an
   empty/partial `services.list` result was being treated as an unremarkable state regardless of
   what this project's OWN architecture actually needs enforced -- `firestore.rules` grants
   authenticated clients direct read/write access to `/users/{uid}/...` with no App-Check gate of
   its own, so backing-service-level enforcement on `firestore.googleapis.com` is the only control
   that can require attestation on that path at all. Added
   `APP_CHECK_INTENDED_ENFORCED_SERVICES = ["firestore.googleapis.com"]` and
   `unenforcedIntendedServices`, which now correctly flags this service whether it's present-but-
   unenforced or entirely absent from the list. A live probe during this round confirmed
   `firestore.googleapis.com` is currently, actually `UNENFORCED` in production -- exactly the state
   this fix makes visible that round 1 could not have caught even if the row had been missing
   outright.
2. **Row-level fields were still defaulting to `"?"` instead of being rejected.** A non-empty,
   well-formed list could still contain a row missing the field this file actually needs (function
   `state`, rule `rulesetName`, App Check `enforcementMode`); round 1's `?? "?"` fallback reported
   that as `OK`. Every section now rejects the WHOLE section (not a silently shrunk item count) on
   any row missing its required identifying fields. Firestore Rules additionally requires that one
   of the valid rows specifically be the `cloud.firestore` release (confirmed live:
   `projects/{project}/releases/cloud.firestore`) -- a non-empty list containing some other release
   but not this project's actual ruleset used to read as `OK`.
3. **Cloud Functions' `unreachable[]` was silently discarded.** The v2 list API can return locations
   it could not query, with functions there simply missing from `functions[]` and no other signal.
   `fetchAllPages()` now accumulates `unreachable` across every page; a non-empty result makes the
   Functions section `UNAVAILABLE` while retaining the partial data it did read.
4. **The per-request timeout didn't bound the whole probe.** `fetchAllPages` can make up to 20
   sequential calls for one section; enough near-timeout pages could still exhaust the function's own
   60s platform budget before this file's own try/catch/log ever ran -- silently recreating the exact
   gap the per-request timeout was meant to close. Added a single `PROBE_BUDGET_MS = 45_000` deadline
   computed once (before token acquisition, so that counts too) and threaded into every section and
   every page: each request checks remaining budget first and fails closed instead of firing with no
   real chance to matter, with its own timeout capped to whatever budget remains. Read through the
   same injectable `deps.now` seam as everything else, so tests simulate the clock crossing the
   deadline without real elapsed time or fake system timers.

Also addressed, called out by name in GPT-PM's reply as a real gap even though not one of the 4
MAJORs: the scheduled function's success path still only logged 3 counts, not the actual
ruleset/App-Check/function state a human or alert would need to act on. `enforcement_state_schedule.ts`
now logs `result.sections` in full on success -- safe to do wholesale because every section's `data`
was already individually constructed to be safe (Identity Toolkit's strict allowlist in particular).

**Verification**: `npm run build` clean. Full suite: **21 suites, 497 tests, all passed** (up from
489, +8: App Check intended-service tests, 3 row-validation tests, the `cloud.firestore`-required
test, the `unreachable[]` test, and 2 probe-deadline tests).

**Still not done**: no deploy, no live resource creation, no positive/negative proof -- unchanged
from round 1's own note above. This commit goes back to GPT-PM, scoped to exactly these findings
plus any direct regressions.

### Step 10A remediation round 3 (2026-08-27, same day)

GPT-PM re-reviewed round 2 and closed 3 of the 4 findings (App Check enforcement, `unreachable[]`,
success-state observability) but found 2 real residuals:

1. **MAJOR -- token acquisition itself was never bounded by the deadline.** `deadlineAt` was
   computed before `deps.getAccessToken()` so its elapsed time counted against the budget, but
   nothing actually RACED `getAccessToken()` against it -- a hang there (ADC/metadata/token-exchange)
   could still consume the whole 60s platform timeout before any section, or this file's own
   try/catch/log, ever ran. Added `deps.raceDeadline()`, an injectable seam that races a promise
   against the SAME remaining deadline (never a second, independent timer -- GPT-PM's explicit
   requirement) and is used for token acquisition. The real implementation clears its timer on
   whichever branch wins and `.unref()`s it, so a normal run never leaks a live timer into the
   background (this suite has already shown a "worker process failed to exit gracefully... active
   timers" warning once before, from an unrelated cause -- deliberately not adding a real one here).
2. **MAJOR -- a `cloud.firestore` release could still be `OK` with no genuine `updateTime`.** Step
   10A's own DoD is "active Firestore ruleset + update time," not just "a release exists." The
   `cloud.firestore` row now also requires a non-empty `updateTime` that `Date.parse` accepts, or the
   section reports `UNAVAILABLE`. Functions' `updateTime` is now required the same way (always
   present per the v2 API contract); `revision` stays best-effort, since its presence is
   generation-dependent in ways this file has no live GEN_1 deployment to verify against -- a
   deliberate, documented scoping call, not an oversight.

**Verification**: `npm run build` clean. Full suite: **21 suites, 501 tests, all passed** (up from
497, +4: 2 deadline-races-token-acquisition tests and 2 updateTime-validation tests). Also confirmed
no leaked timer handles from the new `setTimeout`-based race (`npx jest --detectOpenHandles`, clean).

**Still not done**: no deploy, no live resource creation, no positive/negative proof. This commit
goes back to GPT-PM, scoped to exactly these 2 findings plus any direct regressions.

### Step 10A live activation (2026-08-27, same day, operator-authorized)

GPT-PM's round-3 review returned APPROVE with `final:true`; the actual live deploy is a production
migration reserved for the operator's own separate confirmation (`~/.claude/CLAUDE.md` §4) even
with a broader GO -- authorized explicitly ("деплоить") after the checkpoint was surfaced.

- **Deploy**: `firebase deploy --only functions:runEnforcementStateCheck` -- targeted, not blanket.
  Live functions list confirmed 16 total, the four AI Gateway callables (`aiCoachAdvice`,
  `aiEquipmentRecognition`, `aiExerciseGeneration`, `aiMachineDescription`) absent, exactly as
  required.
- **Scheduler job ID confirmed live, no correction needed**:
  `firebase-schedule-runEnforcementStateCheck-europe-west1` (`gcloud scheduler jobs list`) matches
  `ENFORCEMENT_STATE_SCHEDULER_JOB_ID` exactly.
- **Real API constraints found live, both fixed at the source, neither known before hitting them**:
  1. `conditionAbsent.duration` rejects anything over 23h30m -- the original `absentFor: "86400s"`
     (24h) was never valid; changed to `"64800s"` (18h), still >=3 missed 6-hour cycles before firing.
  2. `notificationRateLimit` is rejected outright on a metric-absence (`conditionAbsent`) policy --
     "only log-based alert policies may specify" one. Removed `notificationRateLimitPeriod` from
     `MetricAbsenceAlertPolicySpec` and its renderer entirely (`types.ts`); `LogMatchAlertPolicySpec`
     keeps it, since only that type is actually allowed to have it.
- **Positive proof**: the Scheduler job was triggered manually (`gcloud scheduler jobs run`) for a
  genuine execution rather than waiting up to 6h for the next natural cycle. Log line
  `"enforcement_state_schedule: check succeeded"` confirmed with the full sanitized state snapshot
  attached -- all 4 sections `OK`, 16 functions inventoried, App Check's live
  `unenforcedIntendedServices: ["firestore.googleapis.com"]` visible exactly as the round-2/3 code
  was built to surface, no secret-shaped field present anywhere in the Identity Toolkit section.
  Evidence: `core/evidence/step10a_positive_proof_2026-08-27.json`.
- **Negative proof**: one synthetic, clearly-marked log entry
  (`test_marker: "step10a_synthetic_enforcement_state_proof_2026_08_27"`, `synthetic: true`, an
  explicit `purpose` string) written via `gcloud logging write` to log `fa-d1-policy-proof`, carrying
  the REAL deployed Cloud Run resource labels (`service_name=runenforcementstatecheck`, the actual
  revision name) -- not a fabricated resource. Confirmed to match
  `ENFORCEMENT_STATE_FAILURE_FILTER` byte-for-byte via `gcloud logging read`. Evidence:
  `core/evidence/step10a_negative_proof_2026-08-27.json`. Same limitation as every prior synthetic
  proof in this project: no server-side incident/notification API this session has found, so real
  email delivery needs the operator's own confirmation.
- **Independent staleness-alert proof**: the failure policy
  (`alertPolicies/17310925602537777726`) created and verified live. The staleness policy's own
  creation initially failed with `404 Cannot find metric(s)` -- `cloudscheduler.googleapis.com/job/execution_count`
  had never been emitted for this specific job before the manual trigger above, and propagation for a
  brand-new metric+resource combination took longer than the API's own "up to 10 minutes" message.
  [Status of this specific item -- filled in once the metric propagates and the policy is created;
  see the entry immediately following this one, or `core/DECISION_LOG.md` if this note is stale.]
