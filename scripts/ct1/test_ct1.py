# -*- coding: utf-8 -*-
"""CT-1 contract, builder, baseline and evaluation.

    python -m pytest scripts/ct1/test_ct1.py -q

Two kinds of test here, and the second kind is the point.

The first checks the code does what it says. The second checks the code CANNOT
do the things CT-1 exists to prevent — train on its own predictions, produce a
clinically validated label, or emit a dataset hash that moves when nothing
moved. Those are asserted against the machinery rather than against a document,
because the programme this pipeline belongs to has repeatedly found that a rule
written only in prose is a rule that gets skipped.
"""
from __future__ import annotations

import json

import pytest

from baseline import REGION_TAGS, corpus_observations, run_checks
from build_dataset import build, split_for
from evaluate import EXACT_BY_CONSTRUCTION, check_family, evaluate
from label_contract import (
    Label,
    LabelContractError,
    LabelSource,
    assert_no_self_training,
    may_train_on,
)

# --------------------------------------------------------------------------
# fixtures — small and hand-written, so an assertion names a row you can read
# --------------------------------------------------------------------------

EQ = [{"id": "bench"}, {"id": "treadmill"}]

EN = [
    {"id": "a", "title": "Bench Press", "summary": "Push.",
     "steps": ["Lie down", "Press"], "equipmentId": "bench",
     "contraindications": ["shoulder"], "tips": ["Brace"],
     "muscles": ["chest"], "primaryMuscles": ["chest"],
     "difficulty": "beginner", "vendorGroup": "Chest", "isStretch": False},
    # Duplicate summary and duplicate steps with `a`; no contraindications key.
    {"id": "b", "title": "Bench Press Wide", "summary": "Push.",
     "steps": ["Lie down", "Press"], "equipmentId": "bench",
     "tips": [], "muscles": [], "primaryMuscles": [],
     "difficulty": "beginner", "vendorGroup": "Chest", "isStretch": False},
    # Dangling equipment, unknown tag, contraindications present but empty.
    {"id": "c", "title": "Sled Push", "summary": "Drive.",
     "steps": ["Push"], "equipmentId": "ghost_machine",
     "contraindications": [], "tips": ["Head up"],
     "muscles": ["legs"], "primaryMuscles": ["legs"],
     "difficulty": "beginner", "vendorGroup": "Legs", "isStretch": False},
    {"id": "d", "title": "Hamstring Stretch", "summary": "Hold.",
     "steps": ["Reach"], "equipmentId": None,
     "contraindications": ["not_a_region"], "tips": ["Breathe"],
     "muscles": ["hamstrings"], "primaryMuscles": ["hamstrings"],
     "difficulty": "beginner", "vendorGroup": "Stretch", "isStretch": True},
]

RU = {
    "a": {"title": "Жим лёжа", "summary": "Толчок.",
          "steps": ["Лягте", "Жмите"], "tips": ["Напрягите"]},
    "b": {"title": "Bench Press Wide", "summary": "Толчок.",
          "steps": ["Лягте", "Жмите"]},
    "c": {"title": "Толкание саней", "summary": "Толкайте.",
          "steps": ["Толкайте"], "tips": ["Голову выше"],
          "purpose": "Осанка."},
    # `d` deliberately absent.
}


def checks_for(item_id: str) -> set[str]:
    return {l.check for l in run_checks(EN, RU, EQ) if l.item_id == item_id}


# --------------------------------------------------------------------------
# the label contract
# --------------------------------------------------------------------------

def test_a_reviewed_label_needs_someone_to_have_reviewed_it():
    with pytest.raises(LabelContractError, match="reviewer"):
        Label("a", "steps_contradict_title",
              LabelSource.HUMAN_REVIEWED_QA_LABEL)
    ok = Label("a", "steps_contradict_title",
               LabelSource.HUMAN_REVIEWED_QA_LABEL, reviewer="qa.jordan")
    assert ok.reviewer == "qa.jordan"


def test_a_machine_label_may_not_carry_a_person_s_name():
    # Otherwise the provenance is technically present and practically unread:
    # a heuristic flag with a reviewer beside it looks exactly like a review.
    with pytest.raises(LabelContractError, match="must not carry a reviewer"):
        Label("a", "duplicate_title", LabelSource.AUTO_HEURISTIC_FLAG,
              reviewer="qa.jordan")


def test_nothing_here_can_mint_a_clinically_validated_label():
    # D1/H3. The enum member exists so the absence is representable; producing
    # one must be impossible rather than merely discouraged.
    with pytest.raises(LabelContractError, match="D1"):
        Label("a", "safe", LabelSource.CLINICALLY_VALIDATED_LABEL,
              reviewer="dr.smith")


@pytest.mark.parametrize("source,allowed", [
    (LabelSource.OBSERVATION, False),
    (LabelSource.AUTO_HEURISTIC_FLAG, False),
    (LabelSource.MODEL_PREDICTION, False),
    (LabelSource.HUMAN_REVIEWED_QA_LABEL, True),
    (LabelSource.DOMAIN_REVIEWED_LABEL, True),
])
def test_only_reviewed_sources_may_be_trained_on(source, allowed):
    assert may_train_on(source) is allowed


