# -*- coding: utf-8 -*-
"""The post-label pipeline — seven stages, and the one it refuses to run.

    python scripts/ct1/pipeline.py --fixtures          # end to end on synthetic data
    python scripts/ct1/pipeline.py --batch <dir> --submission <f> [--submission <f>]
    python -m pytest scripts/ct1/test_pipeline.py -q

    IMPORT -> VALIDATE -> ADJUDICATE -> BUILD CT1_HUMAN_EVAL_V1
           -> BASELINE EVALUATE -> ERROR ANALYSIS -> CHALLENGER GO/NO-GO

The pieces already existed and `human_eval.py` already chained the first five.
What did not exist was the last two, a single reproducible entry point, and a
way to exercise the whole chain before a single human label comes back — which
is the state this repository is actually in and will be in for weeks.

## The stage it will not run

There is no eighth stage. `CHALLENGER_DECISION` emits a decision and stops:

    GO means "a person may now start a training run", not "a training run
    started".

A pipeline that trains on its own GO is a pipeline whose output nobody chose.
The whole point of `scripts/ml/lifecycle.py` is that being BUILT is not
evidence of being BETTER and being better is not authority to SHIP; a stage
that fired the trainer would collapse the first of those two inside one
function call. `assert_no_training_side_effect` is the test that says so, and
it fails if this module ever imports a trainer.

## Dry run is the default

`--issue` is required to write anything into `core/ml/`. Same contract as
`train_review.py`, for the same reason: the expensive, hard-to-reverse thing is
writing an immutable evaluation dataset, and the default should be the one that
tells you what would happen.

## Fixtures are synthetic and stay that way

`--fixtures` runs the whole chain on generated data so the wiring is provable
today. Those fixtures carry a `TEST_` batch id, and two guards keep them apart
from real work: fixture mode refuses to write into `core/ml/`, and production
mode refuses a batch whose id starts with `TEST_`. Mixing them would produce an
evaluation dataset containing invented human labels, which is the single worst
artefact this repository could generate.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))

from human_eval import EvaluationError, build_eval, evaluate, write_eval  # noqa: E402
from review_batch import (  # noqa: E402
    BATCH_ID,
    REVIEW_QUESTIONS,
    BatchContractError,
    assert_authoritative,
    check_contract,
)

#: The stages, in order. Named so a failure report can say which one.
STAGES = (
    "IMPORT", "VALIDATE", "ADJUDICATE", "BUILD_EVAL",
    "BASELINE_EVALUATE", "ERROR_ANALYSIS", "CHALLENGER_DECISION",
)

#: Prefix marking a batch that exists only to exercise this code.
FIXTURE_PREFIX = "TEST_"

#: Minimum reviewed rows before a precision/recall figure is quoted as a
#: reason to build anything.
#:
#: Not a statistical threshold dressed up as one — it is a floor below which
#: the estimate's own confidence interval spans most of the unit interval, so
#: "the baseline is at 0.62" and "the baseline is at 0.30" are the same
#: measurement. The estimator already reports when a stratum has n=1; this
#: stops the DECISION stage from reading a number the estimator disclaimed.
MIN_REVIEWED_ROWS = 30

#: Agreement below which the labels describe the reviewers rather than the
#: content, so an error analysis built on them targets noise.
MIN_AGREEMENT = 0.60


class PipelineError(RuntimeError):
    """A pipeline run that would produce a number nobody should act on."""


def error_analysis(metrics: dict[str, Any], dataset: dict[str, Any]) -> dict[str, Any]:
    """Where the baseline is wrong, and whether a model could fix it.

    This is the stage `train_review.py` is waiting on: its `error_targeted`
    strategy refuses to sample until somebody can say which errors matter, and
    "which errors matter" is what this computes. It deliberately separates two
    kinds of error, because only one of them is a modelling problem:

    * a MISS (false negative) is content a reviewer called defective and no
      rule fired on. That is a gap in the rules and a candidate for a model.
    * a FALSE ALARM (false positive) is a rule firing on content a reviewer
      called fine. That is a rule that is too broad, and the cheapest fix is
      usually to narrow the rule, not to train anything.

    A pipeline that reported one number would send both to the same place.
    """
    per_question = metrics["per_question"]
    misses, alarms, silent = [], [], []

    for question, row in sorted(per_question.items()):
        answered = row["tp"] + row["fp"] + row["fn"] + row["tn"]
        if not row["rules_mapped"]:
            # No rule maps to this question at all. Every defect a reviewer
            # finds here is invisible to the baseline by construction, and no
            # amount of tuning changes that.
            silent.append({
                "question": question,
                "defects_found_by_humans": row["tp"] + row["fn"],
                "answered": answered,
                "note": (
                    "No baseline rule maps to this question. The rules cannot "
                    "be wrong here because they do not speak; this is a "
                    "coverage gap, not an accuracy one."
                ),
            })
            continue
        if row["fn"]:
            misses.append({
                "question": question,
                "count": row["fn"],
                "share_of_defects": _share(row["fn"], row["tp"] + row["fn"]),
                "rules_mapped": row["rules_mapped"],
                "recall": row["recall"],
            })
        if row["fp"]:
            alarms.append({
                "question": question,
                "count": row["fp"],
                "share_of_firings": _share(row["fp"], row["tp"] + row["fp"]),
                "rules_mapped": row["rules_mapped"],
                "precision": row["precision"],
            })

    misses.sort(key=lambda r: (-r["count"], r["question"]))
    alarms.sort(key=lambda r: (-r["count"], r["question"]))
    reviewed = len(dataset["rows"])

    return {
        "reviewed_rows": reviewed,
        "misses": misses,
        "false_alarms": alarms,
        "silent_questions": silent,
        "unmapped_check_families": metrics.get("unmapped_check_families", []),
        "targets_for_a_challenger": [m["question"] for m in misses[:3]],
        "cheaper_than_a_model": [
            a["question"] for a in alarms
            if a["precision"] is not None and a["precision"] < 0.5
        ],
        "scope": (
            "Computed from the holdout review only. It says where the baseline "
            "is wrong on 180 sampled rows, NOT where it is wrong on the "
            "catalogue -- the sample is stratified towards flagged rows, so "
            "false alarms are over-represented by design and their raw count "
            "is not a catalogue rate."
        ),
    }


def _share(part: int, whole: int) -> float | None:
    return None if not whole else round(part / whole, 4)


def challenger_decision(
    analysis: dict[str, Any],
    metrics: dict[str, Any],
    dataset: dict[str, Any],
) -> dict[str, Any]:
    """GO or NO-GO on BUILDING a challenger. Never on shipping one, never automatic.

    Every NO-GO carries the specific thing that is missing, because a decision
    that says "not yet" without saying what would change it is a decision
    nobody can act on.
    """
    blockers: list[str] = []
    reviewed = analysis["reviewed_rows"]

    if reviewed < MIN_REVIEWED_ROWS:
        blockers.append(
            f"{reviewed} reviewed rows, below the floor of {MIN_REVIEWED_ROWS}. "
            "Under it the estimate's interval spans most of the unit interval, "
            "so a measured difference between the baseline and a challenger "
            "would not be a difference"
        )

    agreed = (dataset["agreement"] or {})["percent_agreement"]
    if agreed is not None and agreed < MIN_AGREEMENT:
        blockers.append(
            f"double-reviewed agreement is {agreed:.2f}, below "
            f"{MIN_AGREEMENT}. Labels the reviewers disagree about describe "
            "the reviewers, and a model trained to reproduce them learns the "
            "disagreement"
        )

    unresolved = dataset["adjudication_counts"].get("UNRESOLVED", 0)
    if unresolved:
        blockers.append(
            f"{unresolved} rows are UNRESOLVED. A disagreement nobody settled "
            "has no ground truth, so it cannot be scored either way"
        )

    if not analysis["misses"] and not analysis["silent_questions"]:
        blockers.append(
            "the baseline missed nothing in this sample and no question is "
            "unmapped. There is no measured gap for a challenger to close, so "
            "building one would be optimising an unobserved problem"
        )

    verdict = "NO_GO" if blockers else "GO"
    return {
        "verdict": verdict,
        "blockers": blockers,
        "targets": analysis["targets_for_a_challenger"] if verdict == "GO" else [],
        "prefer_rule_change_over_a_model": analysis["cheaper_than_a_model"],
        "authorises": (
            "A person may start ONE training run against the TRAIN split, "
            "targeting the questions listed above. Its manifest must validate "
            "against scripts/ml/training_run.py and its lifecycle state on "
            "completion is TRAINED -- which is not CHALLENGER and not CHAMPION."
            if verdict == "GO" else
            "Nothing. This is a NO-GO and the blockers above are what would "
            "change it."
        ),
        "does_not_authorise": (
            "Deployment, promotion, shadow running, or any change to what the "
            "app serves. CT != CD. No stage of this pipeline may start a "
            "training run: a pipeline that trains on its own GO produces a "
            "model nobody chose."
        ),
        "baseline_measured": {
            "flagged_precision": metrics.get("BATCH_METRIC", {}).get("precision"),
            "flagged_recall": metrics.get("BATCH_METRIC", {}).get("recall"),
            "note": (
                "Batch metrics, not catalogue rates. The batch is stratified "
                "towards flagged rows."
            ),
        },
    }


def run(
    batch: dict[str, Any],
    submissions: list[dict[str, Any]],
    sealed: dict[str, list[str]],
    *,
    assignments: dict[str, Any],
    adjudications: list[dict[str, Any]] | None = None,
    out: Path | None = None,
    fixture: bool = False,
) -> dict[str, Any]:
    """The whole chain. Writes only when `out` is given."""
    manifest = batch["manifest"]
    is_test = str(manifest.get("batch_id", "")).startswith(FIXTURE_PREFIX)

    if fixture and not is_test:
        raise PipelineError(
            f"fixture mode was asked to run batch {manifest.get('batch_id')!r}, "
            "which is not a fixture. Synthetic reviewers must never touch a "
            "real batch: the output would be an evaluation dataset of invented "
            "human labels, indistinguishable from the real thing"
        )
    if not fixture and is_test:
        raise PipelineError(
            f"batch {manifest.get('batch_id')!r} is a fixture and this is a "
            "production run. Its labels are generated, not reviewed"
        )
    if fixture and out is not None and _inside(out, REPO / "core" / "ml"):
        raise PipelineError(
            f"fixture output would be written to {out}, inside core/ml/. "
            "Fixtures never land where real datasets live -- a directory "
            "listing is the last thing between a generated label and somebody "
            "citing it"
        )
    if not fixture:
        check_contract(manifest)
        assert_authoritative(manifest)

    stages: list[dict[str, Any]] = []

    # IMPORT + VALIDATE + ADJUDICATE + BUILD_EVAL. Kept as one call rather than
    # unpicked into four: build_eval already sequences them and duplicating
    # that order here would create a second place for it to drift.
    try:
        dataset = build_eval(
            batch, submissions,
            assignments=assignments, adjudications=adjudications,
            accepts=("SYNTHETIC",) if fixture else ("HUMAN",),
        )
    except (EvaluationError, BatchContractError) as exc:
        return _halted("BUILD_EVAL", exc, stages)
    for name in ("IMPORT", "VALIDATE", "ADJUDICATE", "BUILD_EVAL"):
        stages.append({"stage": name, "status": "OK"})
    stages[-1]["rows"] = len(dataset["rows"])

    metrics = evaluate(dataset, sealed)
    stages.append({"stage": "BASELINE_EVALUATE", "status": "OK"})

    analysis = error_analysis(metrics, dataset)
    stages.append({
        "stage": "ERROR_ANALYSIS", "status": "OK",
        "misses": len(analysis["misses"]),
        "false_alarms": len(analysis["false_alarms"]),
        "silent_questions": len(analysis["silent_questions"]),
    })

    decision = challenger_decision(analysis, metrics, dataset)
    stages.append({
        "stage": "CHALLENGER_DECISION", "status": "OK",
        "verdict": decision["verdict"],
    })

    written = None
    if out is not None:
        target = write_eval(dataset, out)
        for name, payload in (("baseline_metrics", metrics),
                              ("error_analysis", analysis),
                              ("challenger_decision", decision)):
            (target / f"{name}.json").write_text(
                json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True)
                + "\n", encoding="utf-8",
            )
        written = str(target)

    return {
        "stages": stages,
        "halted_at": None,
        "dataset": dataset,
        "metrics": metrics,
        "analysis": analysis,
        "decision": decision,
        "written": written,
        "dry_run": out is None,
        "fixture": fixture,
    }


def _inside(path: Path, parent: Path) -> bool:
    try:
        path.resolve().relative_to(parent.resolve())
        return True
    except ValueError:
        return False


def _halted(stage: str, exc: Exception, stages: list[dict[str, Any]]) -> dict[str, Any]:
    """A refusal is a result, not a crash. It is recorded with its stage."""
    stages.append({"stage": stage, "status": "HALTED", "reason": str(exc)})
    return {
        "stages": stages,
        "halted_at": stage,
        "dataset": None, "metrics": None, "analysis": None,
        "decision": {
            "verdict": "NO_GO",
            "blockers": [f"the pipeline halted at {stage}: {exc}"],
            "targets": [],
            "authorises": "Nothing.",
        },
        "written": None,
    }


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--batch", help="a built review batch directory")
    ap.add_argument("--submission", action="append", default=[])
    ap.add_argument("--adjudications", default=None)
    ap.add_argument("--fixtures", action="store_true",
                    help="run end to end on generated data (writes nothing)")
    ap.add_argument("--issue", metavar="DIR",
                    help="write the evaluation dataset and reports here")
    args = ap.parse_args(argv)

    if args.fixtures:
        from fixtures import synthetic_run  # noqa: E402
        if args.issue:
            print("--fixtures never writes. Refusing --issue.", file=sys.stderr)
            return 2
        material = synthetic_run()
        result = run(
            material["batch"], material["submissions"], material["sealed"],
            assignments=material["assignments"], fixture=True,
        )
    else:
        if not args.batch:
            print("--batch or --fixtures is required", file=sys.stderr)
            return 2
        batch_dir = Path(args.batch)
        batch = {
            "manifest": json.loads(
                (batch_dir / "manifest.json").read_text(encoding="utf-8")),
            "items": json.loads(
                (batch_dir / "items.json").read_text(encoding="utf-8")),
        }
        if not args.submission:
            print(
                "BLOCKER = HUMAN_REVIEW_LABELS_REQUIRED\n"
                f"  {BATCH_ID} is built and no review has come back. Every\n"
                "  stage after IMPORT would measure the baseline against\n"
                "  itself. Run --fixtures to exercise the chain instead.",
                file=sys.stderr,
            )
            return 2
        result = run(
            batch,
            [json.loads(Path(p).read_text(encoding="utf-8"))
             for p in args.submission],
            json.loads(
                (batch_dir / "sealed_baseline_labels.json").read_text("utf-8")),
            assignments=json.loads(
                (batch_dir / "assignments.json").read_text("utf-8")),
            adjudications=(
                json.loads(Path(args.adjudications).read_text(encoding="utf-8"))
                if args.adjudications else None),
            out=Path(args.issue) if args.issue else None,
        )

    for record in result["stages"]:
        extra = {k: v for k, v in record.items() if k not in ("stage", "status")}
        print(f"  {record['status']:7} {record['stage']:20} "
              f"{extra if extra else ''}")

    decision = result["decision"]
    print(f"\n  {decision['verdict']}")
    for blocker in decision["blockers"]:
        print(f"    - {blocker}")
    if decision["targets"]:
        print(f"    targets: {decision['targets']}")
    print(f"\n  {decision['authorises']}")
    if result.get("dry_run"):
        print("\n  DRY RUN -- nothing written. Pass --issue DIR to write.")
    return 0 if decision["verdict"] == "GO" else 1


if __name__ == "__main__":
    raise SystemExit(main())
