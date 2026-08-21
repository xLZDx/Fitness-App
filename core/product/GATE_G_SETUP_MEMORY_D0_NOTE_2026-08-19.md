# Gate G — physical-machine-instance memory, setup notes, context retrieval — evidence note

2026-08-19. Continues the Gate D/E/F pattern: reconnaissance before code, minimal safe seam, defer
what the evidence doesn't support yet.

## Scope actually claimed: MRD-03/04/05

The original roadmap tier deferred by Gate D's own scope note: not just "you did leg press" but
"you did leg press on THIS SPECIFIC machine, at THIS SPECIFIC gym, and here's your setup from last
time." Three roadmap items:
- MRD-03: physical machine instance identity
- MRD-04: machine setup/configuration memory (seat height, pin position, etc.)
- MRD-05: context retrieval (surfacing that memory at the right moment)

## Reconnaissance

A dedicated read-only agent traced five questions before any code was written (full report in the
session transcript; findings summarized here with file:line evidence):

1. **No physical-machine-instance concept exists anywhere, working or dead.** Every identifier in
   the scanning/equipment stack is TYPE-level: `RecognitionEntry.equipmentId` is explicitly "catalog
   id... doubles as the storage key" (`recognition_history.dart:44-46`), one row per TYPE with a
   5-minute sighting dedup that folds across gyms. `MachineCard.id` is a slug of the recognised
   *name string* (`machine_card.dart:177-183`), with its own doc comment stating the design intent
   directly: "Two people photographing the same thing in two gyms should raise the count on one
   card." `MachineCard.photoPath` is stripped before every Firestore write
   (`firestore_machine_cards.dart:170-176`) — even the one piece of per-scan evidence never reaches
   the server. A `RecognitionSource.qr` enum value and a `firestore.rules` comment about "the QR
   scanner" both reference barcode/QR scanning, but grepping the entire client and `pubspec.yaml`
   found zero scanning package, zero scanning code — a documented-but-never-built path, not working
   evidence of an instance concept.
2. **No setup/configuration memory exists, and nothing dormant to complete.** `SetCapture` is a
   two-field record (`weightKg, reps`, `set_capture.dart:8`). `WorkoutSession.notes` is the only
   free-text field on a session, and it's session-scoped, not per-exercise or per-equipment — it
   cannot hold "seat height for THIS leg press" distinctly from "pin position for THAT lat pulldown"
   within the same session. Unlike Gate F's `gymId`, there was no half-wired field anywhere to wire
   up.
3. **`gyms/{gymId}` is a single flat document with one known field**, `maintenanceWebhookUrl`
   (confirmed again from `functions/src/index.ts:1266-1268`, the only server code touching this
   collection). No `machines` subcollection or any other structure exists in `firestore.rules` for a
   physical-machine concept to attach to.
4. **The scan pipeline is stateless-per-scan by design at every stage.** Traced end-to-end through
   `gemini_equipment_service.dart`: photo in, ranked `VisualMatch` list out, resolved through
   `EquipmentAliasIndex` to a stable TYPE `equipmentId`, and only `ScanOutcome.confident` results
   persist — as a `RecognitionEntry` keyed by that type id, no photo, no location, no per-scan
   instance id. Nothing survives a scan except a type classification.
5. **`WorkoutSession`/`WorkoutSessionExercise`/`SetCapture` carry no dormant location/machine field**
   — checked field-by-field against `toJson`/`fromJson`; the complete field sets contain nothing of
   that shape. Unlike Gate F, there was no half-wired field here to complete.

## Decision: the composite (equipmentId, gymId) key is the minimal honest seam

The reconnaissance agent's own read was that MRD-03/04/05 looked like case (b) — inventing new
schema/business policy — rather than case (a), a half-wired-field seam like Gates D/E/F. That
conclusion was correct as far as it went, but it evaluated only two options: a genuine
single-physical-machine id (which nothing in this app can produce without new capture mechanisms:
barcode/QR scanning, or a location-tagged photo store — real feature invention with no evidence of
which mechanism users would want) versus doing nothing.

There is a third option the reconnaissance surfaced without naming it as such: **Gate F just shipped
a genuinely new, real field — `EquipmentAccess.gymId`** — that, composed with the equipment catalog's
existing TYPE id, is itself a workable approximation of "physical machine instance" for exactly the
scenario MRD-03 exists to serve: distinguishing "the leg press at Gold's Gym" from "the leg press at
Planet Fitness." `(equipmentId, gymId)` is not a claim of single-physical-unit precision — a gym with
two identical leg-press units would have one note that applies to "whichever leg press you use
here," the same honest type-level limitation Gate D already accepted for equipment memory generally,
now further scoped by location. That limitation is disclosed in the model's own doc comment and
reflected in the UI copy ("at {gym}", never "on this machine").

