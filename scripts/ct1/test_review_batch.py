# -*- coding: utf-8 -*-
"""CT-1 review batch: blindness, sampling, and what an import refuses.

    python -m pytest scripts/ct1/test_review_batch.py -q

The tests that matter here are the refusals. A batch that leaks the machine's
answer, or an importer that accepts a machine's output as a reviewed label,
would both produce a corpus that looks correct and is a slightly noisier copy
of the rules it was supposed to check.
"""
from __future__ import annotations

import json
import random
import re

import pytest

from baseline import DATA, REPO, load
from label_contract import LabelSource
from review_batch import (
    BATCH_ID,
    BatchContractError,
    DOUBLE_REVIEW_SHARE,
    assert_authoritative,
    REVIEW_STATUSES,
    SCHEMA_VERSION,
    check_contract,
    REASON_CODES,
    REVIEW_QUESTIONS,
    REVIEW_SCHEMA_VERSION,
    SUPERSEDES,
    VERDICTS,
    assign,
    content_version,
    is_double,
    select,
)
from test_ct1 import EN, EQ, RU  # the same hand-written fixture


def _corpus(n: int = 400, dup_every: int = 2):
    """A corpus big enough that both strata are populated.

    One row in `dup_every` duplicates a shared summary, so `duplicate_summary`
    fires on that share — the flag family the shipped catalogue is also
    dominated by.

    `dup_every` is a parameter rather than a constant because at the default of
    2 the two strata come out the same size, and equal strata make a
    population-weighted estimate numerically identical to an unweighted mean.
    A test of the weighting then cannot fail, whatever the estimator does.
    Found by mutation, not by reading.
    """
    en = []
    ru = {}
    for i in range(n):
        rid = f"row{i:04d}"
        dup = i % dup_every == 1
        en.append({
            "id": rid,
            "title": f"Exercise {i}",
            "summary": "Shared summary." if dup else f"Summary {i}.",
            # Unique per row: identical steps everywhere would fire
            # `duplicate_steps_block` on the whole corpus and leave the
            # unflagged stratum empty, which is how the first version of this
            # fixture guaranteed the outcome it was meant to test.
            "steps": [f"Set up {i}", f"Move {i}"],
            "equipmentId": "bench",
            "contraindications": ["shoulder"],
            "tips": ["Brace"],
            "muscles": ["chest"],
            "primaryMuscles": ["chest"],
            "difficulty": "beginner",
            "vendorGroup": "Chest",
            "isStretch": False,
        })
        ru[rid] = {"title": f"Упражнение {i}", "summary": "Описание.",
                   "steps": ["Готовься", "Двигайся"], "tips": ["Напрягись"]}
    return en, ru, [{"id": "bench"}]


def _batch(size: int = 60):
    en, ru, eq = _corpus()
    return select(en, ru, eq, size=size)


# --------------------------------------------------------------------------
# blindness — the rule everything else is shaped by
# --------------------------------------------------------------------------

def test_the_batch_a_reviewer_opens_carries_no_machine_answer():
    """The whole design in one assertion.

    A reviewer who can see which rule fired is producing an agreement rate, not
    a label, and an agreement rate trained on is the feedback loop
    `label_contract` refuses at the training step. Refusing it there and then
    handing reviewers the machine's output would be refusing it in the one
    place it cannot happen.
    """
    batch = _batch()
    blob = json.dumps(batch["items"], ensure_ascii=False).lower()
    for forbidden in ("duplicate_", "flag", "label", "check", "score",
                      "baseline", "predict", "suspect", "issue"):
        assert forbidden not in blob, f"{forbidden!r} reached the blind batch"


def test_the_sealed_labels_exist_and_are_not_in_the_items():
    # Sealed rather than discarded: without them the batch could never be
    # evaluated against the rules it exists to measure.
    batch = _batch()
    assert batch["sealed"], "nothing sealed, so the batch is unevaluable"
    ids = {i["item_id"] for i in batch["items"]}
    assert set(batch["sealed"]) == ids
    assert any(v for v in batch["sealed"].values()), (
        "no sealed row carries a flag, so the fixture cannot exercise the "
        "flagged stratum"
    )


# --------------------------------------------------------------------------
# sampling
# --------------------------------------------------------------------------

def test_every_item_comes_from_the_holdout_split():
    from build_dataset import split_for
    batch = _batch()
    for item in batch["items"]:
        assert split_for(item["item_id"]) == "holdout", (
            "a reviewed label on a training row is usable as a target and "
            "unusable as evaluation; this batch exists to close the "
            "evaluation gap first"
        )


