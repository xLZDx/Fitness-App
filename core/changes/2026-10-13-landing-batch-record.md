# Change record: landing of the 2026-10-08 tail-closure batch (catch-up)

Written 2026-10-13 to satisfy the rule that every commit has its own change record. It covers eight commits that were made before that rule was re-read and that carried only decision-log entries.

| Commit | What | Why |
|---|---|---|
| 2a663cf, a6e8005 | Code/CI snapshot report (RU + EN), then a simpler restyle | Operator asked for a readable code and CI overview |
| 7662b1b | Review documents, tail-closure registry, evidence files, Phase 2 reference review | Record the 2026-10-07 review and the per-item status in `core/state/TAIL_CLOSURE_REGISTRY.json` |
| 0174337 | Tracked `mobile/pubspec.lock`, `--enforce-lockfile`, store build profile, integration script, CT-1 `fetch-depth 0` | The OSV job failed because the lockfile was never committed; CT-1 compared HEAD with itself in a depth-1 clone |
| e3b022d | `firebase-tools` pinned, `firebase-admin` 13.x, `@grpc/grpc-js` override | Rules and e2e CI jobs failed with "could not determine executable to run"; production audit now has 0 high/critical |
| c04ff6d | `isOrdinaryUser()` canary exclusion in rules, idempotent `bookCoachSession`, cleared probe timers | CR-05, CR-08, CR-09 in the registry |
| 18eb8ac | Account deletion reachable before onboarding, profile-stream race, fail-closed corrupt health blob, scanner invariant tests, regenerated goldens | CR-03, CAND-01, CR-07, CR-06, VER-03 |
| e66be1c | Fixes from the silent-failure and security reviews | Prefs write failures now throw, corrupt blob kept on empty save, wipe completes and reports leftovers, coach export without booking id |

Verification state at e66be1c: functions jest 619 pass, targeted Flutter suites 336 pass, Python ledger/CT-1/ML 405 and equipment identity 797 pass, RU/EN drift 0 new. Not verified: Linux-container rules and e2e on that head, full Flutter suite, any CI run. Nothing was pushed.
