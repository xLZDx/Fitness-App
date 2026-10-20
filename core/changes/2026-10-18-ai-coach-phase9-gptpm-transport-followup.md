# AI Coach Phase 9: exact-tree GPT-PM review transport follow-up

Date: 2026-10-18. Kind: PM Bridge transport evidence and documentation update.

## Request and durable state

After the exact-tree architect review of commit `6915afb7cd78e96523ffa2737148c522ee07d393`, a separate GPT-PM request asked for per-proposal product dispositions and evidence-backed owner routing. The original request `26649707-679f-4962-8d26-e3b2a2ff36b2` was not retried or replaced.

- New exact-tree review request: `15dddc0d-4e77-41ce-8fa7-e07b7e0041e5`
- Durable job: `430d3d00-200e-43a4-9094-a5b0af9ed19b`
- Idempotency key: `15dddc0d-4e77-41ce-8fa7-e07b7e0041e5:send-and-await`
- Payload hash: `e6b3cc8dbe8d1fe32268079f1c0535785ccd19ed9ad88307afbc7eb535c3965f`
- Final status: `failed`, `sendPhase=not-started`, `ATTACHMENT_NOT_LANDED`; error: attached files did not land in composer, specifically `acceptance.md` missing.
- There is no `userTurnId`, `replyId`, send snapshot, or GPT-PM verdict. PM Bridge health was `OK` and the daemon was running with no active job.
- The same request ID and identical payload were safely retried once; it failed at the same pre-send boundary. The request was not changed and no new request ID was created for this exact-tree review.

## Maintainer escalation

The existing [PM Bridge issue #2](https://github.com/xLZDx/PM_Bridge/issues/2), which requests a supported recovery for the original failed pre-send job, received one follow-up comment ([comment 6254363789](https://github.com/xLZDx/PM_Bridge/issues/2#issuecomment-6254363789)). It records the separate post-remediation attachment failure and asks the formal maintainer for both a supported exact-tree attachment path and the original lineage recovery procedure. No maintainer reply is evidenced yet. `xLZDx` remains only the repository assignment/issue actor; this does not establish formal maintainer responsibility.

## Decisions and limits

- The original request `26649707-679f-4962-8d26-e3b2a2ff36b2` remains `failed` before send with its original stored payload hash, no send snapshot, no turn/reply and no reproduced payload. It was not resent, edited, replaced or duplicated.
- The operator-supplied artifact remains uncorrelated evidence for bounded product directions; it is not a GPT-PM reply to either durable request.
- The local architect review at exact head `6915afb7cd78e96523ffa2737148c522ee07d393` found no new BLOCKER/MAJOR/MINOR, but it does not substitute for GPT-PM disposition.
- No OQ contracts were closed, no clinical or product values were invented, no technical/service/on-call/clinical owner was assigned, and all 13 story dispositions remain `PENDING`.
- No tests, checks, builds, CI, migrations, runtime/alert actions, push or merge were performed.

## Affected paths

- `docs/ai-coach/acceptance.md`
- `docs/DOCUMENT_REGISTRY.md` (generated)
