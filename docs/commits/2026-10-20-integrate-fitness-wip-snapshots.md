# Integrate former-worktree WIP snapshots (aicoach, bodyscan, Phase2_s01)

Date: 2026-10-20. Documentation import plus one reference patch; no application code changed.

## Why
The former worktree folders Fitness_App_aicoach, Fitness_App_bodyscan and Fitness_App_Phase2_s01 held uncommitted work, saved as branches snapshot/Fitness_App_*-2026-10-20. The first integration pass missed it. Each changed file was compared with this branch.

## Per-file decisions
| Snapshot | File | Decision | Evidence |
|---|---|---|---|
| aicoach | core/changes/2026-10-20-ai-coach-phase9-gptpm-remediation-review.md | IMPORTED (new) | absent on integrate |
| aicoach | docs/ai-coach/24_PHASE9_AI_COACH_01_TRANSACTION_SCOPE.md | IMPORTED | integrate copy equals the snapshot parent b9622b62; snapshot edit applies cleanly |
| aicoach | reports/2026-10-20-ai-coach-phase9-status.html and .ru.html | IMPORTED (new) | absent on integrate |
| bodyscan | docs/sdlc/STATE.md | SKIPPED (older) | integrate holds a 131-line Phase 2 state; the snapshot is the 22-line Body Scan state of PR 5, since merged; still on the snapshot branch |
| bodyscan | mobile/test/_probe/probe_test.dart | SKIPPED (junk) | print-only exploratory probe, no assertions |
| Phase2_s01 | uid_scoped_activity_journal.dart, sign_out_guard.dart, location_consent_providers.dart, file_recording_journal.dart | NOT APPLIED; kept as reference patch | genuinely new relative to integrate (integrate equals the parent 5d5723fa) but applying them makes 210 existing tests fail (they expect the old behaviour; the WIP carries no test updates) |
| Phase2_s01 | geolocator_location_source.dart | SKIPPED (already fixed) | snapshot rewrites the same broken header block that integrate already repaired |

The five Phase2_s01 code changes are stored verbatim as docs/wip-snapshots/2026-10-20-phase2-s01-uncommitted-hardening.patch for a later sprint that also updates the tests.

## Known gap
Doc 24 (imported) points to docs 23 and 25 for nine review findings, but those two files on integrate do not contain them (the snapshot did not include their edits). The change record above holds the findings summary.

## Checks
- dart analyze (mobile lib test): 0 errors, 182 issues, same as before the import.
- flutter test test/features/recording test/features/activity test/android with the code import applied: 211 failures (210 new). Without it (HEAD): 1 failure, the known DT-0-10 journal_availability_test. The code import was therefore reverted before the commit.
- docs/DOCUMENT_REGISTRY.md regenerated with scripts/dev/gen_document_registry.py.
