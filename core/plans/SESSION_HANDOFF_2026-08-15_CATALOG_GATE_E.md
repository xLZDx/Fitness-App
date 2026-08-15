# Session handoff — exercise catalog Gate E, 2026-08-15

**From:** the catalog session (exercise content audit and remediation)
**To:** the concurrent form-check session working in this same repository
**Written:** 2026-08-15 (local Europe/Chisinau) / 2026-08-15 UTC
**State at handoff:** pushed, `origin/master` = `f81ba44`, working tree clean except your files

This session is closing. Everything below is either something you need to act on, something
that will bite you if you do not know it, or an open item that needs its own GO.

---

## 1. Act on this: two defects in your own file

Codex reviewed the uncommitted tree with `--uncommitted`, which pulls in untracked files, so it
read `mobile/test/features/form_check/coach_single_status_test.dart`. That file was NOT touched
from this session — it is your in-flight work and editing it from here would have been the same
cross-session interference that already cost this gate an index contaminated with 102 lines of
someone else's draft.

**BLOCKER — `coach_single_status_test.dart:140` and `:176`**
The test references `avatarCannotPlaceBodyProvider` (line 140) and `coachStatusHasRepVerdict`
(line 176). Neither identifier exists anywhere else in the repository. The canonical test suite
cannot compile while this file is present.

**MAJOR — `coach_single_status_test.dart:48`**
The test searches for the keys `coach.ready`, `coach.checking` and `form_check.cue_card`.
Production assigns none of them. The key the cue-ready widget actually uses, `form_check.ready`,
is not checked at all. The readiness and dual-surface assertions are therefore **false-green** —
they pass because the finder matches nothing, not because the behaviour holds.

Both findings were cross-checked against the file rather than passed on as reported, and the
evidence is stronger than the report. Line 48 is `Key('coach.ready'),`, line 140 is
`expect(c.read(avatarCannotPlaceBodyProvider), isTrue,`, line 176 is
`expect(coachStatusHasRepVerdict(session), isTrue,` — all three exactly as cited. A repo-wide
`grep -rl --include=*.dart` then gives:

| Symbol / key | Files containing it |
|---|---|
| `avatarCannotPlaceBodyProvider` | 1 — the test itself |
| `coachStatusHasRepVerdict` | 1 — the test itself |
| `coach.ready` | 1 — the test itself |
| `coach.checking` | 1 — the test itself |
| `form_check.cue_card` | 1 — the test itself |
| `form_check.ready` | 1 — `mobile/lib/features/form_check/form_check_page.dart` |

So every symbol and key the test asserts on is defined nowhere but the test, and the one key
production actually ships is the one key the test never looks for.

The second is the defect class this gate hit repeatedly, in four separate places, and it is the
single most useful thing to carry out of this session: **an assertion that cannot fail reads
exactly like an assertion that passes.** Do not re-read the test to check it — mutate it. Delete
or disable the widget under test, re-run, and confirm it goes red. If it stays green, the test
proves nothing regardless of how much code it executes.

---

## 2. Know this: the test suite has a cross-session race, and `tail` lies about failures

**The InkSparkle race.** `flutter test` rebuilds `build/unit_test_assets` by deleting the whole
directory and rewriting roughly 3,010 files, with `shaders/ink_sparkle.frag` written last. Two
concurrent `flutter test` invocations therefore make every `tester.tap` test in BOTH runs fail
with `Asset 'shaders/ink_sparkle.frag' not found`. This is not flakiness in either session's
changes. If you see a burst of tap-test failures that make no sense, check whether another
`flutter test` is running before debugging anything.

For that reason no full-suite run was done from this session after the split — running one would
have broken your run as well as producing a meaningless number. Scoped runs were used instead:
`flutter test test/features/equipment/` → 320 passed, `python -m pytest scripts/catalog/` → 185
passed.

**`tail` misattributes failures.** In `flutter test` output the `-N` counter is a RUNNING TOTAL,
not a property of the suite named on that line. A *passing* negative-control test that dumps a
~150-frame stack will fill the tail window and push the real failure out of view. This session
blamed two innocent files that way before switching method. Use `flutter test --machine` and read
`testDone` events where `result != "success"`:

```bash
flutter test <path> --machine 2>/dev/null | python3 -c "
import sys, json
names = {}
for line in sys.stdin:
    try: e = json.loads(line)
    except Exception: continue
    if not isinstance(e, dict): continue
    if e.get('type') == 'testStart': names[e['test']['id']] = e['test']['name']
    if e.get('type') == 'testDone' and e.get('result') != 'success':
        print('FAILED:', names.get(e.get('testID')))
"
```

**One pre-existing failure is yours, not the catalog's.** `app_semantic_colors_test.dart` fails on
its hardcoded-white ratchet (64 → 61). It is driven by unstaged edits under `mobile/lib/`, and no
change from this session touches any file under `mobile/lib/` — verified against the staged index.

---

## 3. Know this: `contraindications` is generated, not hand-editable

`contraindications` is produced by `scripts/catalog/tag_contraindications.py`. Hand-editing it in
`exercises_vendor.json` breaks a sorted/unique invariant test and is silently reverted by
`retract_stale_tags` on the next run. This session made exactly that mistake and only caught it
because Codex asked — the Flutter suite was green, and the Python suite that would have caught it
had never been run. **Changing catalog tags means changing a tagger rule and regenerating**, e.g.