def test_a_model_prediction_cannot_become_its_own_target():
    # The feedback loop, refused where it would actually happen.
    with pytest.raises(LabelContractError, match="MODEL_PREDICTION"):
        assert_no_self_training(
            [Label("a", "looks_wrong", LabelSource.MODEL_PREDICTION)]
        )


def test_a_heuristic_flag_cannot_become_a_target_either():
    with pytest.raises(LabelContractError, match="AUTO_HEURISTIC_FLAG"):
        assert_no_self_training(
            [Label("a", "duplicate_title", LabelSource.AUTO_HEURISTIC_FLAG)]
        )


# --------------------------------------------------------------------------
# the deterministic baseline
# --------------------------------------------------------------------------

def test_absent_and_empty_are_different_findings():
    # `b` has no contraindications key at all; `c` has the key with an empty
    # list. Collapsing them loses the record that somebody decided `c` has
    # none, which is the only trace of that decision in the catalogue.
    assert "field_absent:contraindications" in checks_for("b")
    assert "field_present_but_empty:contraindications" in checks_for("c")
    assert "field_absent:contraindications" not in checks_for("c")


def test_a_dangling_equipment_reference_is_flagged():
    assert "dangling_equipment_ref" in checks_for("c")
    # A null equipmentId is bodyweight, not a dangling reference. 503 rows in
    # the shipped catalogue are null, so getting this wrong would bury the
    # queue under a quarter of the corpus.
    assert "dangling_equipment_ref" not in checks_for("d")


def test_a_tag_outside_the_nine_region_vocabulary_is_flagged():
    assert "not_a_region" not in REGION_TAGS
    assert "unknown_contraindication_tag" in checks_for("d")
    assert "unknown_contraindication_tag" not in checks_for("a")


def test_duplicates_are_reported_once_per_group_not_once_per_member():
    # Flagging every member doubles the queue and states one fact twice.
    assert "duplicate_summary" not in checks_for("a")
    assert "duplicate_summary" in checks_for("b")
    assert "duplicate_steps_block" in checks_for("b")


def test_a_missing_translation_is_found_in_both_directions():
    assert "locale_row_missing" in checks_for("d")
    # `b` has no RU tips while EN has none either, so nothing to report; `c`
    # carries a RU `purpose` the English row does not have.
    assert "locale_field_orphan" in checks_for("c")


def test_an_untranslated_value_is_not_a_translation():
    # `b`'s RU title is the English string verbatim.
    assert "locale_value_identical" in checks_for("b")
    assert "locale_value_identical" not in checks_for("a")


def test_a_clean_row_produces_nothing():
    # The control. Without it every assertion above is satisfied by a baseline
    # that flags everything.
    assert checks_for("a") == set()


def test_a_field_carrying_one_value_everywhere_is_called_degenerate():
    obs = {o["field"]: o for o in corpus_observations(EN)}
    assert obs["difficulty"]["degenerate"] is True
    assert obs["difficulty"]["dominant_value"] == "beginner"
    # And a field with a real spread is not.
    assert obs["vendorGroup"]["degenerate"] is False


# --------------------------------------------------------------------------
# reproducibility
# --------------------------------------------------------------------------

def test_the_split_is_a_property_of_the_row_not_of_the_corpus():
    # random.shuffle with a fixed seed is reproducible for a fixed corpus and
    # silently is not the moment a row is added. Hashing the id survives that.
    before = {r["id"]: split_for(r["id"]) for r in EN}
    grown = EN + [{"id": "zzz_new", "title": "New", "summary": "s",
                   "steps": ["x"]}]
    after = {r["id"]: split_for(r["id"]) for r in grown}
    for k, v in before.items():
        assert after[k] == v


def test_two_builds_of_the_same_inputs_agree_byte_for_byte(tmp_path):
    en_p = tmp_path / "en.json"
    ru_p = tmp_path / "ru.json"
    eq_p = tmp_path / "eq.json"
    for p, v in ((en_p, EN), (ru_p, RU), (eq_p, EQ)):
        p.write_text(json.dumps(v, ensure_ascii=False), encoding="utf-8")

    a = build(en_p, ru_p, eq_p, "test")
    b = build(en_p, ru_p, eq_p, "test")
    assert a["manifest"]["dataset_hash"] == b["manifest"]["dataset_hash"]
    assert a["content"] == b["content"]


