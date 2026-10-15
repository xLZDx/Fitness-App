# S01: fixes for GPT-PM review round 1 (MODIFY, two MAJOR) and the S00 sprint report

Date: 2026-10-16. Branch: `phase2/s01-contracts`. Reviewed head: `36f15d63`.

## What changed
- MAJOR-01 (stale baseline): the contract and the lifecycle matrix said there is no `storage.rules` and no `storage` block in `firebase.json`. Both exist since PR #5 (`storage.rules` is deny-all for the default bucket; Body Scan photos live in a separate private bucket reached only through signed URLs and the Admin SDK). Verified against `origin/phase2/main` (`89927444`). Contract section 2 rows, GPS-PRIV-064 (now: extend, never loosen, keep Body Scan bucket isolation), section 11 unknowns and matrix rows were corrected.
- MAJOR-02 (debug telemetry): GPS-PRIV-050 and GPS-PRIV-098 now require a server-side guarantee before any GPS code ships, either a sanitising callable with a closed schema and no direct client write, or per-event documents fully checked by rules, with negative tests for a modified client. The client schema test stays as an extra defence.
- Clarification: GPS-PRIV-086 names a server delivery endpoint for unlisted routes (a Firestore rule cannot check a URL token).
- Review disposition table for round 1 appended to the contract (section 13).
- Added `docs/phase2/s00/S00_SPRINT_REPORT_AND_RETRO.md` (closes S00 phase 10) and updated `docs/sdlc/STATE.md`; registry regenerated.

## Why
GPT-PM returned MODIFY on `36f15d63`; the remediation is one batch, followed by a verification round limited to these findings and their direct regressions.

## Affected contracts and paths
Documentation only: `docs/phase2/s01/`, `docs/phase2/s00/`, `docs/sdlc/STATE.md`, `docs/DOCUMENT_REGISTRY.md`, `core/DECISION_LOG.md`. No code, rules or configuration changed.

## Verification state
No tests or checks were run (documentation-only sprint). The two MAJOR claims were checked against `git show origin/phase2/main:storage.rules` and `firebase.json` before editing. GPT-PM verification round on the new head is pending.
