# AI Coach: record failed OQ-19/OQ-28 exact-head review transport

Date: 2026-10-18. Documentation-only record of an unsuccessful focused GPT-PM review attempt for commit `bbc6a30016ed3baacbf0265f288c1c53f8f10f3c`.

## What happened

Request `e86c91bb-59f8-4a93-8d75-405ea82e3943` targeted only the OQ-19 and OQ-28 documentation clarification and cross-document consistency. PM Bridge returned `ATTACHMENT_NOT_LANDED` with `sendPhase=not-started`; the durable job had no `userTurnId` or `replyId`. The attached documents were reported missing from the ChatGPT composer, so no message crossed the send boundary. A retry with the same request ID returned the same persisted failure. No GPT-PM verdict exists for this commit.

## Scope and impact

- No application code, product contract, operator decision, or review verdict changed.
- The OQ-19/OQ-28 clarification remains committed at the targeted source head; its review status is NOT_RUN.
- Earlier exact-head approvals do not extend to the targeted commit.
- The transport error and request correlation are also summarized in `docs/ai-coach/acceptance.md` and `docs/sdlc/STATE.md`.

## Verification

- Evidence: PM Bridge durable job status for request `e86c91bb-59f8-4a93-8d75-405ea82e3943`; `sendPhase=not-started`, `errorCode=ATTACHMENT_NOT_LANDED`, `userTurnId=null`, `replyId=null`.
- Product tests, checks, builds, migrations and runtime/device runs: NOT_RUN; this is a transport-evidence documentation update.
- Registry generation: `python scripts/dev/gen_document_registry.py` completed and wrote `docs/DOCUMENT_REGISTRY.md` with 362 documents.
- Push and merge: not performed.

## Remaining acceptance

The exact-head review requires a functioning PM Bridge attachment/send path. No owner for that transport service is established in the project records. The next step is to restore the transport and obtain a correlated review for the exact OQ-19/OQ-28 commit; this record is not approval.