def test_the_hash_ignores_the_timestamp_and_notices_the_data(tmp_path):
    en_p = tmp_path / "en.json"
    ru_p = tmp_path / "ru.json"
    eq_p = tmp_path / "eq.json"
    for p, v in ((en_p, EN), (ru_p, RU), (eq_p, EQ)):
        p.write_text(json.dumps(v, ensure_ascii=False), encoding="utf-8")
    first = build(en_p, ru_p, eq_p, "test")

    # A hash that moves when nothing moved proves nothing, so `built_at` must
    # be outside it...
    second = build(en_p, ru_p, eq_p, "test")
    assert first["manifest"]["dataset_hash"] == second["manifest"]["dataset_hash"]

    # ...and a hash that ignores the data proves nothing either.
    changed = [dict(EN[0], title="Renamed")] + EN[1:]
    en_p.write_text(json.dumps(changed, ensure_ascii=False), encoding="utf-8")
    third = build(en_p, ru_p, eq_p, "test")
    assert third["manifest"]["dataset_hash"] != first["manifest"]["dataset_hash"]


def test_the_manifest_records_what_a_rebuild_would_need(tmp_path):
    en_p = tmp_path / "en.json"
    ru_p = tmp_path / "ru.json"
    eq_p = tmp_path / "eq.json"
    for p, v in ((en_p, EN), (ru_p, RU), (eq_p, EQ)):
        p.write_text(json.dumps(v, ensure_ascii=False), encoding="utf-8")
    m = build(en_p, ru_p, eq_p, "test")["manifest"]

    for key in ("dataset_id", "dataset_version", "schema_version", "source",
                "source_commit", "rows_included", "rows_excluded",
                "label_sources", "transforms", "normalisation",
                "split_strategy", "splits", "dataset_hash", "built_at"):
        assert key in m, f"manifest is missing {key}"
    assert set(m["source"]["sha256"]) == {"catalogue_en", "catalogue_ru",
                                          "equipment"}


def test_the_dataset_carries_no_images_and_no_personal_data(tmp_path):
    # CT-1's whole reason for going first is that it needs neither. Asserted so
    # that adding either becomes a deliberate act with a red test in front of
    # it, rather than a field somebody adds to the feature dict.
    en_p = tmp_path / "en.json"
    ru_p = tmp_path / "ru.json"
    eq_p = tmp_path / "eq.json"
    for p, v in ((en_p, EN), (ru_p, RU), (eq_p, EQ)):
        p.write_text(json.dumps(v, ensure_ascii=False), encoding="utf-8")
    built = build(en_p, ru_p, eq_p, "test")

    assert built["manifest"]["contains_images"] is False
    assert built["manifest"]["contains_personal_data"] is False
    blob = json.dumps(built["content"], ensure_ascii=False).lower()
    for forbidden in ("photo", "image", "camera", "uid", "email", "poster",
                      "video"):
        assert forbidden not in blob, f"{forbidden!r} reached the dataset"


def test_the_training_split_refuses_machine_labels(tmp_path, monkeypatch):
    # The builder calls assert_no_self_training on the training targets. Today
    # that call is vacuous -- there are no reviewed labels -- so this proves
    # the wiring exists rather than that it currently fires.
    import build_dataset as bd

    def pretend_everything_is_trainable(source):
        return True

    monkeypatch.setattr(bd, "may_train_on", pretend_everything_is_trainable)
    en_p = tmp_path / "en.json"
    ru_p = tmp_path / "ru.json"
    eq_p = tmp_path / "eq.json"
    for p, v in ((en_p, EN), (ru_p, RU), (eq_p, EQ)):
        p.write_text(json.dumps(v, ensure_ascii=False), encoding="utf-8")

    with pytest.raises(LabelContractError):
        bd.build(en_p, ru_p, eq_p, "test")


# --------------------------------------------------------------------------
# evaluation honesty
# --------------------------------------------------------------------------

def test_evaluation_reports_the_label_gap_instead_of_a_number():
    rep = evaluate(EN, RU, EQ)
    gap = rep["evaluation_label_gap"]
    assert gap["state"] == "EVALUATION_LABEL_GAP"
    assert gap["reviewed_labels"] == 0
    for blocked in ("precision", "recall", "false_positive_rate"):
        assert blocked in gap["blocks"]
        assert blocked not in rep, (
            f"{blocked} was reported despite there being no ground truth to "
            "compute it against"
        )


def test_every_check_the_baseline_emits_is_classified():
    # A new check must be classified as exact-by-construction or not. Left
    # unclassified it would sit in the report as an unlabelled number, which is
    # how "exact" quietly starts meaning "important".
    rep = evaluate(EN, RU, EQ)
    assert rep["unclassified_check_families"] == []


def test_the_queue_names_its_biggest_entries():
    rep = evaluate(EN, RU, EQ)
    shape = rep["queue_shape"]
    assert shape == sorted(shape, key=lambda r: (-r["items"], r["check"]))
    assert all("exact_by_construction" in r for r in shape)


def test_what_the_baseline_cannot_do_is_written_next_to_what_it_can():
    rep = evaluate(EN, RU, EQ)
    assert len(rep["requires_judgement_not_covered"]) >= 3


def test_check_family_strips_the_field_suffix():
    assert check_family("field_absent:tips") == "field_absent"
    assert check_family("duplicate_title") == "duplicate_title"
    assert "field_absent" in EXACT_BY_CONSTRUCTION
