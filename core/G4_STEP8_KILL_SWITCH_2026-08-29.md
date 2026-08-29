# G4 Step 8 — rollback mechanism: a live, redeploy-free kill switch for the AI Gateway

## Definition of Done (from GPT-PM, not self-authored)

Obtained by direct question through `review.js` (`--commit ecded8d --scope-note-file
g4_step8_dod_question.md`), VERDICT APPROVE, GO AUTHORIZED, since neither Step 8 nor Step 9 had a
stated DoD anywhere in this repo before this gate step:

- Server-side kill switch for all 4 AI Gateway callables (`aiCoachAdvice`, `aiEquipmentRecognition`,
  `aiMachineDescription`, `aiExerciseGeneration`), effective **without a function redeploy**.
- Evaluated before quota charging and before Vertex/Gemini invocation.
- Client-side UI flag optional/recommended, never the security control.
- One generic kill switch is sufficient (not separate cost-vs-safety switches), recording a
  reason/category.
- Does **not** require model rollback or a full undeploy/redeploy drill (a separate mechanism).
- Eight binding proof points (reproduced in the evidence table below).

## Why an env var could not satisfy this

This codebase's existing enforcement flags (`APP_CHECK_ENFORCED_AI` and friends, `scaling.ts`) are
baked into gen2 Cloud Functions at deploy time — the only way to change them is
`gcloud functions deploy --update-env-vars` plus a redeploy. That is structurally incapable of "live
disable, no redeploy."

## Design — Secret Manager, not Firestore (revised after round 1)

The first version of this step used a Firestore document (`system/aiGateway`). **GPT-PM's round-1
review found that fundamentally unsound**: `fn-ai-runtime` — the identity running the very code
being disabled — already holds project-wide `roles/datastore.user` for quota accounting
(`core/G4_STEP3_IAM_RUNTIME_CONFIG_2026-08-28.md`), and Firestore has no collection-level IAM, so
that grant cannot be narrowed to exclude one document. `firestore.rules` does not help either — the
Admin SDK bypasses Security Rules entirely. A compromised or buggy `fn-ai-runtime` could simply
write `enabled: true` back to its own kill switch, defeating the one property this mechanism exists
for: an operator being able to turn AI off *from the outside*.

**Moved the control plane to Secret Manager**, which grants IAM per-secret, independent of
Firestore's project-wide grant:

- **`ai-gateway-kill-switch`** — a single secret whose latest version's payload is JSON:
  `{enabled, reason, updatedAt, updatedBy}`.
- **`fn-ai-runtime` holds `roles/secretmanager.secretAccessor` scoped to exactly this one secret** —
  read-only, verified by IAM policy inspection to carry no broader Secret Manager role, and nothing
  grants it version-add/update rights on it. Flipping the switch means adding a new secret version,
  which only an operator identity can do. Same secret-level IAM scoping pattern `fn-billing`'s
  `STRIPE_*` access already uses in this codebase — applied here for the first time as the
  *authoritative* control rather than a credential the function merely reads for its own use.