```bash
python scripts/catalog/tag_contraindications.py --region wrist,shoulder,lower_back --write
```

Ratchet counts live in three places and must move together in the same commit:
`scripts/catalog/test_tag_contraindications.py` (per-region counts),
`mobile/test/features/equipment/safety_coverage_test.dart` (`kSafetyCoverageFloor` and the
`batched` map).

---

## 4. Know this: catalog invariants and the Windows newline hazard

- `summary == steps[0]` holds for all 1887 EN rows. It is relied on by the tests and the audit
  tooling. **The RU overlay does not hold it — 127 rows diverge**, measured identical at `HEAD`
  and after this work, so none were introduced here. RU has no equivalent guard.
- RU must match EN step counts. Currently 0 mismatches.
- Both catalog files are LF. Python's default text-mode write converts `\n` to `\r\n` on Windows
  and will rewrite all 1887 rows as a spurious diff. Always write with `newline='\n'`, and check
  `git diff --numstat` afterwards — a real edit to three fields shows 3 changed lines, not 60,000.

---

## 5. What shipped, and what did not

Pushed as `8125a5c` and `f81ba44`, on top of `68b7dad` which was this gate's work committed from
your session while it was still mid-correction.

**Shipped:** both barbell clean variants corrected (the shipped muscle clean described a high
pull); six regressions introduced by this gate's own earlier "softening" pass, reverted or
reworded; the assisted close-grip chin-up made unambiguous; tyre-hammering eye protection moved
out of `purpose` into `steps[0]`; regression tests rewritten to assert the real distinctions in
both EN and RU, all mutation-verified.

**NOT shipped: the Firebase App Distribution build.** "Ship the Build to the Tester" wants a
fresh build closing the gate, and these are user-visible content changes. It was not done because
the build runs from the working tree, which holds your uncommitted form-check WIP —
`build_release.ps1:61-67` would stamp the APK `-dirty` and the tester would get a build matching
no commit. **This is now yours to close**: either build once your form-check work is committed, so
one build covers both, or build `f81ba44` from a clean `git worktree` if you want catalog-only.

---

## 6. Open items — each needs its own GO, none are started

**Known-wrong cards, 5:**
`ea_major_groups_muscle_body` (a single generic standing step, no real exercise — quarantine or
delete), `ea_cable_wrist_extension` (asserts a flexor/extensor strength parity that does not
exist, plus an unhedged causal medical claim), `ea_puppy_pose` ("the lower back is not involved"
is backwards for this pose), `ea_sissy_squat_bodyweight` (implies any knee adapts eventually),
`ea_criss_cross_bow_tie_pose` (RU title describes a seated crossed-legs hip opener; the exercise
is a shoulder stretch, and its own RU steps say so).

**Data-quality populations:**
127 RU rows where `summary != steps[0]`; 78 rows where `equipmentLabel` is the literal string
`"None"` while `equipmentId` names a real machine; 59 `DEDUP_CANDIDATE` cards; 360 rows with no
contraindication tag in any region; `ea_hand_stand_hold` / `ea_monkey_pose` / `ea_tyre_flip`
untagged, the first because the tagger's `handstand` token never matches the two-word title
"Hand Stand Hold" — a fail-open the tagger already documents for `\b` and underscores.

**Never examined at all:** 1368 of 1887 cards (72.5%) were never flagged by a detector and never
read card by card, and 224 cards share a `summary` with another card while never having been
flagged. See `core/plans/CATALOG_DESCRIPTION_COVERAGE_2026-08-15.md` for the full accounting and
a reproduction script for every figure.

**Persistence risk:** the three CSVs the Gate E counts derive from live in the operator's
`Downloads` directory, outside the repository — the same failure class as the 2026-08-04 loss of
131 unpersisted findings. Moving them under `core/` needs its own gate.

---

## 7. Codex is rate-limited until 2026-08-20

The ChatGPT account backing `codex_review.py` hit its usage limit. Round 5 of this gate's
consensus loop could not run; its receipt records `ok: false` and the fail-open policy applied.
Retry is available **2026-08-20 17:32 UTC**.

This matters for you directly: `codex_review_gate.py` blocks `git commit` without a receipt for
this repo within 6h, and blocks `git push` unless the most recent receipt has `final: true`. A
fail-open receipt satisfies both — only a call that was never made blocks. So commits and pushes
will still work, but **you will not get an independent review until the 20th**. Given that rounds
2, 3 and 4 of this gate each found defects in the PREVIOUS round's fixes rather than in the
original work, that absence is worth compensating for with mutation testing rather than ignoring.

---

## 8. The one method rule worth keeping

Every defect this gate found in its own work was found by mutation, never by re-reading. Four
separate assertions in this session looked correct and could not fail. The rule that came out of
it, now enforced by a test rather than only written down:

> A prose edit to this catalog ships with an assertion that fails when the edit is reverted, or
> it does not ship.

The general form applies to your work too: **if deleting the feature under test leaves the test
green, the test proves nothing about that feature.**
