# AI Coach PM Bridge historical payload-hash audit

Date: 2026-10-18

## Change

Recorded a bounded, read-only search for the exact source bytes needed to safely retry the existing failed PM Bridge request.

## Evidence

- The original local PM Bridge call transcript provides request `26649707-679f-4962-8d26-e3b2a2ff36b2`, its logical text, and four attachment paths. The durable job stores only hash `ae7bf4ff2bc39b20a9680ce2012e8298e3b1facc7ff6b8e96acee31ae5e02ecb`, not the original payload bytes.
- PM Bridge `src/jobLedger.js` hashes operation, project, request ID, and payload. `reserveJob` reopens a failed job only when the same idempotency identity is supplied and its payload hash matches; changing payload under that identity is rejected.
- Read-only Git-history search covered all 57 commits touching the four attachment paths. They reduce to two unique attachment-content sets. The three distinct tracked execution-authority blocks and both LF/CRLF byte variants produced 12 hash candidates; none matched the stored hash.
- An earlier audit also checked the request's staged tree `6545ab3682e8079493f5f2a0e7b159c1d172f025`; its reconstructed candidates did not match.
- GitHub escalation [xLZDx/PM_Bridge#2](https://github.com/xLZDx/PM_Bridge/issues/2) remains the route for a maintainer-provided recovery procedure.

## Decision and limits

No retry, payload substitution, cancellation, lease release, or replacement GPT-PM request was made. The search covers tracked history and tracked authority-profile versions; it cannot recover a transient untracked working-copy version or attachment bytes absent from the local transcript and ledger. The original request remains unsent and unresolved.

## Affected paths and verification

- `core/changes/2026-10-18-ai-coach-pm-bridge-recovery-eligibility.md`
- `core/changes/2026-10-18-ai-coach-pm-bridge-hash-history-audit.md`

No tests, checks, builds, CI, migrations, runtime actions, push, or merge were performed.