- **`enforceAiGatewayEnabled(fn)`** (`functions/src/abuse_guard.ts`) calls
  `SecretManagerServiceClient.accessSecretVersion` through a short bounded cache — **current state,
  after round 2's remediation below**: at most one real Secret Manager access per 5 seconds
  (`CONTROL_CACHE_TTL_MS`) per warm instance, the in-flight promise itself shared across concurrent
  callers within that window, not a fresh read on every single invocation. (Round 1 originally read
  fresh every call with no cache at all — GPT-PM's round-2 review found that left an unbounded read
  path a valid caller could still trigger via retries; see the round 2 section below for why and
  what changed. Round 1's own evidence table further down describes that earlier, now-superseded
  no-cache behavior and is kept as a historical record of what round 1 actually proved, not the
  mechanism's current shape.) Not `defineSecret` (the pattern `STRIPE_SECRET_KEY` uses) — that binds
  a value into `process.env` once per container at cold start, so an already-running warm instance
  would keep serving the old value, the opposite of what a kill switch needs.
- **Ordering, also revised after round 1**: GPT-PM's review additionally found the round-1 placement
  (literal first line, before even the auth check) let an unauthenticated-but-App-Check-valid caller
  trigger this read on every retry with no ceiling at all — a new unmetered read path. The DoD only
  requires the switch to run before quota charging and Vertex, never before auth, so the check now
  runs after `request.auth`/`enforceNonAnonymousForAi` but still before `enforceDailyQuota`/
  `generate` in all 4 callables.
- **Three server states, one client contract**, unchanged from round 1: a deliberate disable, an
  empty/missing secret payload, and a Secret Manager read throwing all produce the identical
  `HttpsError("unavailable", "AI features are temporarily unavailable. Please try again later.")` —
  logged under two different structured event names (`monitoring/log_signals.ts`) so an operator can
  tell them apart: `AI_GATEWAY_DISABLED_REJECT_EVENT` (`logger.warn`, carries `reason`) vs.
  `AI_GATEWAY_CONTROL_READ_FAILED_EVENT` (`logger.error`, carries `err`). Strict `enabled === true`,
  not truthy coercion.
- **Firestore**: the now-unused `system/aiGateway` document was deleted and the `firestore.rules`
  `system/{docId}` deny block removed — the mechanism no longer touches Firestore at all, so keeping
  either would be a stale artifact referencing a design that no longer exists.

## What changed

- `functions/package.json` — added `@google-cloud/secret-manager`.
- `functions/src/monitoring/log_signals.ts` — two new exported event-name constants.
- `functions/src/abuse_guard.ts` — `enforceAiGatewayEnabled()`, Secret Manager-backed.
- `functions/src/ai_coach_advice.ts`, `ai_equipment_recognition.ts`, `ai_machine_description.ts`,
  `ai_exercise_generation.ts` — one `await enforceAiGatewayEnabled("<fn>");` each, after
  auth/non-anonymous, before quota/generate.
- `firestore.rules` — the `system/{docId}` block added in round 1 was removed in remediation (dead
  once the control plane moved off Firestore).
- `functions/src/__tests__/abuse_guard.test.ts` — 9 tests on `enforceAiGatewayEnabled` after round 2
  (enabled, disabled+reason, error code, non-boolean, empty payload, unparseable payload, client
  throw, concurrent-calls-cost-one-real-access, cache-hit-still-logs-per-call), all against a mocked
  `SecretManagerServiceClient`.
- `functions/src/__tests__/ai_coach_advice.test.ts`, `ai_equipment_recognition.test.ts`,
  `ai_machine_description.test.ts`, `ai_exercise_generation.test.ts` — one test each, mocked the
  same way.

**Current totals (after round 2): full suite 548/548 passing.** `tsc --noEmit` clean, `npm run
build` clean. Round 1's own commit-point state was 546/546 (7 kill-switch tests, no cache) — see
the round 1 evidence section below, kept as the historical record of what round 1 proved. Deployed:
`firebase deploy --only functions:aiCoachAdvice,functions:aiEquipmentRecognition,functions:aiMachineDescription,functions:aiExerciseGeneration,firestore:rules --project fitness-app-korostelev`
(round 1), redeployed functions-only after round 2's cache fix.

## Round 1 GPT-PM review: 1 MAJOR, 2 MINOR — all remediated

**MAJOR (confirmed real, verified against `core/G4_STEP3_IAM_RUNTIME_CONFIG_2026-08-28.md`)**:
`fn-ai-runtime` held project-wide `roles/datastore.user`, so the Firestore-backed switch was not an
independent control — the identity being disabled could write itself back on. **Fix**: moved to
Secret Manager, IAM-scoped per-secret (design section above). **New adversarial proof added**:
impersonated `fn-ai-runtime` directly and confirmed `accessSecretVersion` succeeds (`200`) while
`addSecretVersion` is denied (`403 PERMISSION_DENIED: secretmanager.versions.add`) — the exact
proof GPT-PM asked for.

**MINOR**: the control-plane read sat before the auth check, so an unauthenticated caller could
trigger it on every retry with no quota bound. **Fix**: reordered to after
auth/`enforceNonAnonymousForAi`, still before quota/Vertex — matches the DoD, which only requires
the latter.

**MINOR**: the original live-drill evidence said "only one `ai_gateway: call` log line exists all
drill," ambiguous against the recovery calls at points 6/8 which should also have produced one each.
**Fix**: reran the drill with per-step UTC timestamps recorded at call time and reconciled every log
line against them (evidence table below) rather than describing the result in prose.

## Live drill, rerun on the remediated Secret Manager mechanism (europe-west1)

**Historical record of round 1's mechanism** (fresh Secret Manager read on every single invocation,
no cache — superseded by round 2's bounded cache described above; kept here unchanged as evidence of
what this specific drill actually proved, not a description of the current implementation).

