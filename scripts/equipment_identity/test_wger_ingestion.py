# -*- coding: utf-8 -*-
"""P1.G4 tests for scripts/equipment_identity/wger_ingestion.py.

    python -m pytest scripts/equipment_identity/test_wger_ingestion.py -q
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import wger_ingestion  # noqa: E402


# --- T1: staging snapshot -- no production write, faithful field carry-through ---


def test_staging_snapshot_has_no_production_write_markers():
    snapshot = wger_ingestion.build_staging_snapshot()
    assert snapshot["stagingOnly"] is True
    assert snapshot["productionWrite"] is False


def test_staging_snapshot_covers_every_raw_fixture():
    snapshot = wger_ingestion.build_staging_snapshot()
    source_ids = {s["sourceId"] for s in snapshot["sources"]}
    raw_ids = {wger_ingestion.load_raw_fixture(n)["sourceId"] for n in wger_ingestion.RAW_FIXTURES}
    assert source_ids == raw_ids


def test_staging_snapshot_preserves_license_field_exactly_including_null():
    # The real, honest fact this test locks in: every exercise-translation
    # record's license field is null in the live wger API (documented in the
    # fixture's own licenseFieldGap note) -- the staging snapshot must carry
    # that null through unchanged, never resolve/invent a value.
    raw = wger_ingestion.load_raw_fixture("wger_exercise_translation_sample_raw.json")
    snapshot = wger_ingestion.build_staging_snapshot()
    staged = next(s for s in snapshot["sources"] if s["sourceId"] == raw["sourceId"])
    assert [r["license"] for r in staged["records"]] == [r["license"] for r in raw["results"]]
    assert all(v is None for v in [r["license"] for r in staged["records"]])


def test_staging_snapshot_preserves_license_author_byte_identical():
    raw = wger_ingestion.load_raw_fixture("wger_exercise_translation_sample_raw.json")
    snapshot = wger_ingestion.build_staging_snapshot()
    staged = next(s for s in snapshot["sources"] if s["sourceId"] == raw["sourceId"])
    raw_authors = [r["licenseAuthor"] for r in raw["results"]]
    staged_authors = [r["licenseAuthor"] for r in staged["records"]]
    assert staged_authors == raw_authors
    # Not vacuous: at least some real, non-empty attribution values exist in
    # the fixture, so this is actually exercising preservation of content,
    # not just preservation of an all-empty list.
    assert any(a for a in raw_authors)


def test_staging_snapshot_record_count_matches_each_raw_fixture():
    snapshot = wger_ingestion.build_staging_snapshot()
    for source in snapshot["sources"]:
        assert source["recordCount"] == len(source["records"])


def test_staging_snapshot_does_not_mutate_the_raw_fixture_on_disk():
    before = {n: wger_ingestion.load_raw_fixture(n) for n in wger_ingestion.RAW_FIXTURES}
    wger_ingestion.build_staging_snapshot()
    after = {n: wger_ingestion.load_raw_fixture(n) for n in wger_ingestion.RAW_FIXTURES}
    assert before == after


def test_load_raw_fixture_rejects_an_unknown_name():
    with pytest.raises(wger_ingestion.WgerIngestionError):
        wger_ingestion.load_raw_fixture("not_a_real_fixture.json")


# --- T2a: equipment mapping ------------------------------------------------


def test_equipment_mapping_covers_every_real_wger_equipment_entry_exactly_once():
    report = wger_ingestion.build_equipment_mapping_report()
    equipment = wger_ingestion.load_raw_fixture("wger_equipment_raw.json")["results"]
    assert report["totalWgerEntries"] == len(equipment) == 12
    covered_ids = [row["wgerId"] for row in report["rows"]]
    assert sorted(covered_ids) == sorted(e["id"] for e in equipment)
    assert len(covered_ids) == len(set(covered_ids))


def test_equipment_mapping_every_sptr_id_is_real():
    sptr_ids = wger_ingestion._sptr_functional_type_ids()
    report = wger_ingestion.build_equipment_mapping_report()
    for row in report["rows"]:
        if row["sptrId"] is not None:
            assert row["sptrId"] in sptr_ids


def test_equipment_mapping_matched_and_alias_rows_always_carry_an_sptr_id():
    report = wger_ingestion.build_equipment_mapping_report()
    for row in report["rows"]:
        if row["classification"] in ("MATCHED", "ALIAS_CANDIDATE"):
            assert row["sptrId"] is not None


def test_equipment_mapping_counts_sum_to_total():
    report = wger_ingestion.build_equipment_mapping_report()
    assert sum(report["counts"].values()) == report["totalWgerEntries"]


def test_equipment_mapping_bodyweight_placeholder_is_not_applicable_not_unmatched():
    # "none (bodyweight exercise)" is not real equipment -- it must be
    # classified NOT_APPLICABLE (excluded from the ontology on purpose),
    # not silently folded into UNMATCHED (which would read as "equipment we
    # failed to map" rather than "not equipment at all").
    report = wger_ingestion.build_equipment_mapping_report()
    row = next(r for r in report["rows"] if r["wgerName"] == "none (bodyweight exercise)")
    assert row["classification"] == "NOT_APPLICABLE"


def test_equipment_mapping_rejects_an_unmatched_row_that_still_carries_an_sptr_id(monkeypatch):
    # Reviewer-found gap (silent-failure-hunter, P1.G4 review, 2026-08-22):
    # the forward check (MATCHED/ALIAS_CANDIDATE requires a real sptrId) had
    # no reverse companion -- an UNMATCHED/NOT_APPLICABLE row could silently
    # carry a stale/leftover sptrId with nothing to catch it.
    bad_mapping = tuple(
        {**row, "sptrId": "barbell"} if row["wgerId"] == 4 else row  # wgerId 4 = "Gym mat", UNMATCHED
        for row in wger_ingestion.EQUIPMENT_MAPPING
    )
    monkeypatch.setattr(wger_ingestion, "EQUIPMENT_MAPPING", bad_mapping)
    with pytest.raises(wger_ingestion.WgerIngestionError, match="sptrId=.*is not None"):
        wger_ingestion.build_equipment_mapping_report()


def test_equipment_mapping_rejects_a_row_referencing_a_fake_sptr_id(monkeypatch):
    bad_mapping = tuple(
        {**row, "sptrId": "not_a_real_functional_type_id"} if row["wgerId"] == 1 else row
        for row in wger_ingestion.EQUIPMENT_MAPPING
    )
    monkeypatch.setattr(wger_ingestion, "EQUIPMENT_MAPPING", bad_mapping)
    with pytest.raises(wger_ingestion.WgerIngestionError, match="not in the real functional_type_snapshot"):
        wger_ingestion.build_equipment_mapping_report()


def test_equipment_mapping_rejects_incomplete_coverage(monkeypatch):
    monkeypatch.setattr(
        wger_ingestion, "EQUIPMENT_MAPPING",
        tuple(row for row in wger_ingestion.EQUIPMENT_MAPPING if row["wgerId"] != 1),
    )
    with pytest.raises(wger_ingestion.WgerIngestionError, match="exactly once"):
        wger_ingestion.build_equipment_mapping_report()


# --- T2b: muscle mapping ----------------------------------------------------


def test_muscle_mapping_covers_every_real_wger_muscle_entry_exactly_once():
    report = wger_ingestion.build_muscle_mapping_report()
    muscles = wger_ingestion.load_raw_fixture("wger_muscle_raw.json")["results"]
    assert report["totalWgerEntries"] == len(muscles) == 15
    covered_ids = [row["wgerId"] for row in report["rows"]]
    assert sorted(covered_ids) == sorted(m["id"] for m in muscles)
    assert len(covered_ids) == len(set(covered_ids))


def test_muscle_mapping_every_sptr_id_is_a_real_value_from_the_exercise_catalog():
    sptr_vocab = wger_ingestion._sptr_muscle_vocabulary()
    assert len(sptr_vocab) > 0
    report = wger_ingestion.build_muscle_mapping_report()
    for row in report["rows"]:
        if row["sptrId"] is not None:
            assert row["sptrId"] in sptr_vocab


def test_muscle_mapping_rejects_an_unmatched_row_that_still_carries_an_sptr_id(monkeypatch):
    # Same reviewer-found gap as the equipment dimension (silent-failure-hunter,
    # P1.G4 review, 2026-08-22), fixed symmetrically in both dimensions.
    bad_mapping = tuple(
        {**row, "sptrId": "calves"} if row["wgerId"] == 13 else row  # wgerId 13 = Brachialis, UNMATCHED
        for row in wger_ingestion.MUSCLE_MAPPING
    )
    monkeypatch.setattr(wger_ingestion, "MUSCLE_MAPPING", bad_mapping)
    with pytest.raises(wger_ingestion.WgerIngestionError, match="sptrId=.*is not None"):
        wger_ingestion.build_muscle_mapping_report()


def test_muscle_mapping_reports_sptr_muscles_never_referenced():
    # Reverse-direction honesty check (the gate's own "disagreements
    # visible" AC): SPTR muscles with no wger counterpart in this mapping
    # must be surfaced, not silently absent from the report.
    report = wger_ingestion.build_muscle_mapping_report()
    referenced = {row["sptrId"] for row in report["rows"] if row["sptrId"] is not None}
    sptr_vocab = wger_ingestion._sptr_muscle_vocabulary()
    assert set(report["sptrMusclesNeverReferenced"]) == (sptr_vocab - referenced)


def test_muscle_mapping_counts_sum_to_total():
    report = wger_ingestion.build_muscle_mapping_report()
    assert sum(report["counts"].values()) == report["totalWgerEntries"]


def test_muscle_mapping_rejects_incomplete_coverage(monkeypatch):
    monkeypatch.setattr(
        wger_ingestion, "MUSCLE_MAPPING",
        tuple(row for row in wger_ingestion.MUSCLE_MAPPING if row["wgerId"] != 1),
    )
    with pytest.raises(wger_ingestion.WgerIngestionError, match="exactly once"):
        wger_ingestion.build_muscle_mapping_report()


# --- T2c: exercise mapping (deterministic, not hand-curated) ---------------


def test_exercise_mapping_rejects_an_empty_wger_sample(monkeypatch):
    # Reviewer-found gap (silent-failure-hunter, P1.G4 review, 2026-08-22):
    # unlike the equipment/muscle dimensions, this dimension has no
    # production-code floor against a truncated/corrupted fixture -- an
    # empty results list would silently produce a "clean"-looking empty
    # report instead of failing loudly, with only the test suite's
    # hard-coded `==57` check (which does not run outside pytest) standing
    # in the way.
    real_load_raw_fixture = wger_ingestion.load_raw_fixture

    def fake_load_raw_fixture(name):
        if name == "wger_exercise_translation_sample_raw.json":
            return {**real_load_raw_fixture(name), "results": []}
        return real_load_raw_fixture(name)

    monkeypatch.setattr(wger_ingestion, "load_raw_fixture", fake_load_raw_fixture)
    with pytest.raises(wger_ingestion.WgerIngestionError, match="empty results list"):
        wger_ingestion.build_exercise_mapping_report()


def test_exercise_mapping_is_deterministic_across_two_runs():
    a = wger_ingestion.build_exercise_mapping_report()
    b = wger_ingestion.build_exercise_mapping_report()
    assert a == b


def test_exercise_mapping_covers_the_full_sample_exactly_once():
    report = wger_ingestion.build_exercise_mapping_report()
    sample = wger_ingestion.load_raw_fixture("wger_exercise_translation_sample_raw.json")["results"]
    assert report["totalWgerSampleEntries"] == len(sample) == 57
    covered = [row["wgerTranslationId"] for row in report["rows"]]
    assert sorted(covered) == sorted(r["id"] for r in sample)
    assert len(covered) == len(set(covered))


def test_exercise_mapping_every_sptr_match_id_actually_exists_in_the_catalog():
    catalog_ids = {e["id"] for e in wger_ingestion._sptr_exercise_catalog()}
    report = wger_ingestion.build_exercise_mapping_report()
    for row in report["rows"]:
        for match_id in row["sptrMatchIds"]:
            assert match_id in catalog_ids


def test_exercise_mapping_matched_rows_have_at_least_one_match_id():
    report = wger_ingestion.build_exercise_mapping_report()
    for row in report["rows"]:
        if row["classification"] in ("MATCHED", "ALIAS_CANDIDATE"):
            assert row["sptrMatchIds"], row
        if row["classification"] == "UNMATCHED":
            assert row["sptrMatchIds"] == []


def test_exercise_mapping_counts_sum_to_total():
    report = wger_ingestion.build_exercise_mapping_report()
    assert sum(report["counts"].values()) == report["totalWgerSampleEntries"]


def test_normalize_title_is_case_and_punctuation_insensitive():
    assert wger_ingestion._normalize_title("Ab Wheel!") == wger_ingestion._normalize_title("ab wheel")


# --- T2d: variation -- explicitly NOT_MODELED, not fabricated --------------


def test_variation_report_is_explicitly_not_modeled():
    report = wger_ingestion.build_variation_report()
    assert report["status"] == "NOT_MODELED"
    assert report["rationale"]


# --- combined report + generated-file integrity ----------------------------


def test_build_mapping_report_has_all_four_dimensions():
    report = wger_ingestion.build_mapping_report()
    assert set(report["dimensions"].keys()) == {"equipment", "muscle", "exercise", "variation"}


def test_generated_staging_snapshot_file_matches_a_fresh_build():
    on_disk = json.loads(wger_ingestion.STAGING_SNAPSHOT_PATH.read_text(encoding="utf-8"))
    fresh = wger_ingestion.build_staging_snapshot()
    assert on_disk == fresh


def test_generated_mapping_report_file_matches_a_fresh_build():
    on_disk = json.loads(wger_ingestion.MAPPING_REPORT_PATH.read_text(encoding="utf-8"))
    fresh = wger_ingestion.build_mapping_report()
    assert on_disk == fresh


def test_no_function_in_this_module_performs_a_network_call():
    # Structural guard against a future edit silently turning this into a
    # live-fetch module -- grep the source for the obvious offenders rather
    # than trying to intercept sockets.
    import inspect
    source = inspect.getsource(wger_ingestion)
    for forbidden in ("requests.", "urllib.request", "httpx.", "http.client"):
        assert forbidden not in source


# --- P1.G4 review: canonical-JSON writer + atomic-tmp-file race -----------


def test_write_json_atomic_uses_this_namespaces_canonical_pretty_printer():
    # Reviewer-found gap (python-reviewer, P1.G4 review, 2026-08-22):
    # canonical_json.py's own module docstring mandates every generator
    # under scripts/equipment_identity/ write through dump_pretty (sorted
    # keys, no bespoke json.dumps) -- this module was the one generator in
    # the namespace not doing that. Assert the two committed generated files
    # are byte-identical to canonical_json.dump_pretty's own output for the
    # same data, not just structurally equal after a second json.loads.
    for path, builder in (
        (wger_ingestion.STAGING_SNAPSHOT_PATH, wger_ingestion.build_staging_snapshot),
        (wger_ingestion.MAPPING_REPORT_PATH, wger_ingestion.build_mapping_report),
    ):
        on_disk_text = path.read_text(encoding="utf-8")
        assert on_disk_text == wger_ingestion.canonical_json.dump_pretty(builder())


def test_write_json_atomic_temp_filename_is_unique_per_process(tmp_path):
    # Reviewer-found gap (python-reviewer, P1.G4 review, 2026-08-22): a
    # fixed tmp filename would race under this workspace's documented
    # concurrent-session pattern -- assert the tmp name now embeds the pid.
    target = tmp_path / "example.json"
    wger_ingestion._write_json_atomic(target, {"a": 1})
    assert target.read_text(encoding="utf-8") == wger_ingestion.canonical_json.dump_pretty({"a": 1})
    leftover_tmp_files = list(tmp_path.glob("example.json.*.tmp"))
    assert leftover_tmp_files == []  # replace() must always clean up the tmp name
    import inspect
    source = inspect.getsource(wger_ingestion._write_json_atomic)
    assert "os.getpid()" in source
