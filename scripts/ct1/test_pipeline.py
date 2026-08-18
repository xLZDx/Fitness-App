# -*- coding: utf-8 -*-
"""The post-label pipeline: the stage it will not run, and the gates that can fire.

    python -m pytest scripts/ct1/test_pipeline.py -q

Two things a test suite around an orchestrator usually fails to prove, and both
are asserted here directly:

* that each GATE in the decision stage can actually fire. Two of them were dead
  on the first run — they read keys the dataset did not have, so they passed
  silently on every input. Every gate below is therefore tested by CONSTRUCTING
  the state that should trip it.
* that the synthetic material and the real material cannot meet.
"""
from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fixtures  # noqa: E402
from human_eval import EvaluationError, write_eval  # noqa: E402
from pipeline import (  # noqa: E402
    FIXTURE_PREFIX,
    MIN_AGREEMENT,
    MIN_REVIEWED_ROWS,
    REPO,
    STAGES,
    PipelineError,
    challenger_decision,
    error_analysis,
    run,
)
from review_import import ReviewImportError  # noqa: E402


@pytest.fixture(scope="module")
def synthetic():
    return fixtures.synthetic_run()


@pytest.fixture(scope="module")
def result(synthetic):
    return run(
        synthetic["batch"], synthetic["submissions"], synthetic["sealed"],
        assignments=synthetic["assignments"], fixture=True,
    )


# --------------------------------------------------------------------------
# the chain runs, and is provably not a stub
# --------------------------------------------------------------------------


def test_every_declared_stage_runs(result):
    """A pipeline that skipped a stage would still print a tidy report."""
    ran = [r["stage"] for r in result["stages"]]
    assert ran == list(STAGES)
    assert all(r["status"] == "OK" for r in result["stages"])
    assert result["halted_at"] is None


def test_the_chain_produces_real_material_not_empty_shells(result):
    """Each stage's own output is non-trivial, so "it ran" is not the whole
    claim. Without this, a stage returning {} would satisfy the test above."""
    assert result["dataset"]["rows"], "no settled rows"
    assert result["metrics"]["per_question"], "no per-question metrics"
    assert result["dataset"]["agreement"]["compared_answers"] > 0, (
        "no double-reviewed answers were compared, so the adjudication and "
        "agreement branches never executed and this run proves less than it "
        "appears to"
    )
    assert result["dataset"]["adjudication_counts"]["DISAGREE_UNADJUDICATED"] > 0, (
        "the synthetic reviewers never disagreed, so the branch that surfaces "
        "a disagreement was not exercised"
    )


def test_a_dry_run_writes_nothing(result):
    assert result["dry_run"] is True
    assert result["written"] is None


# --------------------------------------------------------------------------
# the eighth stage that does not exist
# --------------------------------------------------------------------------


