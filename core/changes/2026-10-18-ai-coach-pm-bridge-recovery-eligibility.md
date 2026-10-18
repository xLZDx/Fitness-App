# AI Coach PM Bridge recovery eligibility review

Date: 2026-10-18

## Change

Added source-grounded recovery eligibility to `core/changes/2026-10-18-ai-coach-owner-resolution-followup.md` after re-reading the durable job and PM Bridge recovery implementation.

## Evidence

- Request `26649707-679f-4962-8d26-e3b2a2ff36b2` / job `37c54352-2436-4955-b217-65fdf141922c` remains `failed`, `sendPhase=not-started`, `generationLease=null`, `sendSnapshot=null`, `ATTACHMENT_NOT_LANDED`, with no `userTurnId` or `replyId`.
- `D:\Repo\pm-bridge\src\orchestrator.js` routes internal `/lease_release` to `forceReleaseLeaseTracked`.
- `D:\Repo\pm-bridge\src\jobLedger.js` `forceReleaseAmbiguousLease` permits release only for a held generation lease with `status=uncertain`, `sendPhase=sending`, no send snapshot, and supplied reason plus conversation-scoped evidence. The AI Coach job meets none of the state predicates needed for this escape hatch. Calling it would be rejected and would not resolve the failed lineage, so no request was made.
- `reserveJob` computes the signature over operation, project, request ID, and payload; the existing request may reopen only when its same idempotency identity and payload hash match. The status/cancel MCP tools do not expose persisted payload bytes or a recovery/release operation for this failed pre-send state.
- Health remains `OK`; queue depth and active jobs are zero. Restart is not a recovery path for this state and was not attempted.

## Decision and remaining dependency

No retry, cancellation, lease release, payload change, or replacement request was made. The safe next action requires the PM Bridge maintainer to recover the original immutable payload or provide a supported same-lineage recovery procedure. The responsible maintainer is not identified in the available records. After the original payload hash is verifiably reproduced, retry only with the original request ID and idempotency key; otherwise do not send.

## Affected paths and verification

- `core/changes/2026-10-18-ai-coach-owner-resolution-followup.md`
- `core/changes/2026-10-18-ai-coach-pm-bridge-recovery-eligibility.md`
- `python scripts/dev/gen_document_registry.py` ran and reported 371 documents. The generated tracked registry remained unchanged and does not list this change record.

No tests, checks, builds, CI, migrations, runtime actions, alert changes, push, or merge were performed. This was a read-only source inspection plus documentation update.
