# Gate D0 — Reconnaissance note: equipment-TYPE workout history

**Correction (mid-D0, before any code was written):** the sections below
originally reconnoitred `workoutLogsProvider` / `WorkoutLogRepository` /
`kWorkoutHistoryWindow`. While reading `workout_player_page.dart`'s own
`_SuggestedWeightChip` for how `progression.dart` is fed, its F3.4 comment
pointed at a newer, superseding path:
`workout_player_page.dart:1255`, `"sourced from workout_sessions, the only
collection new completions now write to"`. Confirmed in
`workout_session_providers.dart`: `workout_logs` stopped receiving writes at
F3.3/F3.4 (`core/plans/PLAN_F3_WORKOUT_SESSION_2026-08-06.md`); it is
"read-only historical data" now. `workoutSessionHistoryProvider` reshapes the
current `workout_sessions` collection into the exact same `WorkoutLogEntry`
view every other consumer (Progress, Home, suggestions, data export) already
reads, and `workoutSessionTotalsProvider` is its all-time-total counterpart —
same shape as `workoutTotalsProvider`, same windowing rationale
(`kWorkoutSessionHistoryWindow`, "same window rationale as
`kWorkoutHistoryWindow`" per its own doc comment). Everything below is
written against the CURRENT (`workout_sessions`) path; the design and the
whereIn-cardinality finding both hold unchanged, since
`summarizeEquipmentTypeHistory`'s signature (`List<WorkoutLogEntry>` +
`int allTimeTotal`) is agnostic to which repository produced them.

Scope: Level-1 memory only — `recognized equipment TYPE -> relevant prior workout
context` (e.g. "Your last leg press: 45 kg x 10"). No gym entity, no physical
machine instance, no Firestore migration, no MRD-03/04 design. Those stay
deferred to later gates per operator instruction.

## FACT — what already exists

- `WorkoutLogEntry` (`mobile/lib/features/workouts/data/workout_log.dart`) has
  no `equipmentId` field. The only path from a logged set to an equipment type
  is `exerciseId` -> catalog lookup -> `ExerciseItem.equipmentId`.
- `EquipmentRepository.exercisesFor(equipmentId)` already returns every
  `ExerciseItem` for a given equipment type
  (`mobile/lib/features/equipment/data/equipment_repository.dart:15`,
  implemented in `asset_equipment_repository.dart:203`). This is the existing,
  already-used mapping — Gate D does not need to invent one.
- `workoutSessionHistoryProvider` (`workout_session_providers.dart:54`) is the
  CURRENT (post-F3.3/F3.4) live history, reshaped from `workout_sessions` into
  `WorkoutLogEntry` rows, newest first, capped by `kWorkoutSessionHistoryWindow`
  (`workout_session_repository.dart`, "same window rationale as
  `kWorkoutHistoryWindow`"). Already watched app-wide (Progress tab, Home,
  streak calc, `workout_player_page.dart`'s suggested-weight chip). The older
  `workoutLogsProvider` / `kWorkoutHistoryWindow` / `workout_logs` path is
  legacy read-only data since F3.4 and is not the correct source for new work.
- `workoutSessionTotalsProvider` (`workout_session_providers.dart:39`) returns
  `WorkoutLogTotals.total`, an exact server-side `count()` aggregation over
  the *entire* history, independent of the window. This is precisely the
  number the codebase already uses to detect when the window is truncated —
  see `mobile/test/features/workouts/history_window_test.dart`, which proves
  the same pattern on the legacy pair (`workoutTotalsProvider` /
  `workoutLogsProvider`) that `workoutSessionTotalsProvider` /
  `workoutSessionHistoryProvider` now mirror. Gate D reuses this existing
  convention rather than inventing a new one.
- `EquipmentDetailPage` (`equipment_detail_page.dart:22`) is already keyed by
  `equipmentId` (a TYPE id, e.g. `leg_press`, not a physical-instance id) —
  it is already the correct, existing surface for a "your last session on this
  equipment type" card. No new navigation/route is needed.
- `suggestNextWeight()` (`progression.dart`) is a pure function over
  `List<WorkoutLogEntry> historyForExercise` — i.e. history already filtered
  to ONE exercise, by the caller. Gate D's equipment-TYPE summary is a
  sibling concept (filtered to *all exercises under one equipment type*, not
  one exercise) and should not be merged into `suggestNextWeight` itself; it
  reuses the same "caller pre-filters, function stays pure" shape.

## FACT — the cardinality constraint that rules out a server-side `whereIn` query

- `mobile/assets/data/exercises_vendor.json`: 65 distinct `equipmentId`s carry
  mapped exercises; the busiest, `bench_press`, maps to 254 exercises;
  `dumbbell` to 209; `barbell` to 165.
- Firestore's `whereIn` operator accepts at most ~30 values per query. A
  direct `.where('exerciseId', whereIn: [...all exerciseIds for this
  equipment type...])` query is therefore not constructible in one call for
  any of the higher-cardinality equipment types (would need up to 9 batched
  queries for `bench_press` alone), and there is no existing `equipmentId`
  field on the stored document to filter on directly instead.

## DECISION — minimal safe seam chosen for Gate D (no schema change, no migration)

Do the equipment-type match **client-side**, over data the app already holds,
instead of adding a new indexed field or a new Firestore query:

1. Reuse `workoutSessionHistoryProvider`'s existing windowed stream (0 new Firestore
   reads — this listener is already attached app-wide).
