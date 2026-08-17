# -*- coding: utf-8 -*-
"""CT-1 — the evaluation dataset, and the only honest way to report a rate.

    python scripts/ct1/human_eval.py --batch core/ml/review/ct1_review_batch_002 \
        --submission <file.json> [--submission <file.json> ...]
    python -m pytest scripts/ct1/test_human_eval.py -q

Two things live here because they must not drift apart.

## 1. ``CT1_HUMAN_EVAL_V1`` — an immutable, versioned evaluation set

Built from adjudicated human review, carrying its own provenance: the batch it
came from, the commit, the catalogue digests, the review schema, which rows
were included and — the part usually missing — which rows were EXCLUDED and
why. A dataset that lists only what it contains cannot be audited for selection
bias, because the rows somebody dropped are exactly the ones worth knowing
about.

Never overwritten. Section 15: a correction produces V2 with a stated diff, so
that a metric quoted last month still refers to something that exists. The
builder refuses to write over an existing version rather than asking.

## 2. The estimator, because ``bad / 180`` is not a defect rate

The batch is deliberately non-representative: it takes every flagged holdout row
and a minority of the unflagged ones, because a random draw would say nothing
about what the rules MISS. That design is what makes the batch worth reviewing
and what makes its raw percentages meaningless as prevalence — the flagged
stratum is over-represented by roughly seven to one.

So three numbers, named differently on purpose:

* ``BATCH METRIC`` — a raw count over the reviewed rows. True, and about these
  rows only.
* ``HOLDOUT ESTIMATE`` — stratum rates re-weighted by the holdout population,
  with a standard error. The flagged stratum was sampled exhaustively, so it
  contributes no sampling variance at all; nearly all of the uncertainty comes
  from the 124-of-330 unflagged sample, which is the honest picture.
* ``CATALOGUE RATE`` — not produced. Getting from the holdout to the catalogue
  needs an assumption this module will not make silently; the field is present
  and null, with the assumption written out, so its absence is a statement
  rather than an omission.
"""
from __future__ import annotations

import argparse
import collections
import json
import math
import sys
from pathlib import Path
from typing import Any, Iterable

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_dataset import DATA, REPO, file_digest, git_commit, source_ref  # noqa: E402
from label_contract import Label  # noqa: E402
from review_batch import REVIEW_QUESTIONS, REVIEW_SCHEMA_VERSION  # noqa: E402
from review_import import adjudicate, import_reviews  # noqa: E402

DATASET_ID = "CT1_HUMAN_EVAL"

#: Which review question a baseline check family is EVIDENCE about.
#:
#: Stated as a mapping rather than assumed, because the two vocabularies were
#: designed for different purposes and a silent join between them is how a
#: precision figure ends up comparing a rule to a question it never addressed.
#: A family with no defensible question is UNMAPPED and is excluded from
#: per-question metrics — counted, not dropped, so the gap is visible.
CHECK_TO_QUESTION = {
    "duplicate_id": "content_is_not_duplicated",
    "duplicate_title": "content_is_not_duplicated",
    "duplicate_summary": "content_is_not_duplicated",
    "duplicate_steps_block": "content_is_not_duplicated",
    "dangling_equipment_ref": "equipment_matches_content",
    "locale_row_missing": "localisation_is_faithful",
    "locale_row_orphan": "localisation_is_faithful",
    "locale_field_missing": "localisation_is_faithful",
    "locale_field_orphan": "localisation_is_faithful",
    "locale_value_identical": "localisation_is_faithful",
    # No question asks whether a contraindication tag is a known one. A
    # reviewer cannot judge it from the row, and inventing a question that
    # could would be asking a content reviewer about clinical vocabulary.
    "unknown_contraindication_tag": None,
}


class EvaluationError(RuntimeError):
    """A metric that would be wrong in a way its reader could not detect."""


def _family(check: str) -> str:
    return check.split(":", 1)[0]


