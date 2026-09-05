# RECOG-C1 step 5 — round 3, the one remaining MAJOR

Round 2 closed BLOCKER 1, BLOCKER 2 and MAJOR 2 and left one MAJOR open: the artifact binding
still validated the pushed plan against a hash derived from that same plan, and a dirty tree was
only warned about. **You were right on both halves.** Scoped to exactly that finding and to
regressions caused by fixing it.

Now committed as `81d2237` (local only — a MAJOR was standing, so nothing is pushed).

## The circularity is gone: the reference no longer comes from the artifact

New committed file `core/plans/RECOG_C1_FREEZE_MANIFEST.json` holds the authoritative
newline-normalised hashes — the run plan's is the reproducible
`4f4ef743734ce710e6e82e968db41a4c682af1f230f2c8ff2aad0d6b9828325d` you named.

`recog_c1_deploy.ps1` reads it with `git show HEAD:core/plans/RECOG_C1_FREEZE_MANIFEST.json` —
**out of the committed tree, never the working copy** — and compares the local plan against it
before anything is staged or pushed. There is no longer any local recomputation of the plan's
hash anywhere, so the scenario you described ("a modified local plan supplies both sides of the
equality") is not merely detected, it is structurally impossible: neither side of the comparison
comes from the plan any more.

The manifest missing from `HEAD` is a hard stop, not a fallback to the working copy. A fallback
would have reintroduced the whole defect through the back door.

## Dirty tree is now a hard stop

Changed from `Write-Host "WARNING"` to `throw`, and moved to the front of `-Push` so it fires
before a single byte is staged. Your reasoning applies exactly: a warning is something a run
discovers it ignored after the day's calls are spent.

## The mutation tests you asked for, run and reported

A new `-VerifyOnly` switch runs the provenance checks and exits without touching adb, so the
guards are testable on their own rather than only as a side effect of a real deployment.

| case | result |
| --- | --- |
| clean tree, frozen plan | `provenance OK: plan matches the committed manifest (4f4ef743...325d), tree is clean` |
| one byte of the plan changed (`"1","1","p00"` -> `"9","1","p00"`) | **refused**: `committed: 4f4ef743...325d / local: 8a086c86aad95841b13e20bd95556a88f0b62eac9192928721fd69831957dbdf` |
| plan restored | passes again |
| one tracked source file dirtied | **refused**: `the working tree is dirty, so RECOG_C1_SOURCE_SHA would name a commit whose contents are not what gets compiled` |
| tree restored | passes again |

Note the second row is the stronger form of your test: because the reference is the committed
manifest, "consistently recomputing the local hash" has nothing left to recompute — the local
edit simply fails.

## The residual I can see, stated rather than left for you to find

Editing the plan **for real** still works if the operator commits both the plan and the manifest
together. That is deliberate and I think correct: the point is not to make the frozen plan
immutable, it is to make changing it visible. A committed change is in `git log` where a reviewer
sees it, and the dirty-tree stop forces any change through a commit to be usable at all. Making
it genuinely immutable would need a signature or an out-of-repo reference, which is more machinery
than this one-gate instrument warrants — but say so if you disagree, because that is a judgement
call and not a fact.

## Evidence

35 tests, `flutter analyze` clean, deploy script parses clean, full suite `+3623 -25` with all 25
failures the pre-existing `test/golden/` pixel diffs. Nothing in the Dart harness changed this
round: the fix is entirely in the deploy script and the new manifest, so the eight mutation
results reported in round 2 still stand unmodified.
