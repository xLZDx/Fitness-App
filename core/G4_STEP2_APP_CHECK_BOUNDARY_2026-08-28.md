# MVP1.G4 Step 2 — security/abuse boundary for the AI callables

Per GPT-PM's binding exit criteria for MVP1.G4 (recorded when `pm_set_gate(MVP1.G4,
pending)` was registered): the security/abuse boundary for the four AI callables,
`APP_CHECK_ENFORCED_AI` (`functions/src/scaling.ts:137-138`), including the
anonymous-account-rotation exposure.

## What already exists, verified against source

- **Quota mitigation applies to all 4 AI callables already.** `quotaFor()`
  (`functions/src/abuse_guard.ts:255-261`) divides an anonymous caller's quota by
  `ANONYMOUS_QUOTA_DIVISOR = 8`; each of `ai_coach_advice.ts`, `ai_equipment_recognition.ts`,
  `ai_exercise_generation.ts`, `ai_machine_description.ts` calls
  `quotaFor(QUOTAS.<name>, signInProvider(request))` before `enforceDailyQuota` (confirmed
  by direct grep, all 4 present).
- **Attestation is already measured, not just gate-able.** `noteAppCheck()`
  (`abuse_guard.ts:53`) is called by all 4 AI callables (confirmed by grep) and logs one
  structured line per call recording whether the request carried a valid App Check token
  — `scaling.ts:80-97`'s own comment: "the `attested: true` share in the `noteAppCheck`
  logs is the number" needed before deciding whether to enforce.
- **`APP_CHECK_ENFORCED_AI` defaults OFF**, same fail-safe-off pattern as every other flag
  in `scaling.ts` (`envFlag` returns false on anything but the literal string `"true"`).
- **Nothing is deployed yet.** `gcloud functions list --project=fitness-app-korostelev`
  (run live 2026-08-28): none of the 4 AI callables exist in the deployed function list.
  So there is currently zero real traffic and zero real attestation data for the AI
  surfaces specifically — the `noteAppCheck` logs for them are empty until deployment.

## The directly relevant precedent already in this repo: N-05 (video)

This repository already ran an extensive, two-round adversarial analysis of the
structurally identical question for `APP_CHECK_ENFORCED_VIDEO`/`APP_CHECK_ENFORCED`
(`core/DECISION_LOG.md`, "N-05 = OPERATOR / PLATFORM DECISION REQUIRED";
`core/review/N05_DISPOSITION.md`). Its conclusions, directly load-bearing here:

1. **App Check attests the app installation, not the account** — it does not close
   per-account abuse by itself; it raises the cost of running an attacker's OWN copy of
   the app, not the cost of creating throwaway Firebase accounts inside a real install.
   The 8x anonymous-quota divisor is what raises rotation cost for a real install; App
   Check is a different, complementary control (blocks non-genuine clients: scripts,
   tampered builds, emulators without attestation).
2. **"Enforcing before measuring locks out real installs."** App Distribution/internal
   test builds can fail attestation even when genuinely used by a real person, so
   flipping the flag with zero measured attestation data risks blocking real users, not
   just attackers.
3. N-05's own conclusion left the actual enforcement decision as "what is actually left
   for a person" — i.e., treated as an operator/product decision, not something to
   silently resolve in code.

## Why the AI callables are NOT a copy-paste of the video decision

The cost profile is materially different, and this document does not treat N-05's
video-flag disposition as automatically transferring:

- **Video's per-call cost is bandwidth** (a signed URL, then GCS egress). **AI's per-call
  cost is a real Vertex AI LLM invocation** — the thing MVP1.G4 exists to activate. A
  rotation-based attacker gets 8x more paid LLM calls per fresh anonymous account, not
  8x more bandwidth. The dollar exposure per rotation is categorically different, even
  though the mitigation mechanism (`quotaFor`/`ANONYMOUS_QUOTA_DIVISOR`) is identical
  code shared with video.
- **`AI_METERED`'s own ceiling is already the most conservative profile in `scaling.ts`**
  (`maxInstances: 15, concurrency: 10`, its own comment calling out "a runaway Vertex AI
  bill, not just a starved instance pool") — a real, independent backstop that does not
  exist for video in the same form (video's ceiling protects instance/IAM-signing
  capacity, not a per-call dollar cost).
- **No live traffic exists yet for AI**, unlike video (which has been in production and
  had real attestation data to reason about). There is no "currently unmeasured" gap to
  close before enforcing for AI — there is no measurement possible at all until
  something is deployed.

## Options, not a unilateral choice

**A. Deploy with `APP_CHECK_ENFORCED_AI` unset (off), same fail-safe default as every
other flag.** Ship the 4 callables behind the existing quota + `AI_METERED` ceiling,
start collecting real `noteAppCheck` attestation data from real traffic, then make the
enforce decision as a dedicated follow-up once real numbers exist — mirroring N-05's own
conclusion for video, adapted: measure before enforcing. Residual risk: an anonymous
account still gets a real LLM-cost exposure at 1/8 the authenticated ceiling per
rotation, mitigated but not eliminated by `AI_METERED`'s low instance/concurrency caps
and the existing per-uid daily quota.

**B. Deploy with `APP_CHECK_ENFORCED_AI=true` from day one**, accepting the real risk
N-05 already documented for video (App Distribution/internal test builds may fail
attestation and get locked out) applied now to a smaller, controlled initial AI rollout
where that risk is more tolerable (fewer real users at G4 launch than video's current
production traffic).

**C. Something narrower**: enforce for the two highest-cost/least-latency-sensitive
callables only (e.g. `aiExerciseGeneration`'s 1024-token JSON generation) while leaving
`aiCoachAdvice` open initially — `APP_CHECK_ENFORCED_AI` is currently one flag shared by
all 4; this would need per-callable flag granularity that does not exist yet in
`scaling.ts`, a real code change, not just a deployment config choice.

My own lean: **A**, for the same reason N-05 concluded "enforcing before measuring locks
out real installs" — but the AI cost-exposure argument above is a real difference from
the video precedent, not a rounding error, so this is not treated as pre-decided.
Surfacing to GPT-PM rather than picking silently, per this project's established pattern
for exactly this kind of trade-off (CLAUDE.md §16/§17).

Per GPT-PM's own earlier framing of what needs CEO/operator input versus what does not
("no CEO escalation is needed merely for four test-call costs... A CEO/business decision
becomes relevant when you intentionally activate AI for real users, choose the long-term
model/cost posture, or accept operation without a binding anti-rotation control"): this
question — whether G4 accepts operating the AI surfaces without a binding anti-rotation
control at initial launch — appears to be exactly the kind of decision that framing called
out as needing real business judgment, not a purely technical call. Asking GPT-PM to rule
on it directly, and to say explicitly whether this is within its own scope to decide or
needs operator escalation under CLAUDE.md §4.

## GPT-PM ruling (round 1): MAJOR — 2 findings, both corrected below

Full reply in `core/DECISION_LOG.md`. Two real defects in the framing above:

**MAJOR 1 — the "App Distribution cannot attest" claim is stale.** Options A/B/C above,
and the underlying `scaling.ts` comment they were built from, treated "Play Integrity
only attests Play-distributed builds" as an unconditional fact. It is not: Firebase's
current documentation explicitly supports Android apps distributed outside Google Play —
for an exclusively-outside-Play channel, the documented per-app configuration is
`PLAY_RECOGNIZED` not required, `LICENSED` not required, `Device Integrity` required (set
in the Firebase Console under App Check > Apps, not in this repository). Independently
verified via a live web search of Firebase's own docs before accepting this (CLAUDE.md
§3/§13) — confirmed accurate. **Required change, adopted: Option D.** Configure App
Check for the actual outside-Play beta channel and prove the real release APK/device path
against a temporary no-Vertex callable with `enforceAppCheck: true`. If it passes, initial
deployment of the 4 AI callables must use `APP_CHECK_ENFORCED_AI=true`, not Option A/B/C's
"defer enforcement" framing. If it fails, keep AI undeployed and repair the attestation
configuration first. `scaling.ts`'s comment corrected in place (see that file) rather than
carrying the stale claim forward.

**MAJOR 2 — App Check enforcement was conflated with a binding anonymous-account
anti-rotation control.** This document already said, correctly, that App Check and UID
quotas solve different problems (App Check blocks non-genuine CLIENTS; the 8x quota only
raises rotation cost) — but then framed the actual decision as whether G4 may "operate
without a binding anti-rotation control," implying App Check enforcement would BE that
control. It would not: Firebase enforcement only rejects missing/invalid App Check
tokens — a valid ATTESTED installation remains completely free to make unlimited
authenticated callable requests under freshly-rotated anonymous UIDs. **An attacker
rotating anonymous Firebase identities through a genuine, attested, real app install is
not stopped by App Check at all.** Required change, adopted: split into two
independently-closed controls, not one:

1. **Genuine-client boundary = App Check enforcement.** Once Option D's real-device proof
   passes, this is a clean technical decision — no CEO escalation needed. Deploy with
   `APP_CHECK_ENFORCED_AI=true` from initial launch.
2. **Anonymous paid-AI identity/cost policy = a separate product decision**, not solved by
   (1) at all. This is the one that needs the operator — see below.

## Decision

**HOLD on deploying the 4 AI callables** until Option D's attestation proof passes.
**GO on the Option-D technical proof and the documentation corrections** (this document,
`scaling.ts`) — both done/in progress, no further GPT-PM round needed for those two items
specifically per its own explicit authorization.

**One question routed to the operator, not GPT-PM, because GPT-PM itself named it as
outside its own scope:** *"At MVP launch, may anonymous users consume paid AI?"*
GPT-PM's own recommendation: **NO** for the initial beta — anonymous users may use every
non-AI SPTR feature, but the 4 AI callables should require a persistent, non-anonymous
account until real usage/cost data supports relaxing that rule. This sidesteps the
anonymous-rotation cost exposure entirely (a real account is not free to mint) rather than
mitigating it at 1/8 severity, and is a clean, reversible policy (a single check at the
top of each `ai_*.ts` callable, gated behind its own flag the same shape as
`APP_CHECK_ENFORCED_AI`) rather than a permanent architectural commitment.
