# AI Coach PM Bridge recovery eligibility review

Date: 2026-10-18

## Change

Added source-grounded recovery eligibility to `core/changes/2026-10-18-ai-coach-owner-resolution-followup.md` after re-reading the durable job and PM Bridge recovery implementation.

## Evidence

- Request `26649707-679f-4962-8d26-e3b2a2ff36b2` / job `37c54352-2436-4955-b217-65fdf141922c` remains `failed`, `sendPhase=not-started`, `generationLease=null`, `sendSnapshot=null`, `ATTACHMENT_NOT_LANDED`, with no `userTurnId` or `replyId`.
- `D:\Repo\pm-bridge\src\orchestrator.js` routes internal `/lease_release` to `forceReleaseLeaseTracked`.
- `D:\Repo\pm-bridge\src\jobLedger.js` `forceReleaseAmbiguousLease` permits release only for a held generation lease with `status=uncertain`, `sendPhase=sending`, no send snapshot, and supplied reason plus conversation-scoped evidence. The AI Coach job meets none of the state predicates needed for this escape hatch. Calling it would be rejected and would not resolve the failed lineage, so no request was made.
- `reserveJob` computes the signature over operation, project, request ID, and payload; the existing request may reopen only when its same idempotency identity and payload hash match. The status/cancel MCP tools do not expose persisted payload bytes or a recovery/release operation for this failed pre-send state.
- A separate read-only SQLite inspection (`mode=ro`) confirmed `jobs` stores `payload_hash`, send/status fields, and `send_snapshot_json`, but no payload bytes or attachment content field. The target row has `send_snapshot_json=null`; `job_events` contains lifecycle events, not the source payload. The stored hash cannot be used to reconstruct the payload.
- Health remains `OK`; queue depth and active jobs are zero. Restart is not a recovery path for this state and was not attempted.
- PM Bridge repository ownership-source search: GitHub returned 404 for root `CODEOWNERS`, `.github/CODEOWNERS`, `MAINTAINERS`, and `CONTRIBUTING.md`; issue search found no items for `ATTACHMENT_NOT_LANDED`, `acceptance.md` composer failure, or attachment recovery. Repository metadata identifies `xLZDx` as owner with `admin`/`maintain` permissions. That establishes a repository escalation route, not a formal PM Bridge service-maintainer assignment.

## Decision and remaining dependency

No retry, cancellation, lease release, payload change, or replacement request was made. The safe next action is to ask the PM Bridge repository owner account (`xLZDx`, admin/maintain permission) for the formal maintainer and a supported same-lineage recovery procedure; the available sources do not establish that account as the service maintainer. After the original payload hash is verifiably reproduced, retry only with the original request ID and idempotency key; otherwise do not send.

## Affected paths and verification

- `core/changes/2026-10-18-ai-coach-owner-resolution-followup.md`
- `core/changes/2026-10-18-ai-coach-pm-bridge-recovery-eligibility.md`
- `python scripts/dev/gen_document_registry.py` ran and reported 371 documents. The generated tracked registry remained unchanged and does not list this change record.

No tests, checks, builds, CI, migrations, runtime actions, alert changes, push, or merge were performed. This was a read-only source inspection plus documentation update.