Same transport fixes as round 1 (Browser API key instead of the Android-restricted key from
`google-services.json`; App Check debug token exchanged for a real JWT via
`exchangeDebugToken`), fresh test identity (`g4-step8-remediation-probe`).

| # | Proof point | Timestamps (UTC) | Result |
|---|---|---|---|
| 1 | Normal state, switch ON, one bounded call | call 08:42:27–35 | `200`, real response |
| 2 | Live disable, no redeploy | `gcloud secrets versions add` 08:42:43–49 | version 2 created, read-back confirmed |
| 3 | All 4 reject the same way | calls 08:43:02–12 | all 4: `503 UNAVAILABLE`, identical message |
| 4 | Pre-provider — quota untouched, Vertex not called | — | usage doc `aiCoachAdvice: 3` = exactly the 3 successful calls (points 1, 6, restore-check); zero increment across either disabled window |
| 5 | Observability | disabled-reject events 08:43:04.31–08:43:13.22 | 4 `AI_GATEWAY_DISABLED_REJECT_EVENT` lines, one per callable, `reason=g4_step8_remediation_drill`, no PII |
| 6 | Recovery, no redeploy | flip 08:43:24–30, call 08:43:30–35 | `200` |
| 7 | Durability | — | at the time of this drill: structural, fresh Secret Manager read every invocation, no cache; also exercised across point 3's 4 separate deployed Cloud Run services. (After round 2: durability instead rests on a new instance always starting with an empty cache, so its first call is still always a genuine fresh read regardless of the 5s TTL — see round 2 section.) |
| 8 | Fail-safe on unreadable control plane | disable version 08:43:56–08:44:02, call 08:44:02–03 | `503 UNAVAILABLE`; distinct `AI_GATEWAY_CONTROL_READ_FAILED_EVENT` at 08:44:04.44 carrying the real cause (`FAILED_PRECONDITION: Secret Version ... is in DISABLED state`); restored 08:44:11–17, next call `200` at 08:44:23 |
| — | Adversarial IAM proof (new, round-1 remediation) | — | Impersonated `fn-ai-runtime`: `accessSecretVersion` → `200` (reads); `addSecretVersion` → `403 PERMISSION_DENIED: secretmanager.versions.add` (cannot write) |

**Reconciliation** (closes round 1's MINOR on ambiguous logging): exactly 3 `ai_gateway: call`
events exist in the entire rerun window (08:42:36, 08:43:36, 08:44:23) — one per successful call,
none during either disabled interval (08:43:02–12, 08:43:56–08:44:03). Exactly 4
`AI_GATEWAY_DISABLED_REJECT_EVENT` and exactly 1 `AI_GATEWAY_CONTROL_READ_FAILED_EVENT` line exist,
each matching a specific rejected call one-to-one. No regression from round 1's behavior; the
wording ambiguity was in the report, not the implementation.

## Cleanup

Deleted the drill's own registered debug token (Step 5's separately-registered token is untouched).
Deleted both test Auth users (`g4-step8-killswitch-probe`, `g4-step8-remediation-probe`). Revoked
both temporary `roles/iam.serviceAccountTokenCreator` grants (on `firebase-adminsdk-fbsvc` for
token minting, and on `fn-ai-runtime` for the adversarial IAM proof — the latter left no standing
grant beyond the pre-existing `roles/iam.serviceAccountUser` this session did not add). Removed
local scratchpad credential files. Final `ai-gateway-kill-switch` state verified: `enabled:true,
reason:null`. The superseded Firestore `system/aiGateway` document was deleted.

## Round 2 GPT-PM review: 2 MINOR — both remediated