This is not a decision that required operator input: it needed no new backend schema (see the
security-rules finding below), no new business policy (no gym directory, no moderation, no identity
verification), and no new capture mechanism. It composes two fields that already exist in the
codebase after Gate F, exactly the kind of client-side composition this project's gates have used
throughout.

**Confirmed no rules change needed.** `firestore.rules`: `match /users/{uid}/{coll}/{document=**} {
allow read/write: if request.auth != null && request.auth.uid == uid && coll != 'subscription'; }`
already covers ANY new subcollection under a user's own document — the same wildcard rule that
already covers `machine_cards` and `recognised_equipment`. A new `equipment_setup_notes`
subcollection needed zero rules changes, eliminating the "new backend policy" concern that would
otherwise have been the strongest case for stopping and asking the operator.

## What shipped

- `mobile/lib/features/equipment/data/equipment_setup_note.dart` (new) — `EquipmentSetupNote`
  model: `equipmentId`, `gymId`, `note` (free text — no structured fields like a dedicated "seat
  height" number; no evidence of what fields users would actually want, so one open box beats
  guessing a schema nobody asked for), `updatedAt`. `equipmentSetupNoteId()` derives the doc id by
  reusing `machineCardId()`'s existing slug normalization for the `gymId` half, rather than
  duplicating that regex a second time.
- `mobile/lib/features/equipment/data/equipment_setup_note_repository.dart` (new) — abstract
  repository + `MockEquipmentSetupNoteRepository` (default binding, in-memory).
- `mobile/lib/features/equipment/data/firestore_equipment_setup_notes.dart` (new) —
  `FirestoreEquipmentSetupNoteRepository`, at `users/{uid}/equipment_setup_notes/{id}`, mirroring
  `firestore_machine_cards.dart`'s exact pattern (lazy singleton resolution, signed-out no-ops).
- `mobile/lib/features/equipment/state/equipment_setup_note_providers.dart` (new) — repository
  provider (mock default, Firestore override in `main.dart`) + `equipmentSetupNoteProvider`, a
  `FutureProvider.family` keyed on a `({String equipmentId, String gymId})` record.
- `mobile/lib/features/equipment/widgets/setup_note_card.dart` (new) — `SetupNoteCard`: hidden
  entirely when the profile has no `gymId` set (same restraint `LastSessionCard` uses for
  confirmed-no-history — an empty state with nothing to add earns no screen space); otherwise shows
  the loaded note in an editable field with an explicit Save button. MRD-05 (context retrieval) is
  just this card watching `equipmentSetupNoteProvider` with the page's own `equipmentId` and the
  profile's current `gymId` — no separate lookup UI needed.
- `mobile/lib/features/equipment/equipment_detail_page.dart` — `SetupNoteCard` added below
  `LastSessionCard`.
- `mobile/lib/main.dart` — `equipmentSetupNoteRepositoryProvider` overridden with
  `FirestoreEquipmentSetupNoteRepository`.
- `mobile/lib/l10n/app_en.arb`, `app_ru.arb` — `equipmentSetupNoteHeadline`,
  `equipmentSetupNoteAtGym` (placeholder), `equipmentSetupNoteHint`, `equipmentSetupNoteSave`,
  `equipmentSetupNoteSaved`.

## A real defect found and fixed during implementation (not by external review this time)

`SetupNoteCard`'s first draft seeded its local `_draft` field once, `??=`-style, mirroring
`InjuriesPage`'s established precedent for "load-once-then-own-locally" editable state. Writing the
"two different gyms show two different notes" test exposed the gap: `InjuriesPage`'s data source
never changes identity under the same `State` object (one draft per signed-in user), but
`SetupNoteCard`'s does — its `equipmentSetupNoteProvider` family key includes `gymId`, which comes
from the live profile and can change while the same widget instance stays mounted (the user
backgrounds the equipment page, edits their gym on the onboarding "edit your answers" screen, and
returns). A stale `_draft` in that scenario would not just display the wrong gym's note — hitting
Save would write the OLD gym's draft text under the NEW gym's key, corrupting data for a gym the
user never touched.

Fixed by tracking `_seededGymId` and reseeding `_draft` whenever the current `gymId` differs from
the one it was last seeded for, rather than only on first load. Verified with a dedicated regression
test that changes the profile's `gymId` via a live `StreamController` while the same `SetupNoteCard`
instance stays mounted (not a fresh `pumpWidget`, which Flutter/Riverpod can keep the same
`State`/`ProviderContainer` for anyway and would not have caught the bug) — reverting the fix to
plain `_draft ??= ...` made this test fail exactly as predicted; restoring it passed; `diff`-verified
the restore.

## Verification

- `mobile/test/features/equipment/data/equipment_setup_note_test.dart` (new) — 8 tests: id
  stability/uniqueness across the (equipmentId, gymId) pair, doc-id safety (no raw `/`), the same
  gym-name normalization `machineCardId` already applies, toJson/fromJson round-trip including an
  explicit empty note, equality/hashCode.
