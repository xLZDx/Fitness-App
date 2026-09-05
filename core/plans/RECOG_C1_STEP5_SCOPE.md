# RECOG-C1 step 5 — review scope

Plan `fitness_app-2026-09-05T11-25-16-919Z-377ee0`, step 5 of 10. One adversarial sweep,
please: the complete BLOCKER/MAJOR set in one pass, not one finding per round.

## What this gate is, and what it is not

RECOG-C1 measures how accurate cloud equipment recognition actually is over the operator's own
52-photograph corpus, under the conditions real users will produce: odd angles, other machines
in frame, and — the operator's explicit bar — a camera pointed at a monitor showing a machine.
Steps 1–4 are committed and frozen. Step 5 builds the instrument. **No cloud call has been made
yet.** Steps 6–10 build the APK, run the 104 paired observations across two UTC windows,
compute the metrics, then DELETE the harness and prove the tree byte-identical.

The gate's own invariant, and the only thing that should block it:

> The harness must measure the production path faithfully, must not spend a single recognition
> call it cannot account for, and must not record a failure in a way the offline analysis would
> misread as a measurement.

## Files in scope

| file | state |
| --- | --- |
| `mobile/lib/features/visual_equipment/measurement/recog_c1_harness.dart` | new |
| `mobile/lib/main.dart` | modified, +13 lines (the seam) |
| `mobile/test/features/visual_equipment/recog_c1_harness_test.dart` | new, 25 tests |
| `mobile/test/tools/recog_c1_generate_run_plan.dart` | new |
| `core/plans/RECOG_C1_RUN_PLAN_2026-09-05.csv` | new, 104 rows |
| `scripts/dev/recog_c1_deploy.ps1` | new |

## Frozen — a finding here must argue for breaking a freeze, explicitly

- `mobile/lib/features/visual_equipment/measurement/recog_c1_contract.dart` — the scoring
  taxonomy and `classifyResponse`, committed at `7eb4392`.
- `core/plans/RECOG_C1_GROUND_TRUTH_2026-09-05.csv` and
  `core/plans/RECOG_C1_LABELS_2026-09-05.csv`, frozen by
  `core/plans/RECOG_C1_GT_FREEZE_2026-09-05.md`.

Freezing the contract before any inference is the whole methodology: a scoring rule chosen
after seeing the results is not a measurement. Propose a change to it only if it is wrong, and
say plainly that the freeze must break.

## Constraints that make this different from ordinary code

- **Quota**: 60 recognition calls per user per UTC day, enforced BEFORE the model call
  (`functions/src/ai_equipment_recognition.ts:124-128`). The measurement is 104 observations,
  hence two windows. A call spent twice is a call unrecoverable that day.
- **The harness runs from `main()`**, so any restart re-enters it. Resume correctness is what
  protects the quota, not carefulness.
- `kEnabled` is `kDebugMode && bool.fromEnvironment('RECOG_C1_HARNESS')`, both compile-time
  constants, so a release build folds every guard away.

## Disclosed deviation from the plan's own DoD

The plan requires each row to carry a **server correlation id**. The callable has none:
`functions/src/ai_equipment_recognition.ts:165` returns `{ text }` and nothing else. Every row
therefore carries `server_correlation_id: null` plus the reason, and records what does exist
(client observation id, exact UTC start/end, callable name and region, and the
`FirebaseFunctionsException` code/message/details on failure). **Step 5's DoD is partial**, and
the tail is that the id cannot exist until the callable returns one. This is also a real
product observability gap — nothing links a client failure to a server log line — and I am
raising it as a roadmap item rather than closing it silently.

## Already found and fixed, by internal review, before this round

One sweep already ran internally (`flutter-reviewer`, `silent-failure-hunter`,
`functional-test-reviewer`, `code-reviewer`). Please verify these rather than rediscover them:

1. **MAJOR** — the abort valve read `transport_error`, which a client-side timeout never sets:
   the production budget wraps the injected ask from OUTSIDE
   (`gemini_equipment_service.dart:147`) and `Future.timeout` races a timer instead of
   cancelling. Now reads the frozen `responseClass == operationalFailure` predicate.
2. **MAJOR** — the `run_aborted` record was written through the same `IOSink` whose failure is
   one of its own trigger paths. Now: sink closed first, record written on a fresh append
   handle, `finally`'s close guarded.
3. **MINOR** — `runWhenSignedIn`'s `try` did not cover the sign-in wait.
4. **MINOR** — a callable that RETURNED with null text was stamped `operationalFailure`, the
   class excluded from every semantic denominator. The harness now tracks `call_returned` and
   passes `''` to the frozen classifier, which yields `malformedParseFailure`. The contract
   itself is untouched.

A second internal sweep after that remediation found three more, all fixed:

5. **MAJOR** — the consecutive-operational-failure valve stopped the run with a bare `break`
   and nothing on disk. That is the same "short file could mean anything" ambiguity the
   `run_aborted` row exists to remove, on the stop condition most likely to actually fire,
   because it is the quota wall. Now writes a `run_stopped_consecutive_failures` control row
   carrying the count, the threshold, and how many observations were left unrun.
6. **MINOR, worse than it sounds** — the id-uniqueness test could not have failed. All 104
   committed rows are `attempt_no` 1 and `(pair_id, arm)` is already unique across them, so
   dropping `attempt_no` from `observationId` would have stayed green — while a retry, defined
   as a fresh run reusing a pair id with a higher attempt number, would then be recognised as
   already-observed and silently skipped.
7. **MAJOR (test fidelity)** — the failing-sink fake threw synchronously from `writeln`. A real
   `File.openWrite` sink buffers and surfaces a volume error from `flush`, so the fake never
   reached the ordering the production comment calls the realistic one.

**Accepted as a documented residual risk, not fixed** — please challenge this specifically if
you disagree: quota is charged BEFORE the model call and the row is written AFTER it returns,
so a process death in that window spends a charged call with no record, and resume re-runs the
row. The obvious fix — a "call started" marker before every call — doubles the writes and opens
its own crash window in which the failure mode is worse: a row that looks spent but never was,
and is therefore never measured. Losing one call in sixty beats losing a photograph. Recorded
in the file header rather than fixed.

Every fix above is mutation-checked: the guard was broken, the suite was confirmed to fail, and
the file was restored and re-verified. The suite is 25 tests. Two of these findings were tests
that passed against broken code — one I caught myself, one the reviewer caught — so please
treat "the tests are green" as a claim to attack rather than evidence.

## What I most want challenged

- Anything that could spend a recognition call without recording it, or record one twice.
- Any failure mode the raw JSONL would present to the step-8 analysis as a measurement.
- Whether the pairing/alternation design (`A`=original, `B`=viewfinder crop, adjacent in time,
  order alternating by pair index) can be confounded by drift the plan does not cancel.
- Whether `scripts/dev/recog_c1_deploy.ps1` can push the wrong arm's images or a stale plan
  without the harness noticing. The sha256 gate in `observe` is the intended backstop; say if it
  is insufficient.

## Explicitly out of scope for this round

- 25 pre-existing golden-test failures in `mobile/test/golden/`. Verified unrelated by
  restoring HEAD's `main.dart` and re-running: identical pixel diffs (`hud_panel_dark.png`
  8.99% / 3272px both ways), text-only, a font-substitution artifact. Roadmap, not this gate.
- The three unresolved ground-truth photographs (#15/#29/#47, a Star Trac plate-loaded unit).
  Frozen as `gt_status = unresolved` and excluded from every accuracy metric; an operator
  answer before the first inference re-opens exactly those six rows.
- Two App Check credential-cleanup items that are operator-only under CLAUDE.md §4/§16/§20.