def test_the_pipeline_cannot_start_a_training_run():
    """GO authorises a person to start one. It does not start one.

    Asserted against the module's actual IMPORT graph, parsed, rather than a
    substring search: the decision text legitimately names
    `scripts/ml/training_run.py` as the validator a future run must satisfy,
    and a text search cannot tell that sentence from an import. The first
    version of this test could not, and failed on its own subject's prose.
    """
    import ast

    source = (Path(__file__).resolve().parent / "pipeline.py").read_text("utf-8")
    imported = set()
    for node in ast.walk(ast.parse(source)):
        if isinstance(node, ast.Import):
            imported.update(a.name.split(".")[0] for a in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported.add(node.module.split(".")[0])
    for forbidden in ("train_review", "training_run", "torch", "subprocess",
                      "sklearn", "os"):
        assert forbidden not in imported, (
            f"the pipeline imports {forbidden!r}. GO authorises a person to "
            "start a training run; a pipeline that can start one itself "
            "produces a model nobody chose"
        )
    # And nothing is invoked dynamically to get around the import check.
    for node in ast.walk(ast.parse(source)):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
            assert node.func.id not in ("exec", "eval", "__import__")


def test_a_go_says_what_it_does_and_does_not_authorise(result):
    decision = result["decision"]
    assert decision["verdict"] in ("GO", "NO_GO")
    assert "TRAINED" in decision["authorises"] or decision["verdict"] == "NO_GO"
    assert "CT != CD" in decision["does_not_authorise"]
    assert "Deployment" in decision["does_not_authorise"]


def test_a_go_never_reaches_champion_or_challenger(result):
    """The two implications lifecycle.py exists to deny, restated at the one
    place a reader might expect a pipeline to promote something."""
    text = json.dumps(result["decision"])
    assert "CHAMPION" not in text.replace("not CHAMPION", "")
    assert "CHALLENGER" not in text.replace("not CHALLENGER", "")


# --------------------------------------------------------------------------
# every gate can fire -- two of them could not
# --------------------------------------------------------------------------


def _decide(result, **mutate):
    """Re-run the decision stage over a deliberately altered dataset."""
    dataset = copy.deepcopy(result["dataset"])
    analysis = copy.deepcopy(result["analysis"])
    for key, value in mutate.items():
        if key == "reviewed_rows":
            analysis["reviewed_rows"] = value
        elif key == "agreement":
            dataset["agreement"]["percent_agreement"] = value
        elif key == "unresolved":
            dataset["adjudication_counts"]["UNRESOLVED"] = value
        elif key == "no_gap":
            analysis["misses"] = []
            analysis["silent_questions"] = []
        else:
            raise AssertionError(key)
    return challenger_decision(analysis, result["metrics"], dataset)


def test_too_few_reviewed_rows_blocks(result):
    decision = _decide(result, reviewed_rows=MIN_REVIEWED_ROWS - 1)
    assert decision["verdict"] == "NO_GO"
    assert any("below the floor" in b for b in decision["blockers"])
    assert decision["targets"] == []


def test_low_agreement_blocks(result):
    """This gate was DEAD on first run: it read `dataset["agreement"]`, which
    build_eval did not produce, so it passed on every input including one where
    the reviewers agreed on nothing."""
    decision = _decide(result, agreement=MIN_AGREEMENT - 0.01)
    assert decision["verdict"] == "NO_GO"
    assert any("agreement" in b for b in decision["blockers"])


def test_agreement_exactly_at_the_floor_does_not_block(result):
    """Pins the comparison. A `<=` here would refuse work the threshold admits."""
    decision = _decide(result, agreement=MIN_AGREEMENT)
    assert not any("agreement" in b for b in decision["blockers"])


def test_unmeasured_agreement_does_not_block(result):
    """null is "no two reviewers saw the same row", not "they disagreed
    completely". A gate that conflated them would refuse every single-review
    batch for a reason that never happened."""
    decision = _decide(result, agreement=None)
    assert not any("agreement" in b for b in decision["blockers"])


def test_unresolved_disagreements_block(result):
    """Also dead on first run, for the same reason: it read an `adjudication`
    key that does not exist rather than `adjudication_counts`."""
    decision = _decide(result, unresolved=3)
    assert decision["verdict"] == "NO_GO"
    assert any("UNRESOLVED" in b for b in decision["blockers"])


def test_no_measured_gap_blocks(result):
    """A challenger with nothing to close is optimisation against an unobserved
    problem. The baseline being good is a NO-GO, not a GO."""
    decision = _decide(result, no_gap=True)
    assert decision["verdict"] == "NO_GO"
    assert any("no measured gap" in b or "missed nothing" in b
               for b in decision["blockers"])


def test_the_unmodified_run_passes_every_gate(result):
    """Otherwise the six tests above are satisfied by a function that always
    returns NO_GO."""
    assert result["decision"]["verdict"] == "GO"
    assert result["decision"]["blockers"] == []
    assert result["decision"]["targets"]


# --------------------------------------------------------------------------
# error analysis separates the two kinds of error
# --------------------------------------------------------------------------


def test_misses_and_false_alarms_are_not_pooled(result):
    """A miss is a modelling problem; a false alarm is usually a rule that is
    too broad. One number would send both to the same place."""
    analysis = result["analysis"]
    assert set(analysis) >= {"misses", "false_alarms", "silent_questions"}
    for miss in analysis["misses"]:
        assert miss["count"] > 0
        assert miss["rules_mapped"], "a miss needs a rule that should have fired"


def test_a_question_no_rule_maps_to_is_a_coverage_gap_not_an_accuracy_one(result):
    """The baseline cannot be wrong where it does not speak, and reporting it
    as 0.0 precision would send somebody to tune a rule that does not exist."""
    silent = result["analysis"]["silent_questions"]
    assert silent, "no unmapped question in this fixture, so this proves nothing"
    for entry in silent:
        assert "coverage gap" in entry["note"]
    for miss in result["analysis"]["misses"]:
        assert miss["question"] not in {s["question"] for s in silent}


def test_targets_come_from_misses_and_are_bounded(result):
    analysis = result["analysis"]
    assert analysis["targets_for_a_challenger"] == \
        [m["question"] for m in analysis["misses"][:3]]


def test_the_analysis_states_that_its_counts_are_not_catalogue_rates(result):
    """The batch is stratified towards flagged rows, so a raw false-alarm count
    is not a rate anybody may quote about the catalogue."""
    assert "not a catalogue rate" in result["analysis"]["scope"]


# --------------------------------------------------------------------------
# synthetic and real must never meet
# --------------------------------------------------------------------------


def test_a_fixture_batch_is_visibly_a_fixture(synthetic):
    manifest = synthetic["batch"]["manifest"]
    assert manifest["batch_id"].startswith(FIXTURE_PREFIX)
    assert manifest["synthetic"] is True
    for submission in synthetic["submissions"]:
        assert submission["reviewer_kind"] == "SYNTHETIC"
        assert submission["reviewer"].startswith("synthetic.")


def test_fixture_mode_refuses_a_real_batch(synthetic):
    """The worst artefact this repository could produce is an evaluation
    dataset of invented human labels. It would look exactly like the real one."""
    batch = copy.deepcopy(synthetic["batch"])
    batch["manifest"]["batch_id"] = "CT1_REVIEW_BATCH_003"
    with pytest.raises(PipelineError, match="not a fixture"):
        run(batch, synthetic["submissions"], synthetic["sealed"],
            assignments=synthetic["assignments"], fixture=True)


def test_production_mode_refuses_a_fixture_batch(synthetic):
    with pytest.raises(PipelineError, match="is a fixture"):
        run(synthetic["batch"], synthetic["submissions"], synthetic["sealed"],
            assignments=synthetic["assignments"], fixture=False)


def test_fixture_output_may_not_be_written_inside_core_ml(synthetic):
    with pytest.raises(PipelineError, match="inside core/ml"):
        run(synthetic["batch"], synthetic["submissions"], synthetic["sealed"],
            assignments=synthetic["assignments"], fixture=True,
            out=REPO / "core" / "ml" / "datasets")


def test_a_synthetic_dataset_is_refused_by_the_writer_too(result, tmp_path):
    """Defence in depth, and not redundant: `write_eval` is reachable from
    `human_eval.py`'s own CLI, which never passes through the pipeline's
    guard."""
    assert result["dataset"]["synthetic"] is True
    write_eval(result["dataset"], tmp_path)              # outside core/ml: fine
    with pytest.raises(EvaluationError, match="inside core/ml"):
        write_eval(result["dataset"], REPO / "core" / "ml" / "datasets")


def test_a_real_import_still_refuses_a_synthetic_submission(synthetic):
    """The kind check is not an off switch. A production run rejects a
    SYNTHETIC submission exactly as it did before the kind existed."""
    from review_batch import BATCH_ID

    # The LIVE batch id, not merely a non-fixture one: production mode runs
    # assert_authoritative before it ever reaches the reviewer check, so any
    # other id would be refused for the wrong reason and this test would prove
    # nothing about reviewer_kind.
    batch = copy.deepcopy(synthetic["batch"])
    batch["manifest"]["batch_id"] = BATCH_ID
    submissions = copy.deepcopy(synthetic["submissions"])
    for s in submissions:
        s["batch_id"] = BATCH_ID
    with pytest.raises(ReviewImportError, match="reviewer_kind must be"):
        run(batch, submissions, synthetic["sealed"],
            assignments=synthetic["assignments"], fixture=False)


def test_an_import_may_not_accept_two_kinds_at_once(synthetic):
    """The guard that makes the kind parameter something other than a switch:
    a dataset holding one reviewed answer and one generated one could never be
    separated again."""
    from review_import import _check_accepts

    with pytest.raises(ReviewImportError, match="exactly one reviewer kind"):
        _check_accepts(("HUMAN", "SYNTHETIC"))
    with pytest.raises(ReviewImportError, match="exactly one reviewer kind"):
        _check_accepts(())
    with pytest.raises(ReviewImportError, match="not a reviewer kind"):
        _check_accepts(("PROBABLY_HUMAN",))


def test_the_dataset_records_what_it_was_built_from(result):
    """Without this stamp a synthetic dataset is shaped exactly like a real
    one, and the only thing separating them is which directory it sits in."""
    assert result["dataset"]["reviewer_kind"] == ["SYNTHETIC"]
    assert result["dataset"]["synthetic"] is True


def test_fixtures_are_deterministic():
    """A fixture that varies between runs makes a pipeline failure
    unreproducible, which is most of the point of having one."""
    a, b = fixtures.synthetic_run(), fixtures.synthetic_run()
    assert a["submissions"] == b["submissions"]
    assert [i["item_id"] for i in a["batch"]["items"]] == \
        [i["item_id"] for i in b["batch"]["items"]]


# --------------------------------------------------------------------------
# halting is a result, not a crash
# --------------------------------------------------------------------------


def test_a_halt_is_reported_with_its_stage_and_is_a_no_go(synthetic):
    """A pipeline that raised would leave the operator with a traceback and no
    verdict. A NO-GO with the reason attached is the useful shape."""
    submissions = copy.deepcopy(synthetic["submissions"])
    for s in submissions:
        for review in s["reviews"]:
            review["review_status"] = "SKIPPED"
            review["answers"] = {}
    result = run(synthetic["batch"], submissions, synthetic["sealed"],
                 assignments=synthetic["assignments"], fixture=True)
    assert result["halted_at"] == "BUILD_EVAL"
    assert result["decision"]["verdict"] == "NO_GO"
    assert result["stages"][-1]["status"] == "HALTED"
    assert result["decision"]["authorises"] == "Nothing."