2. Reuse `EquipmentRepository.exercisesFor(equipmentId)` to get the set of
   `exerciseId`s that belong to the queried equipment type (0 new reads —
   bundled asset, already loaded for the equipment detail page itself).
3. Filter the windowed history to entries whose `exerciseId` is in that set;
   the most recent match (by `completedAt`) is the summary.
4. Because the window is "the newest N logs across every exercise, sorted
   newest-first", any match found inside it is *provably* the true most
   recent one — nothing newer exists outside the window by construction. The
   only case that needs an honesty check is **no match found**: that can mean
   either "never done" or "done, but older than the window covers." Reusing
   `workoutSessionTotalsProvider.total` (already fetched, already the codebase's
   established truncation signal) distinguishes the two: if the window is
   strictly shorter than the all-time total, a "not found" is reported as
   "not found in your recent history" rather than "no history" — satisfying
   the explicit D3 constraint against a false "no history" claim.

Rejected alternatives, with reasons:

- **Add a denormalized `equipmentId` field to `WorkoutLogEntry`, written at
  save-time, queried directly.** Technically correct and avoids the
  whereIn-cardinality problem, but it is a persistence-schema change (new
  field on every future write, a backfill question for the ~existing
  documents that predate it, and a write-path change across every `save()`
  call site). The operator instruction was explicit: *"не предполагай
  migration заранее"* / prefer the minimal safe seam. The client-side option
  above satisfies D3's correctness bar (no false negatives) with **zero**
  schema or write-path change, so it is strictly smaller and is what Gate D
  implements. A future gate can revisit denormalization if product needs
  (e.g. server-side aggregate stats) later justify the write-path cost — not
  assumed here.
- **Batch multiple `whereIn` queries (30 ids at a time) against Firestore.**
  Correct but adds up to 9 extra reads for a single equipment-type lookup on
  top of the window listener that's already paid for, contradicts the
  project's own stated preference ("a correct bounded query, not loading the
  client's full history") only in the sense that it *adds* cost the
  client-side option doesn't need to pay at all. Rejected as unnecessary.

## Scope boundary respected

No `gymId`, no `physicalMachineId`, no seat/pad/pin setup memory, no Firestore
document/collection changes, no migration. `EquipmentTypeHistorySummary` (Gate
D1) carries only: the queried `equipmentId`, the most recent matching
`WorkoutLogEntry` (or null), and a completeness flag. This is deliberately the
smallest type that can honestly answer "your last session on this equipment
type."

## D7 — independent review findings and fixes (2026-08-19)

Three specialists ran in parallel and independently (no cross-seeding):
`flutter-reviewer`, `type-design-analyzer`, `silent-failure-hunter`. All three
read the same files; two converged on the same root defect from different
angles, which is why it is listed once.

**BLOCKER/MAJOR (flutter-reviewer + type-design-analyzer, independently) —
the truncation check compared exercise-ROW count to SESSION count.**
`summarizeEquipmentTypeHistory`'s original completeness check was
`windowedHistory.length >= allTimeTotal`. `allTimeTotal` counts *sessions*
(`WorkoutLogTotals.total`, a `count()` over `workout_sessions` documents).
`windowedHistory` is built from `WorkoutSession.asLogEntries()`, which since
R11e emits **one row per exercise in a session**, not one row per session.
For any user whose sessions average more than one exercise (the documented
normal case), `windowedHistory.length` can equal or exceed `allTimeTotal`
while the window is still missing real sessions — silently flipping a
truncated miss into a false `completeHistory` / confirmed-no-history, which
is the exact defect D3 exists to prevent. The D0 design note's claim that
this "mirrors" the legacy `workoutLogsProvider` pattern held pre-R11e (one
session = one row) and was not re-checked against `asLogEntries()`'s
post-R11e expansion — that gap is what let the bug through the original
implementation and its own tests (every test fixture used one exercise per
session, so row count and session count were always numerically equal).
**Fix:** compare distinct `WorkoutLogEntry.sessionId` count in the window
against `allTimeTotal`, not raw row count — reusing the same session/row
distinction `WorkoutLogEntry.sessionId`'s own doc comment already documents
for `deriveProgress`/`deriveWeekTotals`. Two regression tests added
(`equipment_type_history_test.dart`): one multi-exercise-session window that
is truncated (must report `recentWindowOnly`) and one that is genuinely
complete (must report `completeHistory`) — both fail under the original code
and pass under the fix; confirmed by reverting the fix and re-running (caught).