def test_both_strata_are_populated():
    # The reason the batch is not all-flagged. An all-flagged batch measures
    # precision and cannot, even in principle, discover a row the rules missed.
    m = _batch()["manifest"]
    assert m["flagged_selected"] > 0
    assert m["unflagged_selected"] > 0


def test_the_manifest_states_that_the_sample_is_not_random():
    m = _batch()["manifest"]
    assert m["blind"] is True
    assert "STRATIFIED" in m["sampling"]
    assert "must not be reported" in m["sampling"]


def test_selection_is_deterministic_and_stable_as_the_corpus_grows():
    """Hash-based, not a seeded shuffle.

    A seeded shuffle is reproducible for a fixed corpus and silently is not the
    moment a row is added — the same failure the dataset builder's split
    avoids, asserted the same way.
    """
    en, ru, eq = _corpus()
    first = [i["item_id"] for i in select(en, ru, eq, size=60)["items"]]
    again = [i["item_id"] for i in select(en, ru, eq, size=60)["items"]]
    assert first == again

    grown_en, grown_ru, _ = _corpus(500)
    grown = {i["item_id"] for i in select(grown_en, grown_ru, eq, size=60)["items"]}
    # Not "identical" -- a bigger corpus legitimately changes which rows are
    # picked. What must hold is that the pick is a function of the row's id, so
    # re-running on the same corpus is stable. Asserted above; here the weaker
    # claim that growth does not throw and still fills the batch.
    assert len(grown) == 60


# --------------------------------------------------------------------------
# assignment — who gets what, and what the package does not say
# --------------------------------------------------------------------------


def test_double_review_is_assigned_at_the_share_it_is_configured_for():
    """Pinned to the configured share, not merely to "a minority".

    "Fewer than half" was the assertion, and a mutation raising the share to
    50% still passed it -- the hash landed just under the line on this fixture,
    so the test's verdict was a coin flip rather than a measurement. Every item
    double-reviewed halves the corpus for the same effort; none leaves label
    quality unmeasurable. The share is the decision, so the share is what gets
    asserted.
    """
    batch = _batch()
    doubles = [i for i in batch["items"] if is_double(i["item_id"])]
    assert doubles, "nothing is double-reviewed, so agreement is unmeasurable"
    observed = len(doubles) / len(batch["items"])
    assert abs(observed - DOUBLE_REVIEW_SHARE) < 0.1, (
        f"{observed:.0%} double-reviewed against a configured "
        f"{DOUBLE_REVIEW_SHARE:.0%}"
    )


def test_no_item_a_reviewer_opens_says_it_is_double_reviewed():
    """The overlap rows must be indistinguishable from the rest.

    A reviewer who knows a row is also going to somebody else answers it
    differently -- more carefully, or less, but not the same -- and the
    agreement figure then measures the marking rather than the labelling.
    """
    batch = _batch()
    for item in batch["items"]:
        assert "double_review" not in item
        blob = json.dumps(item, ensure_ascii=False).lower()
        for word in ("double", "overlap", "second_reviewer", "agreement"):
            assert word not in blob, f"{item['item_id']} leaks {word!r}"


def test_every_item_has_exactly_one_primary_reviewer():
    batch = _batch()
    a = assign(batch["items"])
    assert set(a["primary"]) == {i["item_id"] for i in batch["items"]}
    # Every doubled row, and only a doubled row, has a second.
    assert set(a["secondary"]) == {
        i["item_id"] for i in batch["items"] if is_double(i["item_id"])
    }


def test_a_second_reviewer_is_never_the_first():
    """Otherwise 'double review' is one person answering twice."""
    batch = _batch()
    a = assign(batch["items"])
    for item_id, second in a["secondary"].items():
        assert second != a["primary"][item_id]


def test_packages_partition_the_work_and_cover_the_doubles():
    batch = _batch()
    a = assign(batch["items"])
    total = sum(len(v) for v in a["packages"].values())
    assert total == len(batch["items"]) + len(a["secondary"])
    for slot, ids in a["packages"].items():
        assert len(set(ids)) == len(ids), f"{slot} was dealt a row twice"


def test_assignment_is_reproducible_from_the_batch_alone():
    batch = _batch()
    assert assign(batch["items"]) == assign(batch["items"])


def test_double_review_needs_more_than_one_reviewer():
    batch = _batch()
    with pytest.raises(ValueError):
        assign(batch["items"], slots=("R1",))