- `mobile/test/features/equipment/data/equipment_setup_note_repository_test.dart` (new) — 6 tests:
  get/save/overwrite/delete/isolation-across-gyms/empty-note-is-a-real-save, against the mock
  repository.
- `mobile/test/features/equipment/widgets/setup_note_card_test.dart` (new) — 8 tests: hidden with no
  gym / blank gym / no profile, shown once a gym is set, loads a previously saved note, save writes
  through and confirms via snackbar, isolation across two independently-opened pages for different
  gyms, and the same-instance reseed regression above.
- `flutter analyze` clean on all seven touched/added files.
- Mutation testing: the `_seededGymId` reseed fix (see above), reverted and confirmed the regression
  test fails with the predicted symptom (`Expected: 'seat 6' / Actual: not found`), restored,
  `diff`-verified identical.

## Review addendum

Independent review, two specialists in parallel (no cross-seeding): `flutter-reviewer` and
`type-design-analyzer`. Three real findings, all fixed and mutation-tested before commit.

**`flutter-reviewer` found one MAJOR that defeated MRD-05's own purpose.**
`equipmentSetupNoteProvider` is a plain (non-`autoDispose`) `FutureProvider.family`; `_save()` never
invalidated it after writing. Every other write-then-reread flow in this codebase already invalidates
its read provider after a mutation (`workout_log_providers.dart`, `progress_photos_providers.dart`)
— this was the one path that skipped it. Consequence: a note saved once, then the page closed and
reopened within the same app session, would show blank again — the exact "come back later and see
your reminder" flow this gate exists to deliver — and a second Save on that stale blank draft would
silently overwrite the real saved note with nothing. Fixed with `ref.invalidate(...)` on the specific
family key right after `save()` resolves. Reproduced with a dedicated test using a shared
`ProviderContainer` across two independently-keyed `SetupNoteCard` instances (a fresh `pumpWidget`
with a NEW `ProviderScope` would not have caught this, since Riverpod gives that a fresh container
too) — reverting the fix made the test fail with exactly the predicted symptom (note not found on
revisit); restoring it passed; `diff`-verified the restore. One MINOR (a cosmetic race where an
in-flight save's confirmation can land after a fast gym switch already changed what's on screen, with
no data corruption) noted and deliberately left as-is, matching the reviewer's own "not blocking"
read.

**`type-design-analyzer` found two MAJORs, both about the model's "never empty" `gymId` invariant
being a comment, not an enforced rule.** (1) `equipmentSetupNoteId` silently delegated an empty
`gymId` straight into `machineCardId`'s own empty-input fallback (`'machine'`), which would collide
every equipment type's "no real gym" case into one shared bucket — reachable specifically through
`fromJson`'s old `?? ''` default on a corrupted/hand-edited document, bypassing the model
constructor's invariant entirely. Fixed three ways: the constructor now `assert`s a non-blank
`gymId` (catches direct misuse in dev/test); `equipmentSetupNoteId` itself throws `ArgumentError` on
a blank `gymId` rather than silently falling through (the actual funnel point, since the
repository's `get`/`delete` reach it with a raw string, bypassing the model constructor entirely);
`fromJson` now returns `null` for a document with a missing/blank `gymId` or `equipmentId` instead
of constructing an invalid note — a corrupted document reads as "no note found," the same honest
degradation this codebase already uses elsewhere for corrupted data, rather than silently
constructing an object whose own documented invariant is already broken. (2) The reused
`machineCardId` slug function had no forward-reference noting this second, unrelated consumer — a
future edit to it for machine-card reasons could silently orphan previously-saved setup notes (a
changed slug means `get()` on the old id just returns null, no error). Fixed with a forward-reference
doc comment on `machineCardId` itself plus a pinning test (`equipment_setup_note_test.dart`) that
locks six representative inputs/outputs of that function, so a future drift fails this feature's own
suite instead of failing silently in production.

Full findings, evidence, and fix-by-fix mutation proof are captured in the review agents' own reports
(session transcript); summarized here per the project's finding-contract convention.

## Known gaps

- `FirestoreEquipmentSetupNoteRepository` has no direct test — same repo-wide gap as every other
  Firestore-backed repository in this codebase (no `fake_cloud_firestore`/mocking dependency,
  documented precedent). Its shape is a near-line-for-line mirror of the already-shipped
  `FirestoreMachineCardRepository`, sharing that repository's own untested-read/write-path
  boundary rather than introducing a new one.
- A gym with two or more identical machine units (two leg-press machines at one large gym) shares
  one note between them, by design — see "Decision" above. Disclosed in the model's doc comment and
  the UI's "at {gym}" copy; not a defect, a stated limitation of the composite-key approximation.
- `EquipmentSetupNote.note` is unstructured free text, not fielded (no dedicated seat-height /
  pin-position / incline inputs). No evidence exists of which structured fields users would actually
  want populated; a free-text box is the same deliberate under-commitment Gate F used for `gymId`
  itself, for the same reason.
