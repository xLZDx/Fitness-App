# Change record: environment preparation report for deploying V0 (2026-10-23)

Base: master 4a5e6b6d. Adds docs/v1/design/ENVIRONMENT_PREP_2026-10-23.md. Read-only investigation of the dev project (fitness-app-korostelev); nothing was deployed or changed; no secret values recorded.

## Findings
- The released Firestore ruleset (2026-08-29) lags master by about 700 lines and lacks the five V0 carve-outs, so an owner can currently write the five V0 collections through the wildcard. Releasing master's full rules file would also introduce validators on food, weight, body-scan, activity and profile writes and deny client creation of debug sessions; the minimal safe V0 deploy is the released rules plus only the five carve-outs.
- 43 functions are deployed; master exports 42 in the default codebase; only submitWorkoutCommands is not deployed. A targeted deploy touches only that function. The release guard is closed because origin/phase1/main is at 03ea66e1, 28 commits behind master. The function would run under the default Compute service account, which has no Firestore role: harmless with the flag off, a failure with the flag on.
- P1_SNAPSHOT_STALE for the equipment-identity codebase is a false alarm caused by CRLF line endings in the working copy (git blobs are identical); fix: run the three sync scripts or add one .gitattributes line.
- The two scheduler 403s come from the jobs running as the Compute service account while run.invoker is granted only to fn-canary and fn-enforcement; two fixes are described, none applied.
- A rollback drill proposal and a go/no-go list for the dev deploy are in the file.

## Affected contracts and paths
Documentation only.
