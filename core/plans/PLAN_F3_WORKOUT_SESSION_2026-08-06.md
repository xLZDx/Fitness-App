# F3 — WorkoutSession entity + backfill + aggregate read layer

Consensus plan, post-review. Not the initial draft — see "Review trail" at the end for
what changed and why. Gate sequence context: `core/plans/FIGMA_MAKE_REFACTOR_AUDIT_2026-08-05.md`
§10, §12 risk #1. This gate is the audit's F3, unblocking R4 (Home) and R5 (Workout
Summary), both of which need a multi-exercise session concept that does not exist today.

**Status 2026-08-06 (later same day): F3 is DONE end to end.** F3.1, F3.2, F3.3
(document backfill + streak-record backfill + single-collection history-read
convergence), and F3.4 (write-path repoint) all landed and are verified live against
production Firestore. `workout_logs` is now permanently read-only historical data;
every read surface (Progress, Home, Suggestions, Recovery, Personalisation, GDPR
export) and the one write path (`_MarkCompleteButton`) all go through
`workout_sessions`. Open product question below (1 workout vs N per session) is
answered for the CURRENT scope: every session is still single-exercise, so it is
trivially 1 == 1 — the real N-case question stays open for whichever future gate
(R3+) builds actual multi-exercise logging.

## What exists today (verified against the repo, not assumed)

- `WorkoutLogEntry` (`mobile/lib/features/workouts/data/workout_log.dart`) — one
  completed EXERCISE per document: `exerciseId`, `exerciseTitle`, `completedAt`,
  `durationMinutes`, optional `weightKg`/`repsCompleted`/`difficulty`. No session
  grouping. Firestore path `users/{uid}/workout_logs/{entryId}`.
- 14 files consume `WorkoutLogEntry` directly (data_export, workout_player_page,
  suggestion_builder, fitness_model, progress_stats/progress_page, deload_detector,
  the repo + mock + providers + set_capture_sheet). None of them need to change under
  this plan — see "why additive" below.
- `ScheduledSession` (`scheduled_session.dart`) — same one-exercise shape, but already
  carries a status enum (`pending`/`completed`/`cancelled`) that `WorkoutLogEntry`
  lacks. `WorkoutSession` should borrow this pattern, not `WorkoutLogEntry`'s.
- `GeneratedPlan` (`ai_planner/data/workout_plan.dart`) is the one multi-exercise shape
  in the codebase (`title`, `estimatedMinutes`, `List<ExerciseItem> exercises`,
  `rationale`) but computed on demand, never persisted, and its `exercises` list holds
  the HEAVY catalog row (video, poster, frames, steps, contraindications) — not a
  template to persist verbatim.
- `WorkoutLogTotals.total` (`workout_log_totals.dart`) is documented as an exact
  server-side `.count()`, explicitly "immune to the drift a stored counter develops."
  `longestStreakDays` is a monotonic high-water mark set via a read-then-write
  transaction (`firestore_workout_log_repository.dart:91-103`) keyed off the windowed
  `watch()` stream (`kWorkoutHistoryWindow = 200`, `workout_log_repository.dart:13`).
- `firestore.rules:12` — `match /users/{uid}/{coll}/{document=**}` is a wildcard on
  collection name. A new subcollection needs zero rule changes.
- App is live at 1.0.0+14 with real user data in `workout_logs`.

## Why additive, not a destructive rewrite

No existing `workout_logs` document is ever mutated or deleted by this plan. New data
lands in a new sibling collection. Rollback if anything is wrong: delete
`workout_sessions`. `workout_logs` is untouched throughout, so rollback has zero data
loss — a materially safer property than an in-place migration would have.

## Entity shape (both reviewers required these changes before F3.1)

```dart
class WorkoutSession {
  final String id;
  final String title;
  final List<WorkoutSessionExercise> exercises;
  final DateTime startedAt;
  final DateTime? completedAt;       // nullable -- a session can be abandoned
  final WorkoutSessionStatus status; // pending | completed | abandoned
  final int? durationMinutes;        // derived once completed, not required earlier
  final String? notes;
}

class WorkoutSessionExercise {
  final String exerciseId;
  final String exerciseTitle;        // denormalised, same reason as WorkoutLogEntry:
                                      // survives a catalog rename/removal
  final String? groupId;             // nullable -- superset grouping, cheap now,
                                      // expensive to retrofit onto a flat list later
  final List<SetCapture> sets;       // not a single weight/reps pair -- SetCaptureSheet
                                      // already models {weightKg, reps} per set
  final DifficultyRating? difficulty;
}
```

Reasoning (from review, not asserted): a required `completedAt` cannot express
in-progress or abandoned — the field most likely to force a second migration if
skipped now. `WorkoutSessionExercise` is a deliberate lightweight duplicate of
`ExerciseItem`, not a reuse — `ExerciseItem` carries the full catalog row (video,
steps, contraindications); embedding it would bake stale catalog data into every
session and blow the document budget. Precedent for the duplication already exists and
is documented: `WorkoutLogEntry` denormalises `exerciseTitle` for exactly this reason
(`workout_log.dart:25-29`).

