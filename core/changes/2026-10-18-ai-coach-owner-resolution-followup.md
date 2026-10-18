# AI Coach Phase 9 owner resolution and PM Bridge recovery follow-up

Date: 2026-10-18. Documentation-only record of the operator-authorized follow-up. No product implementation or runtime configuration changed.

## Scope and role boundary

The operator authorized Codex to pursue recovery of the existing GPT-PM request without changing its payload or creating a duplicate; canonical ownership-source checks for OQ technical ownership and ACS-100; real on-call routing; and qualified-human sign-off before clinical limits are used. GPT-PM remains the assigned product decision owner/signatory. Codex remains executor, not an appointed service owner or clinician. The operator remains accountable for the delegated task.

## PM Bridge evidence

- Health: `OK`; daemon current and running, queue depth 0, active jobs 0.
- Original request: `26649707-679f-4962-8d26-e3b2a2ff36b2`; idempotency key `26649707-679f-4962-8d26-e3b2a2ff36b2:send-and-await`; job `37c54352-2436-4955-b217-65fdf141922c`; project `fitness_app_aicoach`.
- Durable status after read and cancellation by the original idempotency key: `failed`, `sendPhase=not-started`, `ATTACHMENT_NOT_LANDED`, `cancelRequested=false`, `sendingLineageActive=true`; no `userTurnId`, `replyId`, generation lease, or send snapshot. The original composer error says `acceptance.md` was missing and nothing was sent.
- Durable events: `reserved`, `claimed`, then `failed` with `ATTACHMENT_NOT_LANDED`; event details contain no payload or attachment bytes.
- Retry rule in PM Bridge `src/jobLedger.js`: a terminal failed/pre-send job can reopen atomically on the same idempotency/request identity only if the supplied payload hash matches. A changed payload is refused. Cancellation did not release this failed lineage.
- The exact text and attachment paths were recovered from the local Codex session transcript. Stored `payloadHash`: `ae7bf4ff2bc39b20a9680ce2012e8298e3b1facc7ff6b8e96acee31ae5e02ecb`. A local reconstruction using that text, attachment bytes from staged tree `6545ab3682e8079493f5f2a0e7b159c1d172f025`, and the current execution-authority profile yielded `2ceec4ade726b54396ddfdfcb12c4d2e74b878bd3ada488d2e7404d28b7c93d8`, not the stored hash. This candidate is not claimed to reproduce the historical request. No retry was attempted.
- Safe-only restart was not invoked: health shows an active healthy daemon with no queued or running work, not the proven wedged-daemon condition required by that path.

## Canonical ownership-source evidence

- GitHub repo metadata: `xLZDx/Fitness-App`, default branch `master`.
- GitHub `fetch_file` returned 404 for root `CODEOWNERS` and `.github/CODEOWNERS`.
- GitHub issue search returned no matches for `ACS-100`, `OQ-07`, or `AI Coach on-call`.
- The project already records a broader audit of five conventional ownership paths over 16 returned branches, plus local decision/review sources, in `docs/ai-coach/18_PHASE9_REMOTE_OWNER_SOURCE_CHECK.md`; no technical/service or on-call owner was identified there either.
- Read-only Google Drive searches for `Fitness_App_aicoach OQ-07`, `Fitness_App_aicoach ACS-100`, `OQ-14 AI Coach`, and `on-call ACS-100` returned no files. Broader metadata-only document searches for `ACS 100 alert`, `OQ contract ownership`, `clinical safety signer`, and `AI Coach` returned generic or unrelated material; no canonical OQ ownership register, ACS-100 runtime service/on-call record, or qualified clinical signer was identified. These searches cover only the connected account's accessible Drive results and are not proof of global absence.
- These bounded searches do not prove global absence. They provide no evidence supporting assignment of a person or service.

## Disposition and next actions

1. The OQ-07 product gate and detailed OQ-07/OQ-14/OQ-18 proposal dispositions remain `NOT_RECORDED`; GPT-PM's earlier ACCEPT applies only to bounded OQ-14/OQ-18 product direction. Resolve the existing PM Bridge payload-hash/lineage issue through its maintainer, then replay only the same ID with the verified identical payload.
2. The canonical TR technical owner and AI Coach runtime service/on-call recipient remain unidentified. Record assignments only after their responsible service is confirmed in a canonical project/operations source.
3. No qualified clinical/safety signer is identified. Keep clinical limits and symptom scope unavailable until that person signs the actual values and scope.
4. ACS-100 remains `CARRIED`; no alert was configured or delivered. No clinical limits were applied.

No tests, checks, builds, CI, migrations, runtime alert actions, push, or merge were run or performed.