def build_eval(
    batch: dict[str, Any],
    submissions: list[dict[str, Any]],
    *,
    assignments: dict[str, Any] | None = None,
    adjudications: list[dict[str, Any]] | None = None,
    version: int = 1,
) -> dict[str, Any]:
    """The immutable evaluation dataset, plus everything needed to audit it."""
    manifest = batch["manifest"]
    per_reviewer: dict[str, list[Label]] = {}
    coverage: dict[str, Any] = {}
    stale: list[dict[str, Any]] = []
    domain: set[str] = set()
    reasons: dict[str, list[str]] = {}

    for submission in submissions:
        result = import_reviews(submission, batch, assignments=assignments)
        who = result["reviewer"]
        if who in per_reviewer:
            raise EvaluationError(
                f"two submissions from {who!r}. A reviewer who submitted twice "
                "has either revised or duplicated, and the file cannot say "
                "which"
            )
        per_reviewer[who] = result["labels"]
        coverage[who] = result["coverage"]
        stale.extend(result["stale"])
        domain.update(result["needs_domain_review"])
        reasons.update(result["reason_codes"])

    if not any(per_reviewer.values()):
        raise EvaluationError(
            "no human labels. EVALUATION_LABEL_GAP is still OPEN and every "
            "metric derivable from this state would measure the baseline "
            "against itself"
        )

    verdicts = adjudicate(
        per_reviewer, adjudications=adjudications, domain_review=domain
    )

    #: Only settled answers become evaluation truth. A disagreement nobody
    #: ruled on is not a label with a caveat; it is not a label.
    USABLE = {"AGREE", "ADJUDICATED", "SINGLE"}
    included: dict[str, dict[str, bool]] = collections.defaultdict(dict)
    excluded: list[dict[str, Any]] = []
    for record in verdicts["states"].values():
        if record["state"] in USABLE:
            included[record["item_id"]][record["check"]] = record["value"]
        else:
            excluded.append({
                "item_id": record["item_id"],
                "check": record["check"],
                "state": record["state"],
                "reason": {
                    "DISAGREE_UNADJUDICATED": "two reviewers disagreed and no "
                                              "third has ruled",
                    "UNRESOLVED": "adjudication was attempted and reached no "
                                  "decision",
                    "NEEDS_DOMAIN_REVIEW": "routed out of content QA",
                }[record["state"]],
            })

    # A row is in the evaluation set only if EVERY question about it settled.
    # A partly settled row would silently answer "was anything wrong with this
    # row" with the questions that happened to agree.
    rows = {}
    partial = []
    for item_id, answers in sorted(included.items()):
        if set(answers) == set(REVIEW_QUESTIONS):
            rows[item_id] = answers
        else:
            partial.append({
                "item_id": item_id,
                "settled": sorted(answers),
                "unsettled": sorted(set(REVIEW_QUESTIONS) - set(answers)),
                "reason": "not every question about this row settled",
            })

    if not rows:
        raise EvaluationError(
            "no row settled on every question. There is nothing to evaluate "
            "against, and an evaluation set of zero rows must not be written "
            "as if it were a dataset"
        )

    reviewers = sorted(per_reviewer)
    payload = {
        "dataset_id": DATASET_ID,
        "version": version,
        "immutable": True,
        "batch_id": manifest["batch_id"],
        "review_schema_version": REVIEW_SCHEMA_VERSION,
        "split": manifest["split"],
        "source_commit": git_commit(),
        "batch_source_commit": manifest["source_commit"],
        "source": {
            "catalogue_en": source_ref(DATA / "exercises_vendor.json"),
            "sha256": {
                "catalogue_en": file_digest(DATA / "exercises_vendor.json"),
                "catalogue_ru": file_digest(DATA / "exercises_vendor.ru.json"),
            },
        },
        "questions": list(REVIEW_QUESTIONS),
        "reviewer_count": len(reviewers),
        "reviewers": reviewers,
        "reviewer_kind": "HUMAN (a claim recorded at import; see review_batch)",
        "rows": rows,
        "reason_codes": {k: reasons[k] for k in sorted(reasons) if k in rows},
        "row_count": len(rows),
        "adjudication_counts": verdicts["counts"],
        "coverage": coverage,
        "excluded": excluded,
        "excluded_partial_rows": partial,
        "stale": stale,
        "needs_domain_review": sorted(domain),
        "stratification": manifest["sampling"],
        "strata": {
            "flagged": {
                "population": manifest["flagged_available"],
                "sampled": manifest["flagged_selected"],
            },
            "unflagged": {
                "population": manifest["unflagged_available"],
                "sampled": manifest["unflagged_selected"],
            },
        },
        "holdout_population": manifest["holdout_rows"],
        "use": (
            "EVALUATION ONLY. Every row here is a holdout row. Training on it "
            "destroys the only evaluation this project has; leakage_guard "
            "refuses labels carrying split=holdout for exactly this reason."
        ),
    }
    return payload


