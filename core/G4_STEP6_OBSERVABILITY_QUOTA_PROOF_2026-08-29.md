# G4 Step 6 — observability activation + real quota-exhaustion proof

## DoD (from the gate's own binding exit criteria)

"observability activation incl. a real quota-exhaustion proof."

## What already existed (G3, confirmed still live)

The AI Gateway monitoring definitions (`functions/src/monitoring/ai_gateway_definitions.ts`) and
their live GCP log-based metrics were created during MVP1.G3 Step 9B (`core/DECISION_LOG.md`,
"2026-08-27"), recorded then as `LIVE_METRIC_CREATED / NO_PRODUCTION_PRODUCER` because the four
AI callables were undeployed at that time. Re-confirmed live today via
`gcloud logging metrics list`: `ai_gateway_calls`, `ai_gateway_latency_ms`,
`ai_gateway_total_tokens_per_call`, `ai_gateway_quota_exhaustions`, `appcheck_attestation` — all
five still present, unchanged.

No threshold-based AlertPolicy exists for these by design — GPT-PM's binding ruling (2026-08-27,
cited in the source file's own header): a threshold invented without a production baseline is
worse than none. Out of scope for this step; not treated as a gap.

## What Step 6 actually needed to prove

1. **The metrics now have real producers** — Steps 4-5 deployed the AI callables and made real
   calls; do the metrics actually show it, or is `NO_PRODUCTION_PRODUCER` still the live state?
2. **A genuine quota-exhaustion event, live** — not a code read, an actual `resource-exhausted`
   rejection captured by both the structured log and the metric.

## Evidence

**1. Real production data confirmed.** Queried `monitoring.googleapis.com/v3/.../timeSeries` for
`ai_gateway_calls` over the Step 4-5 test window: a real data point,
`operation: aiCoachAdvice, outcome: success, value: 1`, timestamped to the exact minute of the
Step 5 positive-control call. The metric is no longer `NO_PRODUCTION_PRODUCER`.

**2. Real quota-exhaustion proof, end to end.** Rather than making 40 real (billed) Vertex calls
to reach `aiExerciseGeneration`'s real daily ceiling, seeded `users/{uid}/usage/{today}` directly
via the Firestore REST API to `aiExerciseGeneration: 40` (the real configured limit,
`QUOTAS.aiExerciseGeneration` in `abuse_guard.ts`) for a throwaway test uid — this exercises the
exact same `enforceDailyQuota` transaction/comparison code path the 41st call would take after 40
successful daily calls (the code refuses on `used + cost > limit`, so seeding `used=40` and then
calling once reproduces exactly that state), without the cost of the preceding 40. Called
`aiExerciseGeneration` once with valid Auth + valid App Check debug token:

| Check | Result |
|---|---|
| HTTP response | `429`, `{"error":{"message":"You have reached today's limit for this action. It resets tomorrow.","status":"RESOURCE_EXHAUSTED"}}` |
| Structured log (`abuse_guard.ts:107`) | `severity: WARNING`, `{action: "aiExerciseGeneration", uid: "g4-step4-app-check-probe", used: 40, limit: 40, cost: 1}` |
| Live metric (`ai_gateway_quota_exhaustions`) | one data point, `value: 1`, `operation: aiExerciseGeneration`, at the exact minute of the call |

All three layers — the HTTP contract the client sees, the structured log a human/alert would
read, and the aggregated metric a dashboard would show — independently confirm the same real
event. No mocking: `enforceDailyQuota`'s real Firestore transaction ran and refused for real.

## Round 1 GPT-PM review: MAJOR — only 2 of 5 metrics had confirmed real data

**MAJOR (confirmed real)**: the original evidence queried `ai_gateway_calls` and
`ai_gateway_quota_exhaustions` only. A successful point in the call counter does not prove the
latency/token distributions' own `EXTRACT()` label paths are actually working — they read
different fields (`jsonPayload.latencyMs`, `jsonPayload.totalTokenCount`) that could be absent or
mis-mapped in real Gemini responses while the call counter alone stayed green. `appcheck_attestation`
was also never re-checked for a real AI-callable producer. Explicitly bounded: query the *existing*
Step 4-5 window, no new Vertex calls needed.

**Executed — all three queried against the same Step 4-5 time window, no new calls made:**

| Metric | Real data found |
|---|---|
| `ai_gateway_latency_ms` | 6 series, e.g. `aiCoachAdvice/success`: 1 sample, mean 3133ms; `aiEquipmentRecognition/success`: mean 2451ms |
| `ai_gateway_total_tokens_per_call` | 4 series, e.g. `aiCoachAdvice/success`: mean 678 tokens; `aiEquipmentRecognition/success`: mean 1472 tokens |
| `appcheck_attestation` | 4 series, all four AI functions show `attested: true` counts (2-3 points each) |

All five AI Gateway metrics now independently confirmed with genuine, non-mock production data
from the same real calls Steps 4-5 already made — no additional Vertex cost incurred.

**MINOR (confirmed, wording only)**: the report described the seeded state as modeling "the 40th
call" — the code actually allows the 40th (`39 + 1 > 40` is false at `used=39`) and refuses the
*41st* (`40 + 1 > 40` is true at `used=40`). Corrected above; no change to the seeded value (40
was already correct) or the test's validity, just its description.

## Cleanup

Seeded usage document deleted, throwaway test Auth user deleted, temporary
`roles/iam.serviceAccountTokenCreator` grant revoked — same lifecycle as every prior step's
temporary probes.

## Status

Round 1 fix applied (no code change, just the two additional queries + wording correction).
Round 2 flagged one remaining wording MINOR, fixed via an append-only correction note. Round 3:
`VERDICT: APPROVE`, final. Next gate step: Step 7 (product-level real-device E2E on the S8).
