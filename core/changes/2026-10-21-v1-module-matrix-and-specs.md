# Change record: module matrix, local-queue decision, attendance amendment (2026-10-21)

## What changed
Three new documents under `docs/v1/`:
- `MODULE_DISPOSITION_MATRIX.md`: all 46 `mobile/lib/features` modules with a proposed disposition (KEEP / HIDE / KEEP login-only / DEFER), based on a read-only scan; method limits are stated in the file.
- `LOCAL_QUEUE_DECISION.md`: the operator decision to use a durable local queue for CompleteSet, AddEligibleExercise and SetDifficulty, replacing the package's online-only Option A, with fourteen acceptance criteria (after the documentation gate).
- `ATTENDANCE_SPEC_AMENDMENT.md`: first delivery of gym attendance is foreground only; background geofences are a later step gated on a Google Play policy assessment; seven measurable acceptance criteria proposed (after the documentation gate).

## Gate round 1 remediation (GPT-PM: 0 BLOCKER, 5 MAJOR, 2 MINOR)
- LOCAL_QUEUE_DECISION: criteria expanded from 8 to 14 (atomic durable acceptance, no silent eviction and fail-closed at capacity, stable IDs, one logical set one completion, per-session ordering, receipt capacity vs 256 proposal, UID isolation, sign-out outcomes with in-flight fencing, deletion ordering, offline export).
- ATTENDANCE_SPEC_AMENDMENT: added class definitions (automatic detection / confirmation suggestion / unknown), separate recall and precision for automatic detection, frozen thresholds and labeling rules before the pilot, negative foreground-only tests (background, lock screen, termination, GPS recorder service), named non-attendance journeys per permission state.
- MODULE_DISPOSITION_MATRIX: qualified unverified exclusivity claims and separated intended closure of cycling/hiking from demonstrated closure.

## Why
Operator answers of 2026-10-21 to the independent review of the FitnessUp v1 rebaseline package, which listed these as the open items before implementation.

## Affected contracts and paths
Documentation only. No source, test, build or rules file changes. The amendments are meant to be fed to the next independent review of the package together with the original package.

## Verification state
Documentation; nothing was executed. Facts about the code (unconditional removal of the background location permission, no attendance code, module imports) come from reads of master `dc124bbc` and the integration candidate. The Google Play policy statement is carried from the review and must be re-verified with a dated official source before any declaration is written.
