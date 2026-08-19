# Gate F — gym identity (MRD-02 slice) — evidence note

2026-08-19. Continues the Gate D/E pattern: reconnaissance before code, minimal safe
seam, defer what the evidence doesn't support yet.

## Scope actually claimed

MRD-01 (workout-equipment relationship, type level) is already covered by Gate D's
`EquipmentTypeHistorySummary` — nothing new to add there. This gate is the MRD-02
half of the original Gate F spec: **"gymId exists in two models, always 'unknown',
never assigned."**

## Reconnaissance

`gymId` as a bare string, before this gate, had exactly two appearances in the
client:

1. `mobile/lib/features/buddy/data/buddy_match.dart` — `BuddyProfile.gymId` and
   `rankBuddies()`. Confirmed dead code: `buddy_match.dart` is the only file under
   `features/buddy/`, nothing else in the app constructs a `BuddyProfile`, and no
   route or provider reaches this file. Excluded from this gate — wiring a field
   nothing reads would not fix "always unknown," it would just add a second unread
   field.
2. `mobile/lib/features/equipment/widgets/equipment_report_sheet.dart` —
   `EquipmentReportSheet.show({..., String gymId = 'unknown'})`. This is real,
   live, and reachable: `equipment_detail_page.dart`'s "report broken equipment"
   button calls it. Before this gate, **no caller ever passed `gymId`**, so every
   report ever filed through this sheet carried the literal string `'unknown'`,
   regardless of which gym the user actually trains at.

Where `gymId` goes downstream, server-side (read-only from the client, confirmed
in `firestore.rules` lines 33-36: `match /gyms/{gymId} { allow read: if
request.auth != null; allow write: if false; }`):

- `functions/src/index.ts`'s `reportEquipment` callable (TX.7, ~lines 1020-1103)
  looks up `gyms/{gymId}.maintenanceWebhookUrl` and, if present, posts the report
  to that gym's Slack webhook. With `gymId` always `'unknown'`, this lookup could
  never resolve to a real gym's webhook — the whole maintenance-notification path
  was dead on arrival for every user who trains at a gym.

This is the load-bearing fact for the gate's scope decision: **`gyms/{gymId}` is
already a business/operator-provisioned namespace with its own security policy.**
I do not need to invent gym-identity product policy (uniqueness, moderation,
geo-verification) — that would be MRD-02's fuller scope and is exactly the kind of
"invent new business policy" territory the standing instruction's stop-condition
#2 warns about. What's missing is much narrower: **the user has no way to tell the
app which gym they're at**, so the one real consumer of `gymId` never receives a
real value.

## Decision: minimal safe seam

Add `gymId` as a free-text field on `EquipmentAccess` (the profile's equipment
section), collected once during onboarding, and thread it into the one real call
site.

**Free text, not a validated picker against `gyms/{gymId}`.** A searchable
gym-directory UI would need to match user input against the real `gyms/{gymId}`
document ID / slug convention, and I have no evidence of what that convention is —
no seed script, no admin tooling, no sample document visible from the client side
(writes are `allow write: if false`, and there is no read-listing UI anywhere in
the app to sample document IDs from). Building a picker against a guessed slug
format risks silently sending reports to a `gymId` that matches nothing, which is
no better than today's `'unknown'` and harder to notice. A free-text answer
degrades honestly: the Cloud Function's webhook lookup either matches a real gym
document or, same as today, matches nothing and the report still gets recorded
without a webhook ping. Building the real directory/picker is deferred to when
MRD-02's fuller scope is taken up with operator input on the actual gym-record
format.

