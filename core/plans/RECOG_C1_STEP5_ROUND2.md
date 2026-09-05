# RECOG-C1 step 5 — round 2, verification of the round-1 remediation

Round 1 returned `VERDICT: BLOCKER` with 2 BLOCKER + 2 MAJOR. **All four were accepted, verified
against source first, and fixed.** Per the one-sweep rule this round is scoped to exactly two
things: whether those four are genuinely closed, and whether the remediation itself introduced a
BLOCKER/MAJOR regression. Nothing else in the diff is open for this round.

## BLOCKER 1 — process-death window between the charge and the row

**You were right and I was defending the weaker design.** My previous position was that a
write-ahead marker introduces its own crash window where a row looks spent but never was. Your
counter removes that objection entirely: the marker records that a call was ABOUT TO BE MADE, not
that quota was burned, so a crash before the call cannot retire a photograph.

Implemented exactly that way:

- `attempt_started` is written and flushed inside the recording ask, after the exact bytes are
  known and immediately before `real(bytes)`. It carries `observation_id`, `pair_id`, `arm`,
  `attempt_no`, `image_id`, `sent_sha256`, `sent_bytes` — the sha so a later retry can prove it is
  repeating the same call.
- `readJournal` returns `observed` and `uncertain` (a marker with no matching observation)
  separately. Uncertain rows are **neither re-run nor counted as done**; they are named in an
  `attempts_uncertain` control record for an explicit whole-pair retry under a new run id.
- **A real defect this introduced, which an existing test caught before you had to:** the marker
  write happens inside the ask, and `GeminiVisualEquipmentService` wraps anything the ask throws in
  a `VisualEquipmentException` (`gemini_equipment_service.dart:227`), so a storage failure while
  writing the marker was being swallowed into `classify_error` — a full disk recorded as a MODEL
  failure, real cause lost. Now carried on the capture as `journalError` and re-raised from
  `observe`, and the run stops rather than continuing to make calls it cannot account for.

## BLOCKER 2 — a forgotten define runs all 104 observations in one UTC day

Confirmed exactly as you described. `configurationProblem()` now fails CLOSED at the production
entry: window must be 1 or 2, and `RECOG_C1_PLAN_SHA` and `RECOG_C1_SOURCE_SHA` must both be
non-empty. `run()` additionally refuses a selected window that is not 52 rows across 26 pairs —
the window is only a protection if it is the size the quota arithmetic assumed. Window 0 stays
reachable by `run()` itself, which is what the tests drive with their own small plans.

## MAJOR 1 — nothing bound the instrument to the artifacts it claims

`RECOG_C1_PLAN_SHA` is now compiled into the binary, `run()` hashes `run_plan.csv` on device and
refuses a mismatch, and every observation and control record carries `plan_sha256`.
`recog_c1_deploy.ps1` computes the hash from the bytes it just pushed, prints it in the build
command, and warns when the working tree is dirty — because `git rev-parse HEAD` names a commit
whose contents are not what gets compiled from a dirty tree.

## MAJOR 2 — resume was observation-atomic, not pair-atomic

Taken as your option (a). Every row carries a random-per-invocation `session_id`, and a resume
about to split a pair writes `pairs_split_by_resume` naming it. Both arms still run, because each
is a valid single-arm observation. **Methodology addition, declared now, before any inference:**
step 8 admits a pair to the crop-effect metric only when both arms share `pair_id` AND
`session_id`. Please say if you want option (b) — refusing the partner outright — instead; I chose
(a) because (b) discards an already-charged call.

## Evidence

35 tests, `flutter analyze` clean, deploy script parses clean. Full suite `+3623 -25`; all 25
failures are the pre-existing `test/golden/` pixel diffs confirmed unrelated by restoring HEAD's
`main.dart` and reproducing them exactly.

Every one of the eight new guarantees was mutation-checked — the guard was broken, the suite
confirmed to fail, the file restored:

| mutation | suite |
| --- | --- |
| delete the window guard | `+34 -1` |
| stop checking the plan against the compiled hash | `+34 -1` |
| drop the 52-rows/26-pairs assertion | `+34 -1` |
| remove the marker's durability | `+33 -2` |
| treat a dangling marker as done | `+34 -1` |
| swallow a journal failure into `classify_error` | `+32 -3` |
| stop naming split pairs | `+34 -1` |
| one session id for every invocation | `+34 -1` |

**My first attempt at the window guard's test was not load-bearing and the mutation said so** — it
asserted only "the configuration was refused", which any of the five checks satisfies, so deleting
the window branch left it green. Fixed by giving `configurationProblem` per-input parameters, so
each branch is isolated. Treat "the tests are green" as a claim to attack; in this gate it has
been wrong three times.

## Out of scope for this round

The 25 pre-existing golden failures, the three unresolved ground-truth photographs, the frozen
contract and ground truth, and the disclosed missing server correlation id — which you already
declined to promote to a finding, and I agree.