**MINOR (confirmed real)**: auth-ordering (round 1's fix) raised the attacker bar but did not
create the claimed ceiling — a valid, non-anonymous, App-Check-attested caller sending malformed
payloads (rejected by `parseInput`, which runs AFTER this check) or retrying past its exhausted
daily quota (checked AFTER this check too, by the DoD's own requirement) could still generate one
real Secret Manager access per attempt, unbounded. **Fix**: a short bounded cache
(`CONTROL_CACHE_TTL_MS = 5_000`) in `abuse_guard.ts` — caches the in-flight *promise*, not just the
resolved value, closing a stampede bug an initial draft had (a burst of concurrent calls all
checking the cache before the first one's fetch resolved, each seeing "empty" and each fetching;
caught by the new regression test itself failing `5` instead of `1` before the promise-caching fix).
Every call still logs its own structured event regardless of cache hit — proof point 5
(observability) is unaffected, only the network access is throttled. GPT-PM explicitly offered this
as an acceptable alternative to reordering validation further, and it closes the gap more
completely: reordering `parseInput` earlier would not have helped the "well-formed but
already-over-quota caller retries" case at all, since quota is deliberately checked after this
switch per the DoD.

**MINOR**: `log_signals.ts`'s doc comments for both events still described the superseded Firestore
mechanism (`system/aiGateway`, "control document"). **Fix**: rewrote both to describe the actual
Secret Manager control plane (`ai-gateway-kill-switch`, version state, JSON parse failure).

**Verification**: added 2 new tests in `abuse_guard.test.ts` — one asserting 5 concurrent calls cost
exactly 1 real `accessSecretVersion` call, one asserting a cached hit still produces one log line
per call. Full suite: 548/548 passing. `tsc --noEmit` clean, `npm run build` clean. Redeployed all 4
functions. Live smoke check on the real deployed mechanism (fresh test identity
`g4-step8-r2-smoke-probe`): normal call `200` → live disable via `gcloud secrets versions add` →
waited past the 5s cache TTL → call `503` → re-enable → waited past TTL → recovery call `200`.
Cleanup: deleted the smoke check's debug token and test Auth user, revoked the temporary IAM grant,
removed scratchpad files.

## Round 3 GPT-PM review: 1 MINOR — documentation-only, remediated

**MINOR (confirmed real)**: round 2's code fix was correct, but this document's main Design section
and the "What changed" test-count summary still described the pre-round-2 "fresh every call, no
cache, instant propagation" architecture rather than the current bounded-cache one, and the round-1
evidence table wasn't clearly marked as describing the earlier mechanism. **Fix**: rewrote the
Design section's `enforceAiGatewayEnabled` bullet, the "What changed" test totals, the durability
row, and the round-1 drill section's own heading to state the current cache-bounded semantics
explicitly and mark the round-1 drill as historical evidence of that round's mechanism, not the
current one. No code change, no redeploy, no further live testing — GPT-PM's own explicit scoping
for this round.

## Round 4 GPT-PM review: APPROVE — Step 8 CLOSED

All round 1-3 findings confirmed closed. No new findings. Verbatim: "MVP1.G4 Step 8 is CLOSED... the
resulting control now has the properties this gate needed: operator-controlled Secret Manager
switch → runtime can read but cannot re-enable → auth before control read → bounded/stampede-safe 5s
cache → switch before quota/Vertex → fail-closed unreadable state → per-call rejection observability
→ live disable/recovery without redeploy." `PUSH: AUTHORIZED under the current Gate policy.` Marked
`--final` via `--recover-request-id` (same scope/diff, nothing changed since the round-4 call).

## Status

CLOSED. Round 1: 1 MAJOR, 2 MINOR, remediated (Secret Manager control plane, IAM-scoped read-only
for the runtime identity, ordering fixed). Round 2: 2 MINOR, remediated (bounded cache closing the
residual unmetered-read gap, stale documentation corrected). Round 3: 1 MINOR, remediated
(documentation reconciliation). Round 4: APPROVE, final. All 8 DoD proof points plus the
adversarial IAM proof verified live. Proceeding to commit, push (per §20 — a genuine correlated
GPT-PM APPROVE authorizes push), and G4 Step 9.