**Collected in onboarding, conditionally.** `StepEquipment` already asks
`TrainingLocation` (gym / home / outdoor / mixed) and derives `hasGymAccess` from
it. The gym-name field is shown under the exact same condition
(`location == gym || location == mixed`) — never shown to someone training purely
at home or outdoors, so it can't collect an answer that has nothing to attach to.
This screen is also the "edit your answers" screen for returning users
(`profile_page.dart`'s `profileEditYourAnswers` routes to `/onboarding`), so
existing users can go back and fill this in, not just new signups.

**Wired only into the live consumer.** `equipment_detail_page.dart`'s report
button now reads `ref.read(currentProfileProvider).valueOrNull?.equipment.gymId`
and passes it through, falling back to the pre-existing `'unknown'` literal only
when the user has no location set or left the field blank — so the fallback
behavior for users who haven't answered is unchanged, and only users who *have*
answered get the fix. `buddy_match.dart` is left untouched; wiring dead code was
out of scope.

## What changed

- `mobile/lib/features/profile/data/profile_models.dart` — `EquipmentAccess`
  gained `final String? gymId`, threaded through `copyWith`.
  `UserProfile.toJson()`'s equipment map gained `'gymId': equipment.gymId`.
- `mobile/lib/features/profile/data/firestore_profile_repository.dart` —
  `_fromMap`'s equipment construction reads `gymId: equipment['gymId'] as
  String?`.
- `mobile/lib/features/onboarding/steps/step_equipment.dart` — conditional
  `GlassTextField` (key `onb.gymId`) shown for gym/mixed location, writing
  `notifier.updateEquipment((s) => s.copyWith(gymId: v.trim()))`.
- `mobile/lib/features/equipment/equipment_detail_page.dart` — report button
  reads the profile's `gymId` and passes it to `EquipmentReportSheet.show`,
  falling back to `'unknown'` only when unset/blank.
- `mobile/lib/l10n/app_en.arb`, `app_ru.arb` — `onbGymName`, `onbGymNameHint`.

## Verification

- `mobile/test/features/onboarding/equipment_access_test.dart` — extended with a
  `gymId` group (unset-by-default, `copyWith` preserves other fields, `copyWith`
  clears to `''` distinct from unset) and two serialization cases (untouched
  profile still writes `gymId: null`; `gymId` round-trips through `toJson`). 9 new
  assertions, all passing.
- `mobile/test/features/onboarding/step_equipment_test.dart` (new) — 6 widget
  tests: field absent by default, shown for gym, shown for mixed, hidden again
  after switching to home/outdoor (regression against a "sticky" bug), typing
  writes through to the draft, and an explicit null-vs-empty-string regression
  check.
- `flutter analyze` — clean on all six touched/added files (0 issues).
- Mutation testing (temporarily broken, confirmed red, restored + `diff`-verified
  identical to the backup):
  - `step_equipment.dart`'s gating condition, mutated from `gym || mixed` to
    `gym` only — `step_equipment_test.dart`'s "mixed reveals the field" test and
    3 others correctly went red.
  - `profile_models.dart`'s `copyWith` gymId assignment, mutated from `gymId ??
    this.gymId` to a variant that treats an explicit empty string as "no
    change" — `equipment_access_test.dart`'s clear-to-empty-string test
    correctly went red with a clear diff (`Expected: '' / Actual: 'Old Gym'`).

## Review addendum

Independent review, two specialists in parallel (no cross-seeding): `flutter-reviewer` and
`type-design-analyzer`.

**`flutter-reviewer` found one real MAJOR, fixed and mutation-tested.** `step_equipment.dart`'s
`onChanged` originally trimmed on every keystroke (`s.copyWith(gymId: v.trim())`). `GlassTextField`
is a controlled widget (own doc comment, `mobile/lib/features/onboarding/widgets/inputs.dart:354-367`)
that force-resyncs its `TextEditingController` whenever the incoming `value` disagrees with what's
displayed — a guard meant for *external* draft changes. Trimming inside this field's own `onChanged`
created a self-inflicted mismatch after every word: state briefly held the space-stripped string,
the resulting rebuild landed before the next keystroke, and `didUpdateWidget` forcibly overwrote the
controller to the trimmed text, deleting the space the user had just typed. Typing "Iron Temple Gym"
continuously produced "IronTempleGym" — this would have made most real (multi-word) gym names
unenterable. Reproduced with a widget test that appends each character to whatever the field is
*actually* displaying (reading the live `EditableText` controller, not an assumed target substring)
— an earlier version of the test that fed pre-computed prefixes via `enterText` did **not** catch
this, because it bypassed the resync race entirely. Fixed by dropping the per-keystroke `.trim()`
and trimming only at the one consumption boundary that needs a normalized value
(`equipment_detail_page.dart`'s report call site, which now also trims before the
null/empty-vs-real check per the reviewer's paired MINOR finding). Verified: reintroducing the old
trim-on-every-keystroke line makes the new regression test fail with exactly the predicted corrupted
string (`Expected: 'Iron Temple Gym' / Actual: 'IronTempleGym'`); restoring the fix makes it pass;
`diff` confirmed the restored file is byte-identical to the fixed version.

The reviewer also noted `step_equipment.dart`'s pre-existing `homeEquipment` field
(`_splitTags(v)` fed back as `value`) shares the same risky shape, predating this gate. Not fixed
here — out of scope for a gymId gate, and a distinct enough failure mode (comma-separated tags,
where users pause at the comma far more often than mid-word) that it did not block this change. Left
as a known, pre-existing pattern worth a follow-up if it turns out to bite users in practice.

**`type-design-analyzer` found no BLOCKER/MAJOR.** Confirmed the `String?` choice, the three-state
null/empty/real-answer distinction, and the consumption-site fallback are all correctly designed and
consistent with this file's existing conventions. One MINOR, left as documentation-only: `gymId` on
`EquipmentAccess` (free text, no invariant) and the unrelated, dead-code `BuddyProfile.gymId` in
`buddy_match.dart` (required, used as an exact-match key) share a bare name with no cross-reference.
Currently harmless since `BuddyProfile` is unreachable, but flagged as a future footgun: if buddy
matching is ever revived, wiring it straight from `EquipmentAccess.gymId` would silently fail to
match users who typed the same gym differently ("Gold's Gym" vs. "golds gym"). No code change made —
the fix (a cross-referencing doc comment, or a rename) belongs with whichever gate actually revives
`BuddyProfile`, not this one.

## Known gap

`firestore_profile_repository.dart`'s `_fromMap` read-side line (`gymId:
equipment['gymId'] as String?`) has no direct test. This repo has no
`fake_cloud_firestore`/`firebase_auth_mocks`/mocking dependency — documented
precedent in `test/features/visual_equipment/firestore_recognition_history_test.dart`
that adding one is out of scope for incidental coverage. The line is a one-token
cast identical in shape to every other field `_fromMap` already reads (`location`,
`hasGymAccess`, etc.), all of which share this same untested-read-path gap
predating this change — not a new risk introduced by Gate F, and consistent with
the existing coverage boundary in this file.

`equipment_detail_page.dart`'s new read-and-fallback logic
(`ref.read(currentProfileProvider)...`) also has no direct widget test: the page
has no existing test file, and building one from scratch would require a full
provider-mocking harness for an unrelated page well beyond this gate's scope. The
logic itself is a single ternary, verified by manual trace against
`equipment_report_sheet.dart`'s default (confirmed via `grep`: `gymId = 'unknown'`
was never previously passed by any caller in the repo), and the fallback value is
unchanged from today's behavior for the unset case.
