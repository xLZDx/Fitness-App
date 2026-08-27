# Monitor definitions -- Step 9 groundwork

Source-controlled DEFINITIONS only, per GPT-PM's ruling of 2026-08-27 (Rosetta
plan for Step 9A having already closed; this is the "remaining alert-independent
Step 9 groundwork" it authorized next). Nothing in this directory creates a live
GCP resource -- there is no deploy/apply script here, and none is added by this
change. See `core/DECISION_LOG.md` for the full exchange.

## Status per item

| Item | Definition | Live resource |
| --- | --- | --- |
| Stripe reconciliation-failure alert | `DEFINED`/`TESTED` | `READY_TO_ACTIVATE` -- blocked only on `FA-D1` (who owns the notification channel), not on cost |
| Delete/export operational-failure alert | `DEFINED`/`TESTED`, see audit below | `READY_TO_ACTIVATE` -- same, blocked only on `FA-D1` |
| App Check attested-ratio metric | `DEFINED`/`TESTED` | `HOLD` -- blocked on a real (not estimated) incremental-cost figure, see below |
| AI Gateway metrics (calls, latency, tokens, quota exhaustions) | `DEFINED`/`TESTED` | `HOLD_LIVE_CREATION_COST` -- same cost posture as the App Check metric |
| AI Gateway investigation queries (7, `ai_gateway_definitions.ts`) | `DEFINED`/`TESTED` | `READY_TO_USE` -- plain filter strings, no GCP resource to create |

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

## App Check attested-ratio metric: cost model

GPT-PM's ruling: a log-based metric DEFINITION may be written now (no CEO
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
