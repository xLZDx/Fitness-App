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

None of the three has a notification channel attached in its definition
(`notificationChannels: []` is the intended shape when one is eventually
rendered to a real `google_monitoring_alert_policy`) -- attaching a channel is
exactly the FA-D1-gated step.

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
named messages, scoped by `resource.labels.function_name` so `deleteAccount`'s
backstop entry never matches `exportAccountData`'s and vice versa (see the
negative-proof tests in `__tests__/alert_definitions.test.ts`).

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