# --------------------------------------------------------------------------
# the schema change that made this batch 002 rather than a new 001
# --------------------------------------------------------------------------


def test_the_batch_id_changed_with_the_review_schema():
    """Section 45: a material schema change gets a new batch id.

    Not because 001 had returned work to protect -- it had none -- but because
    the first time the rule is expensive is the time it gets waived.
    """
    batch = _batch()
    m = batch["manifest"]
    assert m["batch_id"] == BATCH_ID != SUPERSEDES
    assert m["supersedes"] == SUPERSEDES
    assert m["review_schema_version"] == REVIEW_SCHEMA_VERSION >= 2
    assert "SUPERSEDED_BEFORE_REVIEW" in m["supersession"]


def test_the_supersession_moved_the_rows_it_says_it_moved():
    """The claim in `SUPERSESSION`, checked rather than asserted in prose."""
    superseded = REPO / "core" / "ml" / "review" / SUPERSEDES.lower() / "items.json"
    # Asserted present rather than skipped. A test that quietly stops running
    # when its evidence disappears is a test that reports success for the one
    # state it exists to detect. Raised in gate review.
    assert superseded.exists(), (
        f"{superseded} is missing, so the supersession claim is unverifiable"
    )
    en, ru, eq = load(
        DATA / "exercises_vendor.json",
        DATA / "exercises_vendor.ru.json",
        DATA / "equipment.json",
    )
    rebuilt = {i["item_id"] for i in select(en, ru, eq)["items"]}
    before = {i["item_id"] for i in json.loads(superseded.read_text(encoding="utf-8"))}
    # 003 MOVED rows, deliberately -- see SUPERSESSION. What must hold is that
    # the move is the small, explained one and not a wholesale reshuffle, and
    # that the manifest says the rows changed rather than claiming they did not.
    assert rebuilt != before, "the supersession note says the rows moved"
    assert len(rebuilt ^ before) <= 4, (
        f"{len(rebuilt ^ before)} rows moved; the supersession note explains two"
    )


def test_every_item_carries_the_content_it_was_reviewed_at():
    batch = _batch()
    for item in batch["items"]:
        assert item["source_content_version"] == content_version(item)


def test_the_content_version_moves_when_reviewed_content_moves():
    """Otherwise section 12's staleness check cannot fire."""
    batch = _batch()
    item = dict(batch["items"][0])
    before = content_version(item)
    item["steps"] = list(item["steps"]) + ["and one more"]
    assert content_version(item) != before


def test_the_content_version_ignores_fields_no_reviewer_was_shown():
    batch = _batch()
    item = dict(batch["items"][0])
    before = content_version(item)
    item["some_internal_field_added_later"] = "irrelevant"
    assert content_version(item) == before


# --------------------------------------------------------------------------
# the questions, and the boundary they may not cross
# --------------------------------------------------------------------------


def test_no_question_asks_whether_an_exercise_is_safe():
    """Section 9 and 10. A content reviewer may not produce a clinical claim.

    Checked on the question NAMES, which is where the wording would have to
    appear for a reviewer to be asked it. `review_app` carries the prose and is
    scanned separately.
    """
    forbidden = ("safe", "risk", "injur", "contraindicat", "clinic", "danger",
                 "harm", "medical")
    for q in REVIEW_QUESTIONS:
        for word in forbidden:
            assert word not in q.lower(), f"question {q!r} contains {word!r}"


def test_the_questions_cover_the_dimensions_the_brief_named():
    dimensions = {
        "content_is_complete", "structure_is_consistent",
        "content_is_not_duplicated", "title_matches_content",
        "equipment_matches_content", "localisation_is_faithful",
        "instructions_are_consistent", "metadata_matches_content",
    }
    assert dimensions <= set(REVIEW_QUESTIONS)


def test_unsure_is_one_of_the_verdicts():
    """Forcing a verdict on a row nobody can assess manufactures a label."""
    assert "unsure" in VERDICTS
    assert "cannot_judge" not in VERDICTS


def test_the_reason_vocabulary_has_an_escape_hatch():
    """`other` is how an incomplete vocabulary shows up as a countable class
    rather than as reviewers forcing a near-miss code."""
    assert "other" in REASON_CODES


def test_reason_codes_do_not_name_a_baseline_rule():
    """A code named after a rule would tell a reviewer which rules exist and,
    row by row, invite them to look for that rule's subject."""
    families = {
        "duplicate_id", "duplicate_title", "duplicate_summary",
        "duplicate_steps_block", "dangling_equipment_ref",
        "unknown_contraindication_tag", "locale_row_missing",
        "locale_row_orphan", "locale_field_missing", "locale_field_orphan",
        "locale_value_identical",
    }
    assert families.isdisjoint(set(REASON_CODES))