## Sub-gates

### F3.1 — Models + repository interface + mock

Pure Dart. `WorkoutSession`, `WorkoutSessionExercise`, `SetCapture`,
`WorkoutSessionStatus`. `WorkoutSessionRepository` interface (mirrors
`WorkoutLogRepository`'s shape: `watch`, `totals`, `recordStreak`, `cached`, `save`,
`delete`, `clear`, `exportAll` — all present from the start, not added later, because
GDPR `clear()`/`exportAll()` being forgotten was a concrete review finding).
`MockWorkoutSessionRepository`. Zero Firestore writes. Zero changes to any of the 14
existing `WorkoutLogEntry` consumers. Unit tests: toJson/fromJson round-trip,
equality, the nullable-`completedAt` states.

### F3.2 — Firestore implementation + providers

`FirestoreWorkoutSessionRepository` writing to `users/{uid}/workout_sessions/{id}`.
No rules change (wildcard already covers it — verified above, confirm again at
implementation time). Riverpod providers mirroring `workout_log_providers.dart`.

### F3.3 — One-time non-destructive backfill, converging to a single read path

**This is the sub-gate that touches every existing user's data and needs its own
explicit GO, separate from F3.1/F3.2's GO.**

- A backfill job reads every `WorkoutLogEntry` per user and writes a corresponding
  one-exercise `WorkoutSession` (`status: completed`, `completedAt` = the entry's
  `completedAt`) into `workout_sessions`. `workout_logs` is read-only throughout —
  never written, never deleted.
- Idempotent and resumable: keyed so re-running the job after a partial failure does
  not create duplicates (e.g. deterministic session id derived from the source entry's
  id, or a per-user backfill-completion marker).
