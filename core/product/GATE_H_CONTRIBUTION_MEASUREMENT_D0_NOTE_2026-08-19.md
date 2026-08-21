# Gate H — contribution pipeline measurement (MRD-07) — evidence note

2026-08-19. Final gate of this session's product-implementation run. Continues the Gate D-G
pattern: reconnaissance before code, minimal safe seam, defer what the evidence doesn't support yet.

## Scope actually claimed

MRD-07, as named consistently across three prior references in this repo (`core/marketing/
claim_register.json`'s `unknown-coverage-queue` claim row, `SPTR_MARKETING_SITE_CLAIM_REGISTER_
2026-08-19.md`, `SPTR_MARKETING_SITE_GOVERNANCE_REMEDIATION_2026-08-19.md` section 7) is the
"measurement layer" over the app's existing unrecognised-machine contribution mechanism
(`MachineCard`). All three references describe the mechanism as built and the measurement as
missing; the governance-remediation doc explicitly lists MRD-07 as out of scope for that (marketing)
change specifically, not as a standing refusal for a future product-implementation gate.

## Reconnaissance

A dedicated read-only agent answered five questions with file:line evidence before any code was
written (full report in the session transcript; summarized here):

1. **No operator/admin-facing reader of `MachineCard` data exists.** The capability is claimed in
   three separate doc comments ("the same numbers come out of a collection-group read... with the
   Admin SDK") but none of them is a description of something built — grepping every Cloud Function
   export, every `scripts/` file, and the whole repo for `collection-group`/`collectionGroup`/
   `machine_cards` found zero scripts, zero admin pages, zero Cloud Functions reading it across
   users. The only Cloud Function touching `machine_cards` at all is the per-user account-export
   path (`functions/src/account_export.ts:172`), which reads one signed-in user's own subcollection,
   not an aggregate.
2. **No analytics/reporting subsystem exists anywhere in this codebase to extend.** No scheduled
   Cloud Function, no dashboard, no "top N" query pattern. The nearest structural precedent is
   `scripts/ops/strip_health_from_profiles.py`, a one-off, dry-run-first, REST-collection-group-query
   compliance script — a workable *pattern* to imitate (REST auth via the Firebase CLI's own stored
   credentials, collection-group query shape), but it is a migration/compliance idiom, not a metrics
   idiom, and it mutates data (with a safety gate) where this gate's work should not.
3. **MRD-07 is referenced in exactly three places, all agreeing on the same one-sentence scope**:
   "cards + merge + count exist; a measurement/reporting layer over them does not exist and was
   never scoped." No D0 note, no plan file, no decision-log entry defines *who* consumes the
   measurement, *how often*, or *what threshold* triggers filming a clip.
4. **The user-facing angle that exists is own-device only, not cross-user.** The scanner shows a
   user "scanned N times" for their own repeat sightings of their own card
   (`scanner_page.dart:1097-1099`, `machineCardSeenTimes` ICU string) — never a cross-user count.
   More importantly: **nothing in the shipped app ever writes `MachineCardStatus.inCatalog` or
   `.declined`** — grepped for every assignment site, found zero. The enum values exist and the
   merge rule (`MachineCardMerge.fold`) correctly *preserves* a non-`preparing` status across new
   sightings, but nothing ever sets one in the first place. The `preparing -> inCatalog` transition
   this measurement is nominally supposed to help trigger has no writer at all today.
5. **No Cloud Function anywhere in this codebase performs cross-user aggregation**, scheduled or
   otherwise. `onSchedule` is not used anywhere in `functions/src/index.ts`. The only cross-document
   reads are narrowly-scoped, transaction-specific (e.g. `reportEquipment`'s single-document
   `gyms/{gymId}` webhook lookup) — no precedent for a recurring aggregation service in this codebase
   at all.

## Decision: a read-only report script, nothing more

The reconnaissance agent's own read, and mine independently: this is genuinely split. The
*write-side* substrate (`FirestoreMachineCardRepository`, `MachineCardMerge`, the `timesSeen`
counter) is solid, tested, shipped data — a real half-wired seam in the Gate D/E/F/G sense. The
*reading* side is not a half-wired seam at all: there is no reader, no defined audience, no cadence,
and the companion mechanism (status transitions) that would make a ranking actionable has no writer
either. Building a dashboard, a scheduled digest, a notification loop, or automating the
`preparing -> inCatalog` transition would all require deciding who looks at this and how — a
business/product decision this repo has no evidence for, and exactly the class of "invent new
infrastructure/policy" work Gates D-G have each avoided.

What the evidence *does* support, without inventing anything: the collection-group read the
repository's own doc comment describes as "possible" genuinely is possible, using patterns that
already exist verbatim in this repo (`firebase_api.py`'s CLI-credential auth, the REST
collection-group query shape from `strip_health_from_profiles.py`). A **read-only report script**
that runs that query, aggregates `MachineCard.timesSeen` across users per machine, and prints a
ranked table answering the repository's own stated question ("which missing clip do we film first")
requires no new schema, no new Firestore rules, no new Cloud Function, no scheduled job, and no
decision about audience or cadence — it is a tool the operator runs by hand, like every other script
in `scripts/ops/`, the same way `strip_health_from_profiles.py` is run by hand rather than scheduled.
This is the smallest slice of MRD-07 the current evidence actually supports.

**Explicitly not attempted, and why:**
- **No dashboard/scheduled job/notification loop.** No evidence of intended audience, cadence, or
  delivery channel — inventing one would be a product decision, not a wiring task.
- **No automation of the `preparing -> inCatalog` transition.** Nothing writes it today; deciding
  *what* should write it (a manual admin action? a catalog-build script cross-referencing card ids
  against shipped exercise ids?) is a separate, undecided piece of scope with no evidence to build
  from.
- **No write path of any kind.** This is a read-only report; `--apply` from the
  `strip_health_from_profiles.py` precedent does not apply because there is nothing to mutate.

## What shipped

- `scripts/ops/machine_card_contribution_report.py` (new) — collection-group REST query over
  `machine_cards` (mirrors `strip_health_from_profiles.py`'s `find_profiles` shape), decodes the
  Firestore REST value union for the fields `MachineCard.toJson()` actually produces, aggregates
  `timesSeen` per machine id across every user, and prints a table ranked by total sightings (tied
  broken by distinct-user count, so one enthusiastic photographer cannot outrank a machine three
  separate people asked about). Excludes cards where every recorded sighting is already resolved
  past `preparing` by default (`--include-resolved` to see them anyway) — in practice always shows
  everything, since nothing writes a resolved status today, but the check stays honest rather than
  assuming that never changes.
- `scripts/ops/test_machine_card_contribution_report.py` (new) — 28 pytest tests (19 original plus 9
  added during review, see addendum below) against the pure `aggregate()`/`parse_card_doc()`/
  `_decode_value()`/`_earlier()`/`_later()`/`_display_name()`/`render()` functions (no live Firestore
  call in any test, matching `strip_health_from_profiles.py`'s own precedent of no test coverage for
  the network half).

## Data hygiene

The report never prints a document path, a `uid`, or any other value that would tie a sighting to
the person who took it — aggregated counts and machine names only. Verified by a dedicated test
(`test_never_prints_a_uid_or_document_path`) that asserts a real-looking uid string does not appear
anywhere in rendered output.

## Review addendum

Two independent read-only agents reviewed the script and its tests: `security-reviewer` and
`python-reviewer`. No cross-seeding between rounds.

**security-reviewer**: clean — no BLOCKER/MAJOR. Two MINOR hardening suggestions, both applied
before the tests below were written: (1) narrow the REST query's `select` to only the fields the
report reads, so `recognisedAs`/`confidence`/`uses` never cross the wire at all rather than arriving
and being discarded post-decode (`find_machine_card_docs`, least-fetch discipline); (2) confirm the
never-print-uid guarantee has direct test coverage (it already did — `test_never_prints_a_uid_or_
document_path` — reviewer asked for explicit confirmation, none of the fixes changed this path).

**python-reviewer**: 4 MINOR findings, all real, all fixed and mutation-tested:

1. `_decode_value` had no `timestampValue` branch, even though `firestore_machine_cards.dart`'s own
   read side documents Firestore-native Timestamps as a real possibility for `firstSeenAt`/
   `lastSeenAt` ("what a console edit or a server-side write produces") — a document written that way
   would silently decode the date field to `None` instead of the real value. Fixed by adding the
   branch (REST timestamps are already RFC3339/ISO-8601 strings, so no conversion needed). Test:
   `test_decodes_a_timestampValue_date_field`, plus a `timestampValue` case in `TestDecodeValue`'s
   parametrize list.
2. `aggregate()` compared `firstSeenAt`/`lastSeenAt` as raw strings. Dart's `toIso8601String()` prints
   milliseconds unconditionally but microseconds only when nonzero, so the same instant can appear as
   `"...500Z"` or `"...500001Z"` — variable width that a lexicographic comparison reads backwards
   (`'Z' > '0'` at the first differing character). Fixed with `_earlier()`/`_later()`/`_parse_iso()`
   helpers that parse into real `datetime` objects before comparing, with explicit `None`/unparseable
   handling (a naive/aware `datetime` comparison hazard in an earlier draft of this fix was caught and
   avoided before ever running a test, by re-reading the code and avoiding sentinel-based comparison
   entirely). Test: `TestEarlierLater` (3 tests — the exact variable-width regression, `None`
   handling, unparseable-string-doesn't-crash).
3. `parse_card_doc`'s `isinstance(times_seen, int)` check accepted booleans, since `bool` is a Python
   subclass of `int` — a hand-edited `timesSeen: true` would silently contribute a phantom sighting
   instead of being skipped as malformed. Fixed with an explicit `and not isinstance(times_seen, bool)`
   exclusion. Test: `test_skips_a_document_whose_timesSeen_is_a_boolean`.
4. `render()` printed names at a fixed column width with no truncation marker — two machines whose
   names agree for the first 32 characters (plausible for verbose vision-model-generated descriptions)
   would print as identical rows with no visible signal they're different. Fixed with a `_display_name()`
   helper that truncates with a trailing `~`; `aggregate()` itself still always keys on the untruncated
   `id`, never the display string, so truncation never affects ranking or merging. Tests: `TestDisplayName`
   (3 tests — short name passthrough, long name truncated with the marker, and a correctness test
   proving `aggregate()` never merges two cards whose names share a 32-character prefix even though
   `render()` alone can't fully visually disambiguate them).

## Verification

- 28 pytest tests, all passing (19 original + 9 added during review), covering: sighting aggregation
  across users, per-machine isolation, ranking (including the distinct-user tiebreak), first/last-seen
  date folding via parsed-datetime comparison, the resolved/unresolved status check, REST value
  decoding for every shape `MachineCard.toJson()` produces plus `timestampValue`, malformed-document
  skipping (missing required field, path with no uid, boolean `timesSeen`), display-name truncation,
  and the never-print-uid privacy guarantee.
- Mutation testing, all five fixes, using the established break → confirm-fail-with-predicted-symptom →
  restore → `diff`-verify-identical pattern (backups kept in the session scratchpad, never in the repo):
  - Distinct-user tiebreak: removed from the sort key — the first attempt at this test used machine
    names that happened to sort correctly by name alone even without the real tiebreak, silently
    passing against the mutation; caught by reviewing the failure output, renamed the test's fixture
    data so alphabetical order alone would rank them wrong, re-confirmed the mutation is now caught.
  - `timestampValue` decode: removed the branch — `test_decodes_a_timestampValue_date_field` failed
    with `None == '...'` as predicted.
  - Bool-exclusion: removed `isinstance(times_seen, bool)` — `test_skips_a_document_whose_timesSeen_
    is_a_boolean` failed by returning a parsed dict instead of `None`, as predicted.
  - Date comparison: reverted `_earlier`/`_later` to raw string comparison (bypassing `_parse_iso`) —
    both the variable-width-fractional-seconds regression test and the unparseable-string test failed
    exactly as predicted (the third `TestEarlierLater` test, `None`-handling, correctly kept passing
    since that path never touches string comparison).
  - Display truncation: removed the `~` marker — `test_a_long_name_is_truncated_with_a_visible_marker`
    failed on the `endswith('~')` assertion as predicted; the other two `TestDisplayName` tests
    correctly kept passing.
  All five restores verified byte-identical via `diff -q` before deleting the backup.
- `python -m py_compile` clean on both the script and its test file. No `flutter analyze` applicable —
  this gate touches no Dart/Flutter code.

## Known gaps

- No test exercises `find_machine_card_docs`, `access_token`, or the live REST call path — consistent
  with `strip_health_from_profiles.py`'s own precedent (a live network call against real Firestore
  credentials is not something a unit test should fake its way around; this repo has no Firestore
  emulator harness for Python scripts).
- The script has never been run against real production data as part of this gate (would require
  live operator credentials and touches real user data, even read-only) — verified only via unit
  tests against synthetic fixtures. The operator should run it once by hand to confirm the live query
  and REST decoding behave as expected against the real `machine_cards` collection shape before
  relying on its output.