def test_the_shared_fixture_is_the_one_the_other_suite_uses():
    assert EN and RU and EQ


def test_selection_does_not_depend_on_the_order_rows_arrive_in():
    """The assertion the determinism test above was missing.

    `first == again` is satisfied by a seeded shuffle called fresh each time,
    and so is "the batch is still full after the corpus grows" -- both were
    measured against `random.Random(seed).sample`, and both passed. Neither
    rules out the thing the docstring claims to rule out.

    Order-independence does. A seeded shuffle over a reordered list draws a
    different set; a selection that is a function of the row id cannot.
    """
    en, ru, eq = _corpus()
    straight = {i["item_id"] for i in select(en, ru, eq, size=60)["items"]}
    shuffled = list(en)
    random.Random(20260817).shuffle(shuffled)
    reordered = {i["item_id"] for i in select(shuffled, ru, eq, size=60)["items"]}
    assert straight == reordered


def test_a_batch_built_under_a_different_contract_is_refused():
    """The manifest is the contract between the builder, the page generator,
    the importer and the evaluator. A manifest that merely DESCRIBES the
    contract while every consumer reads the code constants is documentation
    that cannot be wrong, which is the same as documentation nobody checks."""
    batch = _batch()
    check_contract(batch["manifest"])          # green on a real batch

    for field, bad in (
        ("review_schema_version", 1),
        ("schema_version", 1),
        ("questions", ["steps_match_title"]),
        ("verdicts", ["ok", "problem", "cannot_judge"]),
        ("reason_codes", []),
        ("review_statuses", ["COMPLETE"]),
    ):
        stale = {**batch["manifest"], field: bad}
        with pytest.raises(BatchContractError, match=field):
            check_contract(stale)


def test_the_manifest_shape_version_moved_with_the_manifest_shape():
    """`schema_version` stayed at 1 while v2 added five manifest fields, so a
    consumer dispatching on it could not tell a 001 manifest from a 002 one."""
    m = _batch()["manifest"]
    assert m["schema_version"] == SCHEMA_VERSION >= 2
    for added in ("review_schema_version", "supersedes", "supersession",
                  "reason_codes", "review_statuses"):
        assert added in m


def test_every_identifier_the_page_puts_in_an_attribute_is_quote_free():
    """What actually makes the reviewer page's attribute contexts safe.

    `name="${q.id}"`, `value="${v.id}"` and `value="${c.id}"` interpolate these
    vocabularies directly. They are code constants, not catalogue text, so the
    protection is that no identifier can contain a quote -- asserted here rather
    than left to the escaper, which does not run on them.
    """
    for vocabulary in (REVIEW_QUESTIONS, VERDICTS, REASON_CODES,
                       REVIEW_STATUSES):
        for identifier in vocabulary:
            assert re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", identifier), identifier


def test_only_the_authoritative_batch_may_be_dealt_or_evaluated():
    """Section 7. Superseded batches stay in the repository as evidence, so
    something has to say which one is live.

    `check_contract` happens to reject 001 and 002 today, because their
    manifests were written at `schema_version: 1`. That is an accident of
    history, not a rule -- a future batch superseded WITHOUT a schema change
    would sail through it.
    """
    batch = _batch()
    assert_authoritative(batch["manifest"])          # green on the live batch

    for superseded in ("CT1_REVIEW_BATCH_001", "CT1_REVIEW_BATCH_002"):
        stale = {**batch["manifest"], "batch_id": superseded}
        with pytest.raises(BatchContractError, match="not the authoritative"):
            assert_authoritative(stale)


def test_the_superseded_batches_on_disk_are_refused_by_both_guards():
    """Not a hypothetical id -- the manifests actually committed."""
    review = REPO / "core" / "ml" / "review"
    for name in ("ct1_review_batch_001", "ct1_review_batch_002"):
        path = review / name / "manifest.json"
        assert path.exists(), f"{path} is the evidence; it must not vanish"
        manifest = json.loads(path.read_text(encoding="utf-8"))
        with pytest.raises(BatchContractError):
            assert_authoritative(manifest)
        # And each carries a marker a person opening the directory will see.
        marker = (review / name / "SUPERSEDED.md").read_text(encoding="utf-8")
        assert "SUPERSEDED" in marker
        assert BATCH_ID in marker
