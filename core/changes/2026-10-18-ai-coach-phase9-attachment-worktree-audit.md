# AI Coach Phase 9: read-only audit of PM Bridge attachment worktree

Date: 2026-10-18. Kind: bounded read-only transport-path audit and status update.

## Evidence

The original PM Bridge request and the separate exact-tree GPT-PM request both failed before send with `ATTACHMENT_NOT_LANDED`, specifically because `acceptance.md` did not appear as a composer card. The daemon was healthy. The exact-tree GPT-PM request `15dddc0d-4e77-41ce-8fa7-e07b7e0041e5` (job `430d3d00-200e-43a4-9094-a5b0af9ed19b`) was retried once with the same request ID/payload; it failed before send again. The original user request `26649707-679f-4962-8d26-e3b2a2ff36b2` was not altered, retried, or replaced.

A bounded `git worktree list --porcelain` in `D:/Repo/pm-bridge` showed a dedicated sibling worktree:

- Path: `D:/Repo/pm-bridge-attach`
- HEAD: `1c4b5cd6fd539f0f0d2272fd09a1853f3969740e` (detached)
- Working tree: already dirty before this read-only inspection
- Modified/untracked paths include `src/attachments.js`, `src/orchestrator.js`, `src/server.js`, `src/transports/playwright.js`, `tests/test_attachments.mjs`, `package.json`, `core/DECISION_LOG.md` and supporting report/state files.

The target transport diff introduces attachment admission, byte/hash checks, upload-card proof and a new attachment test file. This overlaps the failing path. Its author/owner and whether it is actively being edited cannot be established from Git metadata; no file in that worktree was changed, staged, committed or tested. The main PM Bridge checkout also contains unrelated dirty paths and was not modified.

The existing [PM Bridge recovery issue #2](https://github.com/xLZDx/PM_Bridge/issues/2) received follow-up comment [6254363789](https://github.com/xLZDx/PM_Bridge/issues/2#issuecomment-6254363789), requesting the formal maintainer and supported recovery/attachment procedure. No maintainer reply is evidenced.

## Disposition and limits

- The attachment worktree may contain a relevant implementation, but it is uncommitted, detached, and overlaps another actor's work; it is not safe to stage, alter or adopt without identifying/coordining with its author and completing its authorized review workflow.
- The original failed job's exact payload hash remains unreproduced. No safe original-lineage recovery path is available through the exposed status/send tools; the internal ambiguous-lease release predicates do not apply to this pre-send job.
- Exact-tree GPT-PM disposition remains unavailable because both attempts were pre-send failures. No product decision, service owner, on-call recipient or clinical signer is inferred.
- No test, check, build, CI, migration, runtime or alert action was run. No push or merge occurred.

## Affected paths

- `docs/ai-coach/acceptance.md`
- `docs/ai-coach/00_README.md`
- `docs/sdlc/STATE.md`
- `docs/DOCUMENT_REGISTRY.md` (generated)
