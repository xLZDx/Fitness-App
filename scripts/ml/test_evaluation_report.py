# -*- coding: utf-8 -*-
"""The registry-to-report check, and the ways it could be worth nothing.

    python -m pytest scripts/ml/test_evaluation_report.py -q

A checker that cannot read its sources reports no drift, which looks exactly
like a clean bill of health. So the cases below are weighted toward proving the
opposite: that it finds drift when drift exists, that it says so out loud when
it cannot read something, and that it never reports a claim it failed to locate
as verified.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from evaluation_report import (  # noqa: E402
    NOT_A_METRIC,
    REGISTRY,
    VERDICTS,
    WINDOW,
    audit,
    check_claim,
    claims_of,
    locate,
)


# ----------------------------------------------------------------- locate
def test_a_prose_report_states_its_number():
    assert locate("**top-1 = 0.617, top-3 = 0.835** (n=261)", "top_3", 0.835)
    assert locate("**top-1 = 0.617, top-3 = 0.835** (n=261)", "top_1", 0.617)


def test_a_percentage_is_the_same_claim_as_a_ratio():
    assert locate("top-3 accuracy on 18 labelled photos: 5/18 (28%)",
                  "top_3", 0.28)


def test_a_leading_zero_is_optional():
    assert locate("top-3 = .835 on the holdout", "top_3", 0.835)


def test_a_different_number_is_not_the_claim():
    assert not locate("top-3 = 0.835", "top_3", 0.935)


def test_rounding_is_not_accepted():
    # `0.83` and `0.835` are different claims. A checker that accepts either
    # cannot see a drift into the third digit, which is exactly the size of
    # drift a hand-copied registry produces.
    assert not locate("top-3 = 0.83", "top_3", 0.835)


def test_the_number_must_be_near_its_name():
    # The gap is a LITERAL, not a multiple of WINDOW. Derived from WINDOW it
    # would scale with the thing under test and pass for any value of it --
    # a fixture guaranteeing its own outcome, which is the defect class this
    # programme has hit more than once. Caught here by a mutation that set
    # WINDOW to 100,000 and left this case green.
    far = "top-3 accuracy" + ("x" * 4000) + "0.835"
    assert not locate(far, "top_3", 0.835)


def test_the_window_is_tight_enough_to_mean_anything():
    # A window wide enough to span a document makes `locate` an unconditional
    # "does this number appear anywhere", which would call an unrelated 0.835
    # on another page a verified citation.
    assert 0 < WINDOW <= 400


def test_a_name_it_was_never_taught_is_not_guessed():
    # The module maps spellings, never meanings. `accuracy` may well BE the
    # top-1 number in some report; deciding that here would be inventing a
    # measurement mapping, which is the failure this whole programme guards.
    assert not locate("accuracy = 0.617", "top_1", 0.617)


# ------------------------------------------------------------ check_claim
def test_a_json_report_is_checked_by_key_not_by_text():
    src = json.dumps({"coverage": {"share": 0.443, "rows": 1887}})
    assert check_claim(src, True, "rows", 1887) == "MATCHES"
    assert check_claim(src, True, "rows", 1888) == "DRIFTED"


def test_a_json_key_the_report_does_not_have_is_not_locatable():
    src = json.dumps({"coverage": {"share": 0.443}})
    assert check_claim(src, True, "novel_defect_yield", 0.9) == "NOT_LOCATABLE"


def test_prose_that_names_the_metric_and_disagrees_is_DRIFT():
    assert check_claim("top-3 = 0.835", False, "top_3", 0.9) == "DRIFTED"


def test_prose_that_never_names_the_metric_is_NOT_LOCATABLE():
    # The distinction that stops this module crying wolf. A document that never
    # discusses a metric is not a document that contradicts it.
    assert check_claim("nothing relevant here", False, "top_3", 0.9) == (
        "NOT_LOCATABLE")


def test_a_null_is_not_a_claim():
    # `content_qa` carries `precision: null` deliberately -- EVALUATION_LABEL_GAP
    # -- and demanding a source for the absence of a number would be demanding
    # evidence of a negative.
    assert check_claim("", False, "precision", None) == "MATCHES"


def test_a_string_metric_is_not_silently_accepted():
    assert check_claim("anything", False, "verdict", "good") == "NOT_LOCATABLE"


# ------------------------------------------------------------- claims_of
def test_both_registry_shapes_are_read():
    nested = {"dataset": "x", "n": 261, "metrics": {"top_1": 0.617}}
    flat = {"dataset": "y", "rows": 1887, "coverage": 0.443}
    assert claims_of(nested) == {"n": 261, "top_1": 0.617}
    assert claims_of(flat) == {"rows": 1887, "coverage": 0.443}


def test_prose_fields_are_not_mistaken_for_measurements():
    ev = {"dataset": "x", "caveat": "an upper bound", "$note": "see below",
          "source": "a/b.md", "dataset_hash": "0955", "top_1": 0.5}
    assert claims_of(ev) == {"top_1": 0.5}
    for key in NOT_A_METRIC:
        assert key not in claims_of(ev)


# ----------------------------------------------------- the real registry
def test_the_real_registry_has_no_drift():
    result = audit()
    assert result["drifted"] == [], result["drifted"]


def test_the_audit_actually_read_something():
    # The control that makes the test above mean anything. If every claim came
    # back NOT_LOCATABLE, "no drift" would be true and worthless.
    result = audit()
    assert result["counts"]["MATCHES"] >= 10, result["counts"]


def test_both_consumers_contribute_claims():
    # The measured justification for a SHARED primitive rather than a
    # per-model check. If one of these ever stops appearing, the sharing is no
    # longer earned and this module should be reconsidered, not quietly kept.
    models = {f["model_id"] for f in audit()["findings"]}
    assert {"equipment_recognition", "content_qa"} <= models


def test_every_verdict_is_a_declared_one():
    assert {f["verdict"] for f in audit()["findings"]} <= set(VERDICTS)


def test_what_it_cannot_read_is_reported_rather_than_passed():
    # Seven claims are currently unreadable: five real-world confidence figures
    # written as Russian prose in the B1 measurement, and two whose names the
    # source spells differently (`abstained_of_30` vs "abstained ('none')",
    # `coverage` vs the report's `share`). None of them is drift, and none of
    # them is verified either. The module must say so.
    result = audit()
    assert result["unlocatable"], (
        "if this is empty the sources became readable, which is good -- update "
        "the expectation rather than deleting the case"
    )
    for f in result["unlocatable"]:
        assert f["verdict"] == "NOT_LOCATABLE"
        assert f["cited_report"]


def test_a_drifted_claim_is_caught(tmp_path):
    # The mutation, run as a test rather than by hand: take the real registry,
    # move one number, and require the audit to name it.
    payload = json.loads(REGISTRY.read_text(encoding="utf-8"))
    target = None
    for model in payload["models"]:
        for ev in model.get("evaluations") or []:
            if (ev.get("metrics") or {}).get("top_3") == 0.835:
                ev["metrics"]["top_3"] = 0.935
                target = model["model_id"]
    assert target, "the registry no longer contains the claim this case uses"

    moved = tmp_path / "MODEL_REGISTRY.json"
    moved.write_text(json.dumps(payload), encoding="utf-8")
    result = audit(moved)
    drifted = [f for f in result["drifted"] if f["metric"] == "top_3"]
    assert drifted, result["counts"]
    assert drifted[0]["claimed"] == 0.935


def test_a_missing_source_is_reported_as_missing_not_as_drift(tmp_path):
    payload = {"models": [{
        "model_id": "x",
        "evaluation_report": "no/such/report.json",
        "evaluations": [{"metrics": {"top_1": 0.5}}],
    }]}
    moved = tmp_path / "MODEL_REGISTRY.json"
    moved.write_text(json.dumps(payload), encoding="utf-8")
    result = audit(moved)
    assert result["counts"]["SOURCE_MISSING"] == 1
    assert result["counts"]["DRIFTED"] == 0


def test_an_evaluation_may_cite_its_own_source(tmp_path):
    # The scanner's real-world numbers come from the B1 measurement, not from
    # the model's README. Checking them against the README would have reported
    # a citation problem as a drift problem.
    report = tmp_path / "report.md"
    report.write_text("top-1 = 0.9", encoding="utf-8")
    payload = {"models": [{
        "model_id": "x",
        "evaluation_report": "mobile/assets/models/README.md",
        "evaluations": [{"source": "no/such/file.md",
                         "metrics": {"top_1": 0.9}}],
    }]}
    moved = tmp_path / "MODEL_REGISTRY.json"
    moved.write_text(json.dumps(payload), encoding="utf-8")
    result = audit(moved)
    assert result["findings"][0]["cited_report"] == "no/such/file.md"
    assert result["findings"][0]["verdict"] == "SOURCE_MISSING"


# --- the denominator-carrying key, and the six it must not also "fix" --------


def test_out_of_key_matches_the_fraction_the_source_writes():
    src = "abstained ('none'):                   10/30 (33%)"
    assert locate(src, "abstained_of_30", 10)


def test_out_of_key_does_not_accept_a_different_numerator():
    # The whole risk of a looser rule: `abstained` is present, `30` is present,
    # and a checker that stopped there would confirm a claim of ten against a
    # source that measured nine.
    src = "abstained ('none'):                   9/30 (30%)"
    assert not locate(src, "abstained_of_30", 10)


def test_out_of_key_does_not_accept_a_different_denominator():
    src = "abstained ('none'):                   10/29 (34%)"
    assert not locate(src, "abstained_of_30", 10)


def test_out_of_rule_needs_the_stem_near_the_fraction():
    # 10/30 alone is not evidence about abstention. WINDOW apart, so proximity
    # is what fails rather than absence.
    src = "abstained ('none'): see below" + ("." * 400) + "10/30"
    assert not locate(src, "abstained_of_30", 10)


def test_a_russian_metric_name_is_still_not_locatable():
    # core/ml/METRIC_PROVENANCE.md, cause 1. The value is right there; the name
    # is `уверенность`. A locator that matched this would have acquired a
    # translation table, which is a claim about meaning it is not entitled to
    # make. This test exists so that acquiring one is a deliberate act.
    src = "уверенность top-1: min 0.215 · медиана 0.437 · max 0.897"
    assert not locate(src, "confidence_median", 0.437)


def test_a_complement_is_not_located():
    # Cause 2. `30/30` passed, so zero were rejected -- true, and not stated.
    src = "пропущено фото-порогом    (0.10)     30/30  (100%)"
    assert not locate(src, "rejected_by_photo_threshold_0_10", 0)


def test_a_block_name_does_not_vouch_for_every_scalar_under_it():
    # Cause 3. Four numbers live under `coverage`; a claim of `coverage = 264`
    # must not pass just because 264 is one of them.
    src = json.dumps({"coverage": {"rows": 1887, "heuristic_flags": 264,
                                   "share": 0.443}})
    assert check_claim(src, True, "coverage", 264) == "NOT_LOCATABLE"


def test_the_audit_still_reports_the_six_it_cannot_read():
    # The number that must not quietly drop to zero: a future locator change
    # that "fixes" the remaining six has changed what this module means.
    result = audit()
    assert result["counts"]["NOT_LOCATABLE"] == 6
    assert result["counts"]["DRIFTED"] == 0
