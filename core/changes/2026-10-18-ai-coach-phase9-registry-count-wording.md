# AI Coach Phase 9: clarify registry count wording

Date: 2026-10-18. Documentation-only correction from local review.

## What changed and why

- Clarified that the generated registry count of 368 includes the new review artifact, while per-commit change records are intentionally excluded. This avoids implying that the change record contributes to the registry count.

## Affected paths

- `core/changes/2026-10-18-ai-coach-phase9-remote-owner-review.md`.
- The registry itself is unchanged; its header already documents that change records are excluded.

## Review and verification

- `doc-updater` read-only review of exact HEAD `14574230b6753c5b60d84961b94b3997cfdeb9e6` found one MINOR wording ambiguity at line 9 of the remote-owner review change record and no other findings. It confirmed the registry's exclusion rule, the new review artifact row/size, cross-document consistency, PM Bridge correlation and that the PM approval targets supplied parent HEAD `924df4518617d25c9fecfd7200aa59ee83a4be0c`, not the reviewed commit.
- Applied the narrow wording correction; manually inspected this corrected sentence against the registry header and generated row. No tests, checks, builds, CI, migrations, push or merge were run/performed.