def write_eval(payload: dict[str, Any], root: Path) -> Path:
    """Write a version, refusing to replace one.

    Section 15. The refusal is the feature: an evaluation set that can be
    edited in place means a number quoted in a report last month refers to
    something that no longer exists, and nobody can tell.
    """
    target = root / f"{DATASET_ID.lower()}_v{payload['version']}"
    if target.exists():
        raise EvaluationError(
            f"{target} already exists. An evaluation dataset is immutable "
            f"after publication; a correction is v{payload['version'] + 1} "
            "with a stated diff, not an edit to this one"
        )
    target.mkdir(parents=True)
    (target / "dataset.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return target


def _rate(bad: int, n: int) -> float | None:
    return bad / n if n else None


def _stratified(strata: list[dict[str, Any]]) -> dict[str, Any]:
    """Population-weighted rate with a standard error.

    ``strata``: ``population``, ``sampled``, ``defective`` per stratum. Returns
    ``None`` for the estimate when any stratum with a non-zero population
    contributed no sampled rows — an unsampled stratum's rate is not zero, it is
    unknown, and averaging over the strata that happen to have data silently
    assumes the missing one looks like them.
    """
    total = sum(s["population"] for s in strata)
    if not total:
        return {"estimate": None, "reason": "no population"}
    for s in strata:
        if s["population"] and not s["sampled"]:
            return {
                "estimate": None,
                "reason": (
                    f"stratum {s['name']!r} has {s['population']} rows and none "
                    "were reviewed. Its rate is unknown, not zero"
                ),
            }
    estimate = 0.0
    variance = 0.0
    unestimated: list[str] = []
    for s in strata:
        w = s["population"] / total
        n, N = s["sampled"], s["population"]
        p = s["defective"] / n if n else 0.0
        estimate += w * p
        if n > 1:
            # Finite population correction. A stratum sampled exhaustively
            # (n == N) contributes zero variance because there is nothing left
            # unobserved in it -- which is the whole point of taking every
            # flagged row.
            fpc = 1 - n / N
            variance += (w ** 2) * fpc * p * (1 - p) / (n - 1)
        elif n == 1 and N > 1:
            # A single observation has no sample variance to compute -- the
            # estimator's denominator is n-1 -- so this stratum contributes
            # nothing to the standard error while contributing its full weight
            # to the estimate. That understates the uncertainty, and it is
            # recorded rather than absorbed: this module refuses to omit an
            # assumption silently for CATALOGUE_RATE and the same rule applies
            # here. Raised in gate review.
            unestimated.append(s["name"])
    se = math.sqrt(variance)
    out = {
        "estimate": estimate,
        "standard_error": se,
        "ci95": [max(0.0, estimate - 1.96 * se), min(1.0, estimate + 1.96 * se)],
        "strata": strata,
    }
    if unestimated:
        out["variance_understated"] = unestimated
        out["variance_note"] = (
            "The standard error EXCLUDES " + ", ".join(unestimated) + ": a "
            "stratum with one reviewed row has no estimable sample variance, "
            "so the interval below is narrower than the truth. Treat it as a "
            "lower bound on the uncertainty, not as the uncertainty."
        )
    return out


def evaluate(
    dataset: dict[str, Any], sealed: dict[str, list[str]]
) -> dict[str, Any]:
    """The baseline measured against human labels, with the rates named honestly."""
    rows = dataset["rows"]
    strata_def = dataset["strata"]

    flagged_ids = {i for i in rows if sealed.get(i)}
    stats: dict[str, Any] = {"per_question": {}}

    def row_is_bad(answers: dict[str, bool]) -> bool:
        # A row is defective if a reviewer said any dimension was a problem.
        # `False` is "problem" -- the label's value is "the answer was ok".
        return any(v is False for v in answers.values())

    tp = sum(1 for i in rows if i in flagged_ids and row_is_bad(rows[i]))
    fp = sum(1 for i in rows if i in flagged_ids and not row_is_bad(rows[i]))
    fn = sum(1 for i in rows if i not in flagged_ids and row_is_bad(rows[i]))
    tn = sum(1 for i in rows if i not in flagged_ids and not row_is_bad(rows[i]))

    for question in REVIEW_QUESTIONS:
        families = {f for f, q in CHECK_TO_QUESTION.items() if q == question}
        q_tp = q_fp = q_fn = q_tn = 0
        for item_id, answers in rows.items():
            if question not in answers:
                continue
            fired = any(_family(c) in families for c in sealed.get(item_id, []))
            bad = answers[question] is False
            q_tp += fired and bad
            q_fp += fired and not bad
            q_fn += (not fired) and bad
            q_tn += (not fired) and not bad
        stats["per_question"][question] = {
            "rules_mapped": sorted(families),
            "tp": q_tp, "fp": q_fp, "fn": q_fn, "tn": q_tn,
            "precision": _rate(q_tp, q_tp + q_fp),
            "recall": _rate(q_tp, q_tp + q_fn),
        }

    stats["unmapped_check_families"] = sorted(
        f for f, q in CHECK_TO_QUESTION.items() if q is None
    )

    # Defect prevalence, three ways, named so they cannot be confused.
    reviewed_flagged = len(flagged_ids)
    reviewed_unflagged = len(rows) - reviewed_flagged
    holdout_estimate = _stratified([
        {
            "name": "flagged",
            "population": strata_def["flagged"]["population"],
            "sampled": reviewed_flagged,
            "defective": tp,
        },
        {
            "name": "unflagged",
            "population": strata_def["unflagged"]["population"],
            "sampled": reviewed_unflagged,
            "defective": fn,
        },
    ])

    return {
        "dataset_id": dataset["dataset_id"],
        "dataset_version": dataset["version"],
        "rows_evaluated": len(rows),
        "confusion": {"tp": tp, "fp": fp, "fn": fn, "tn": tn},
        "precision": _rate(tp, tp + fp),
        "recall": _rate(tp, tp + fn),
        "precision_note": (
            "Every flagged holdout row was reviewed, so this precision is "
            "EXHAUSTIVE for the holdout split rather than a sample of it."
        ),
        "recall_note": (
            "Recall is estimated from the unflagged sample and inherits its "
            "uncertainty; see holdout_estimate.standard_error."
        ),
        "BATCH_METRIC": {
            "defect_rate": _rate(tp + fn, len(rows)),
            "meaning": (
                "Defective rows / reviewed rows. Describes THESE rows. The "
                "batch over-samples flagged rows roughly sevenfold by design, "
                "so this number is not prevalence and must never be quoted as "
                "one."
            ),
        },
        "HOLDOUT_ESTIMATE": {
            **holdout_estimate,
            "meaning": (
                "Stratum rates re-weighted by the holdout population "
                f"({dataset['holdout_population']} rows). This is a defect "
                "rate for the holdout split."
            ),
        },
        "CATALOGUE_RATE": {
            "estimate": None,
            "reason": (
                "Not produced. The holdout is a deterministic hash of the row "
                "id, so it is content-independent and extrapolating to the "
                "catalogue is defensible -- but it is an ASSUMPTION (that the "
                "hash is unrelated to content quality, and that the training "
                "split has not been edited differently), and this module will "
                "not make it silently. State it and compute it deliberately, "
                "or quote the holdout estimate."
            ),
        },
        **stats,
    }


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--batch", required=True)
    ap.add_argument("--submission", action="append", default=[])
    ap.add_argument("--adjudications", default=None)
    ap.add_argument("--version", type=int, default=1)
    ap.add_argument("--out", default=str(REPO / "core" / "ml" / "datasets"))
    args = ap.parse_args(argv)

    batch_dir = Path(args.batch)
    batch = {
        "manifest": json.loads((batch_dir / "manifest.json").read_text("utf-8")),
        "items": json.loads((batch_dir / "items.json").read_text("utf-8")),
    }
    assignments = json.loads((batch_dir / "assignments.json").read_text("utf-8"))
    sealed = json.loads(
        (batch_dir / "sealed_baseline_labels.json").read_text("utf-8")
    )
    if not args.submission:
        print(
            "BLOCKER = HUMAN_REVIEW_LABELS_REQUIRED\n"
            "  no submissions given. EVALUATION_LABEL_GAP stays OPEN; there is\n"
            "  no metric to compute that would not be the baseline measuring\n"
            "  itself."
        )
        return 2

    submissions = [
        json.loads(Path(p).read_text(encoding="utf-8")) for p in args.submission
    ]
    adjudications = (
        json.loads(Path(args.adjudications).read_text(encoding="utf-8"))
        if args.adjudications else None
    )
    payload = build_eval(
        batch, submissions, assignments=assignments,
        adjudications=adjudications, version=args.version,
    )
    target = write_eval(payload, Path(args.out))
    metrics = evaluate(payload, sealed)
    (target / "baseline_metrics.json").write_text(
        json.dumps(metrics, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"{payload['dataset_id']} v{payload['version']}  "
          f"{payload['row_count']} rows  -> {target}")
    print(f"  precision {metrics['precision']}  recall {metrics['recall']}")
    print(f"  BATCH METRIC     {metrics['BATCH_METRIC']['defect_rate']}")
    print(f"  HOLDOUT ESTIMATE {metrics['HOLDOUT_ESTIMATE']['estimate']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
