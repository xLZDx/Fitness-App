# Integrate origin/phase2/main (a62d7c4e): PR 14 phase2/s04 gate fixes

Date: 2026-10-20. Merge of origin/phase2/main (5 commits: 63b03a7a, ea5d1b8e, 0ee39ba1, c63cdd35, merge a62d7c4e) into integrate/2026-10-20 (base 577faf07).

## What changed
Seven source files (uid_scoped_activity_journal, sign_out_guard, location_consent_providers, file_recording_journal, geolocator_location_source, recorder_ports, main.dart recorderWiredProvider override), about 25 test files (s04_gate1_*), s04 gate change records and findings doc.

## Conflicts and resolution
- core/DECISION_LOG.md, core/LESSONS_LOG.md: union of both sides.
- docs/DOCUMENT_REGISTRY.md: regenerated with scripts/dev/gen_document_registry.py.
- docs/sdlc/STATE.md: union; one older duplicate "Agents and models actually run so far" line from the branch dropped, integrate's newer form kept.
- geolocator_location_source.dart: took the branch's clean header; it is the upstream fix of the stray source line that the earlier integration had repaired by hand.
- Auto-merged main.dart keeps both the combined wipe provider and recorderWiredProvider.

## Checks
- Deleted-files audit vs HEAD: empty. No conflict markers.
- Lost content: every file changed by the branch since 5d5723fa matches the branch except newer integrate-side docs.
- dart analyze: 0 errors (201 issues, was 182; new info/warning come from newly added tests).
- flutter test (smoke + recording, activity, account_deletion, scanner, core, android): HEAD 3237 pass / 1 fail; after 3289 pass / 1 fail. Same single failure: DT-0-10 journal_availability_test (known).
- The docs/wip-snapshots Phase2_s01 patch is now obsolete: applying it to 5d5723fa yields exactly the origin/phase2/main content for 4 of 5 files; the fifth (sign_out_guard) is a strict subset of the upstream version.