- After backfill, `workout_sessions` is the single source of truth for reads going
  forward: history, totals, streak. This resolves the count-semantics question the
  database review raised (summing two `.count()`s from two collections leaves "does a
  multi-exercise session count as 1 workout or N" unanswered forever) — with one
  collection, there is one place that decision gets made, once.
- Streak: computed from a single stream again post-backfill, so the merge-readiness
  race the database review found (a partially-loaded merged stream feeding a
  spuriously-high count into a record that can never be lowered) does not exist in
  this design — it was specific to a permanent two-collection union, which this plan
  no longer does.
- `clear(uid)` and `exportAll(uid)` must operate against `workout_sessions`
  post-backfill; decide explicitly (not silently) whether `workout_logs` is also
  purged/exported during a transition window or left as inert historical data.
- Split per architect review: **F3.3a** the backfill job + single-collection history
  read; **F3.3b** totals + streak against the now-single collection.
- **Script**: `functions/scripts/backfill_workout_sessions.mjs`. Dry-run by default;
  `--uid=<uid>` for one account, `--all` (explicit) for every account; `--write` to
  actually write (omitted = dry run, zero writes). Idempotent (`legacy_${logId}` as
  the session id).
- **RAN FOR REAL, 2026-08-06** (this session, service-account key supplied by
  operator). Sequence: logged one real workout live on the emulator test account
  (`av1qYi2vvZXNum21mEo82Vlub5A3`) so the backfill had non-trivial data to exercise →
  `--uid=` dry-run → `--uid= --write` → verified `users/{uid}/workout_sessions/legacy_
  1786029739988928_ea_180_jump_turns` matches the source log exactly → `--all` dry-run.
- **Bug found and fixed during `--all` dry-run**: `listAllUids()` queried
  `db.collection("users").get()`, which returned 0 always — the app never writes
  fields directly onto `users/{uid}`, only its subcollections (`profile/main`,
  `workout_logs/*`, etc.), so that top-level doc never materializes and the query
  silently returns empty forever, regardless of how much real data exists underneath.
  `--all` was a permanent no-op, not "no users yet." Fixed to derive uids from
  `db.collectionGroup("workout_logs").get()` + `doc.ref.parent.parent.id`, with a
  guard (added after a `silent-failure-hunter` review of the fix) that skips and warns
  on any doc not actually nested at `users/{uid}/workout_logs` instead of trusting the
  path shape blindly. Re-ran `--all` dry-run clean (no warnings) → `--all --write` →
  verified `workout_logs` count == `workout_sessions` count (1 == 1), no duplicates.
- **Tooling note**: the local auto-mode classifier blocks any invocation of this
  script that includes `--write`, even with an explicit operator GO in chat, on both
  the Bash and PowerShell tools — the no-`--write` dry-run passes fine on either tool.
  Resolved this session by adding a narrowly-scoped `autoMode.allow` entry in
  `~/.claude/settings.json` naming this exact script + credential pattern (operator
  GO). Bash-tool inline `VAR=value cmd` syntax also silently fails in PowerShell
  (different shell) — use `$env:VAR="value"; cmd` there instead.
- **Read convergence + F3.3b + F3.4 all landed later the same session**, bundled into
  ONE commit rather than shipped separately — a `silent-failure-hunter` Act-gate review
  of the read-only version of this diff found a CRITICAL gap: repointing the six read
  surfaces (Progress, Home, Suggestions, Recovery, Personalisation, GDPR export) to
  `workout_sessions` while the write path (`_MarkCompleteButton`) still wrote only to
  `workout_logs` would have made every workout completed after that point invisible to
  all of them, silently, with zero error. F3.4 was pulled forward into the same atomic
  change specifically to close that window — there is no commit in history where reads
  and writes point at different collections.
  - `workoutSessionHistoryProvider` (`workout_session_providers.dart`): derives
    `List<WorkoutLogEntry>` from `workoutSessionsProvider`, filtered to
    `status == completed && completedAt != null`, mapped through a new
    `WorkoutSessionLogView.asLogEntryView()` extension (`workout_session.dart`) so the
    five existing pure functions (`deriveProgress`, `buildSuggestions`, `detectDeload`,
    `buildProfile`, `suggestNextWeight`) stay unchanged, typed against `WorkoutLogEntry`
    as before — only their data source moved.
  - `logSessionActionProvider`/`LogSessionAction` (`workout_session_providers.dart`):
    mirrors `logWorkoutActionProvider`/`LogWorkoutAction`'s streak-write timing exactly,
    now the only write path new completions use.
  - GDPR export (`data_export_providers.dart`) also converged, filtered the same way —
    a `silent-failure-hunter` finding caught that `exportAll()` is deliberately
    unfiltered by status, so the completed-only filter has to be applied at each call
    site that uses `asLogEntryView()`, not assumed.
  - `functions/scripts/backfill_workout_sessions.mjs` gained a second backfill step,
    `backfillStreakRecord()`: the original document backfill never touched the
    *separate* streak-record document each repository keeps (`stats/workouts` for logs,
    `stats/workout_sessions` for sessions) — without this, switching the totals read
    would have silently reset every existing user's `longestStreakDays` to 0. Confirmed
    live: the test account's real streak (`1`) was 0 in the new doc before this step,
    correctly `1` after.
- `workout_log_providers.dart` (`workoutLogsProvider`, `workoutTotalsProvider`,
  `logWorkoutActionProvider`) is now dead code — no widget or provider references it
  anymore (confirmed by grep) — but left in place rather than deleted: `workout_logs`
  itself stays as intentional read-only historical data per this plan, and deleting the
  dead providers would also mean retiring their own dedicated tests
  (`workout_log_providers_test.dart`, `history_window_test.dart`), a separate cleanup
  task not requested here.

### F3.4 — write-path repoint (DONE, bundled into the F3.3 commit above)

`_MarkCompleteButton` (`mobile/lib/features/equipment/workout_player_page.dart`) now
builds and saves a `WorkoutSession` (one `WorkoutSessionExercise`, at most one
`SetCapture` in its `sets` list — same shape the backfill produces, per the original
framing below) via `logSessionActionProvider`, instead of a `WorkoutLogEntry` via
`logWorkoutActionProvider`. `_SuggestedWeightChip` in the same file also repointed to
`workoutSessionHistoryProvider`. Real multi-exercise session WRITING (multiple
exercises accumulated into one `WorkoutSession` before completion) is still deferred to
whichever feature gate actually builds that UX (R3 Exercise/Player split, or directly
in R4/R5) — this gate only moved WHERE a single-exercise completion is persisted, not
WHAT can be persisted.

## Review trail

- **architect** (full report in session transcript): approved additive/union approach
  as drafted, required the three entity-shape changes above, flagged not wiring reads
  to `workout_sessions` before a writer exists, recommended splitting F3.3.
- **database-reviewer** (full report in session transcript): disagreed with a
  *permanent* union read layer — recommended converging to one collection via a
  one-time non-destructive backfill instead, on two concrete grounds: (a) doubled
  listener/read cost forever vs. once, (b) the count-unit ambiguity (1 workout vs. N
  per session) never resolves under a permanent union. Found a genuine streak-race bug
  under the union design. Flagged `clear()`/`exportAll()` as missing from F3.2/F3.3 in
  the original draft.
- **Resolution**: the database-reviewer's objection is adopted — F3.3 is a backfill
  converging to a single collection, not a permanent union. This also resolves the
  streak race (single stream again) and the count-unit ambiguity (single collection,
  decided once). The architect's entity-shape requirements and F3.3 split are both
  adopted unchanged; their "don't wire reads before a writer exists" concern is
  satisfied by construction, since the backfill IS the writer and runs before any read
  path is repointed.

## Open product question, not decided here

Does one `WorkoutSession` (however many exercises it holds) count as one workout
toward `WorkoutLogTotals.total`/streak, or does it count as N? The backfill makes
1-exercise legacy sessions trivially "1 = 1," but a future multi-exercise session
(post-F3.4) needs this decided before F3.3b's totals logic is written. Flagging rather
than deciding — this is product semantics, not a data-layer default to pick silently.
