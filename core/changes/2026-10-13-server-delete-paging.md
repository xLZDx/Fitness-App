# Change record: bounded account-deletion sweep and export size guard (NEW-DELETE-OOM)

**Problem.** `sweepSharedRecords(uid)` in `functions/src/index.ts` read whole shared collections with an unbounded `.get()` during account deletion, so a large collection could exhaust memory or time and leave a deletion half done. The export in `functions/src/account_export.ts` was capped by row count only, so a few very large rows could still exceed the callable response size.

**Change.**
- The sweep now reads in pages of 450 (`SWEEP_PAGE`) and commits each page, until no query returns a full page. The same four queries run and each record is deleted or anonymised exactly as before; a failing commit still throws, so `deleteAccount` fails the same way.
- The export gets `MAX_EXPORT_BYTES` (8 MiB, under the 10 MiB callable limit). When the serialized body is over it, the largest array sections are halved until it fits and each trimmed section is added to the existing `truncated` list, so the export is never silently short.
- Tests: the delete-account mock supports `.limit()` and applies committed writes; new cases for 1000 rows across several pages, a failed commit, and an oversized export.

**Contracts and paths touched.** Account-deletion callable behaviour (unchanged result, bounded work), export response shape (`truncated` may now name byte-trimmed sections by response key such as `debugSessions`).

**Known edges.** A self-booking that appears on only one side of a page is finished on a later page and still ends up deleted. Halving a section can drop more rows than strictly needed.

**Verification state.** Not run yet: focused functional tests are written and run by the test agents at the end of the sprint. Nothing pushed.
