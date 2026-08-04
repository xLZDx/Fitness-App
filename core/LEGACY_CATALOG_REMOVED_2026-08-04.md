# The pre-purchase catalog is gone — 2026-08-04

Operator: *"оставить только вендорский контент 1887 упражнений это и так очень
много"*, then *"удали старый каталог"* once the equipment linking was done.

`mobile/assets/data/exercises.json` (511 entries) and its Russian overlay are
deleted, along with `assets/exercises/` — 132 photographs, 8.1 MB — that only
it referenced. One catalog ships now.

CSV twin: `core/LEGACY_CATALOG_REMOVED_2026-08-04.csv`.

---

## Why it was safe to remove, in the order it was established

1. **Its clips were duplicates.** 371 of the 373 distinct clip references the
   legacy catalog still had after the licence audit pointed at object keys the
   vendor catalog already uses. Keeping both meant showing the same footage
   under two names.
2. **Its machine links were the only reason to keep it, and they were
   replaced.** Legacy carried 404 `equipmentId` values against a vendor
   catalog that had zero. That is what the 2026-08-03/04 linking gates fixed:
   1,383 vendor exercises now carry one, across 65 of 69 machines.
3. **The four machines it uniquely covered were checked by hand, not
   assumed.** `recumbent_bike`, `glute_kickback_machine`, `t_bar_row` and
   `rotary_torso_machine` had 1, 3, 4 and 3 legacy exercises and have no
   vendor clip at all. Those four pages are empty now. This was surfaced
   before the deletion, not discovered after it — see the "known empty" test
   in `registry_test.dart`, which names them so a FIFTH machine going empty
   still fails.

## A real bug this exposed, and the fix

`AssetEquipmentRepository._translate` discarded an entire overlay entry —
**title included** — when the translation carried no steps:

```dart
if (title is! String || title.trim().isEmpty || steps.isEmpty) return item;
```

Harmless while the pre-purchase catalog was the visible half: every one of its
rows had instructions. The purchased library ships **403 of 1,887 with a title
and no steps**, so with legacy gone this silently left a fifth of the app
showing English titles under a Russian UI — with the correct Russian sitting
unused in `exercises_vendor.ru.json`. Operator's standing rule on Russian is
"mandatory, hide nothing", and this was hiding it.

Fixed: the title is applied whenever it is present, and steps the overlay does
not have are kept from the base rather than blanked — so an overlay that loses
its steps can never delete instructions either. Regression test added covering
both halves; the case used to sit in the "malformed, keep English" list, which
is exactly how it survived.

Found by a test failing for the *right* reason after the repoint, not by
reading the code. Worth saying plainly: nothing else was checking it.

## What was removed

| | |
|---|---|
| `assets/data/exercises.json` | 511 entries, 778 KB |
| `assets/data/exercises.ru.json` | 530 KB |
| `assets/exercises/` | 132 photographs, 8.1 MB — unreachable since the clip-only rule, referenced by nothing else |
| `includeLegacyCatalog` | setting, its persistence key, its controller method, its Settings row, 3 l10n strings x2 languages |
| `AssetEquipmentRepository.includeLegacy` | constructor flag and the conditional load |
| `legacy_switch_test.dart` | 8 tests for a switch that no longer exists |
| `demo_coverage_test.dart` | 4 tests, all about legacy's partial imagery — vendor is 100% clipped and `vendor_catalog_test` already asserts it |
| `video_library_test.dart` | 13 tests about the 677-file drop into legacy; the clip-key shape it guarded is covered by `vendor_catalog_test` |
| `build_registry.py`'s `REASSIGN` / `NEW_EXERCISES` | patched a file that no longer exists |

**~9.4 MB out of the APK.**

## What was kept, and repointed rather than deleted

`bundled_assets_test.dart` is the one worth naming. It existed because 66
exercises shipped with correct frame paths, all 132 files present on disk, and
every demo still rendering "Demo unavailable" — a pubspec directory entry does
not recurse, so none of them were packaged. The files that exposed that are
gone; the bug class is not, because `assets/posters/girl/` and
`assets/posters/men/` are two more non-recursive entries holding 2,539 files
the app depends on being instant and offline. The assertions moved onto them.

Loading 2,539 assets one at a time blew the 30-second test timeout, so the
check reads the asset **manifest** instead — same question, complete coverage,
no sampling.

A new test also asserts the deleted files are really absent from the bundle:
deleting a file and un-shipping it are not the same thing.

`registry_test.dart` kept the registry's own promises (ids, Russian names,
alias resolution, translation overlay) and dropped the half that was about
legacy's contents — the treadmill reassignments, the hand-authored cardio, the
free-exercise-db import, the machine hero photographs.

## Result

| | before | after |
|---|---:|---:|
| catalogs loaded at runtime | 2 | **1** |
| exercises shipped | 2,398 | **1,887** |
| ...of which play a clip | 1,887 + 355 | **1,887 (all of them)** |
| bundled assets | ~40.4 MB | **~31 MB** |
| tests | 1,095 | **1,060** |

All 1,060 pass. `flutter analyze`: the same 6 pre-existing issues, none in a
touched file.

## Not done

`data/staging/` and the `scripts/catalog/*.py` that built or patched the old
catalog (`import_free_exercise_db.py`, `merge_video_library.py`,
`relicense_legacy_catalog.py`, `match_legacy_semantic.py`, ...) are untouched.
They are the record of how the catalog got the way it did, they run against
files rather than importing app code, and deleting them would destroy the
audit trail behind the licence work without making anything smaller in the
APK. `build_registry.py` was the exception because it is still live — it
generates the registry every gate uses.