**MINOR, applied (type-design-analyzer) — the type didn't enforce its own
stated invariant.** `EquipmentTypeHistorySummary`'s public constructor let a
caller construct `lastEntry != null` with `completeness: recentWindowOnly`,
a combination the design treats as impossible but nothing stopped. Not a
live bug (single call site, currently correct), but a latent trap. **Fix:**
private constructor, two named factories — `.found()` (fixes completeness
to `completeHistory` internally) and `.notFound(windowCoveredAllHistory:)` —
so the invalid combination is unrepresentable rather than merely
undocumented-against.

**HIGH (silent-failure-hunter) — `equipmentExerciseIdsProvider` only read
the vendored catalog; AI-generated-only equipment types could never match.**
11 of 48 registry machines have no vendored exercises and fall through
entirely to AI generation (`exercisesForEquipmentWithAiFallbackProvider`).
A workout logged against one of them is logged under a generated
`ai::$equipmentId::$i` id. `equipmentExerciseIdsProvider` (added this gate)
only read `_exercisesForEquipmentProvider` (vendored catalog only), which is
permanently empty for those 11 types — so a user who genuinely, repeatedly
trained on one of them would see the same silent "nothing to show" as a
user who never touched it, deterministically, every time, not as a
loading/error race. **Fix:** union in cached generated-exercise ids via
`GeneratedExerciseRepository.get()` when the vendored set is empty —
reading the **cache only**, never triggering fresh generation (that is
billed, and belongs to the page that shows the exercise list, which already
caches it there). Three regression tests added
(`equipment_exercise_ids_provider_test.dart`): cached generated ids are
included when the catalog is empty; a real catalog never falls through to
the cache (proven by seeding the cache with a wrong id that must not leak
in); nothing cached yet resolves to empty rather than throwing. Confirmed
by reverting the fix and re-running (caught).

**MAJOR, applied (flutter-reviewer) — the card could flash a false "not
found" before the session stream's first snapshot.** `LastSessionCard`
gated rendering on `workoutSessionTotalsProvider` alone; `workoutSessionHistoryProvider`
collapses "still loading" into an empty list
(`.valueOrNull ?? const []`), indistinguishable from "no sessions". If
`workoutSessionTotalsProvider` (an independent `FutureProvider`, no
ordering guarantee) resolved before the session stream's first event, the
card would read "0 in window, N total" as a truncated miss and render "Not
found in your recent workouts" — self-correcting on the next stream
emission, but a real false claim in the interim. **Fix:** also gate on
`ref.watch(workoutSessionsProvider).hasValue`. Regression test added
(a `StreamController` that never emits during the test) — fails under the
original code (renders the false text), passes under the fix; confirmed by
reverting and re-running (caught).

**MEDIUM, deliberately deferred, not fixed in this gate
(silent-failure-hunter).** `workoutSessionTotalsProvider` samples
`authUserProvider.valueOrNull`, returning `WorkoutLogTotals.zero` both when
signed out and while Firebase Auth is still restoring the session (a
resolved-null-vs-not-yet-known collapse the codebase already fixed
elsewhere, e.g. `screeningProfileProvider`'s doc comment, by watching
`.future` instead of `.valueOrNull`). In combination with a genuinely
errored/collapsed session stream, this could in principle still produce a
false "confirmed no history." Not fixed here because
`workoutSessionTotalsProvider` is shared, wide-blast-radius infrastructure
(Home, Progress, streak calc all depend on its current semantics) —
changing its fix pattern is exactly the kind of "smallest independently
verifiable change" boundary this gate should not cross to fix a
conditional, lower-probability race in one new caller. Flagged here rather
than silently dropped; a candidate item for a dedicated auth-race hardening
pass across all consumers of `authUserProvider.valueOrNull`, not just this
one.

**Verified clean, no issue found (flutter-reviewer):**
`equipmentExerciseIdsProvider`'s presence in `equipment_providers.dart`
despite the file's "only `recommendedExercisesProvider` should surface
exercises for a machine" comment — the new provider's own doc comment gives
the specific, correct reason for the exception (history-matching must not
apply injury screening retroactively) and returns only raw ids, never
`ExerciseItem`s; provider caching/disposal; `formatLastSessionMetric`'s
null-safety; l10n key/placeholder consistency in both locales; no crash-risk
path (`FutureProvider` throws convert to `AsyncError`, never rethrown into
the widget tree); `LastSessionCard`'s own `.valueOrNull` guards correctly
collapse loading/error into "render nothing" and do not read an error as a
manufactured zero.

All fixes re-verified: `flutter analyze` clean (no new issues in touched
files), full suite 2445/2445 passing (was 2439 before this gate's own 6 new
regression tests), and each of the three applied fixes independently proven
by reverting it and confirming its regression test fails, then restoring
and confirming it passes.
