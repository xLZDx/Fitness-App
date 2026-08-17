# -*- coding: utf-8 -*-
"""The clinical validator: every refusal, and the boundary it must not cross.

    python -m pytest scripts/review/test_clinical_import.py -q

A validator is green against a function that returns its input, so almost
everything below breaks a submission and asserts the refusal. The last section
is different: it asserts what this module must NOT do, because the failure
there is a passing test suite around a module that quietly acquired a clinical
opinion.
"""
from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from clinical_import import (  # noqa: E402
    CSV_FILLABLE,
    CSV_READONLY,
    DISPOSITIONS,
    REPO,
    ROW_FIELDS,
    SCHEMA_VERSION,
    SUBMISSION_FIELDS,
    ClinicalImportError,
    catalogue_digest,
    load_submission,
    regions,
    validate,
    verify_worklist,
    worklist,
    write_worklist,
)


def _body() -> str:
    """The module's code, with its docstring removed.

    The docstring is where this module EXPLAINS the boundary, so a plain
    substring search over the whole file would fire on the explanation and
    never on a violation.
    """
    source = (Path(__file__).resolve().parent / "clinical_import.py").read_text(
        encoding="utf-8"
    )
    return source.split('"""', 2)[-1]


def _ids(n: int) -> list[str]:
    return [r["item_id"] for r in worklist()["rows"][:n]]


def _submission(**overrides):
    """A structurally valid submission. Its dispositions are meaningless: they
    are placeholders in a shape test, not a clinical claim about any row."""
    body = {
        "schema_version": SCHEMA_VERSION,
        "handoff_commit": "0" * 40,
        "catalogue_sha256": catalogue_digest(),
        "reviewer_name": "A. Reviewer",
        "reviewer_credentials": "MSc Physiotherapy, HCPC PH000000",
        "reviewer_authority": "Independent; engaged for this review only",
        "reviewed_at": "2026-08-17T10:00:00+00:00",
        "rows": [{"item_id": i, "disposition": "UNKNOWN"} for i in _ids(3)],
    }
    body.update(overrides)
    return body


# --------------------------------------------------------------------------
# identity and authority -- the field CT-1 deliberately does not have
# --------------------------------------------------------------------------


def test_a_structurally_valid_submission_is_accepted():
    """Otherwise every refusal below is satisfied by a function that always
    raises."""
    result = validate(_submission())
    assert result["counts"]["UNKNOWN"] == 3
    assert result["reviewer"]["credentials"].startswith("MSc")


@pytest.mark.parametrize(
    "field", ["reviewer_name", "reviewer_credentials", "reviewer_authority"]
)
def test_an_unattributed_review_is_refused(field):
    """An anonymous clinical review is not a clinical review: nobody can be
    asked what they meant, and nobody is accountable for it."""
    for blank in (None, "", "   "):
        with pytest.raises(ClinicalImportError, match=field):
            validate(_submission(**{field: blank}))


def test_credentials_are_required_even_when_a_name_is_present():
    """The specific gap the handoff review found: the repository had a place
    for WHO reviewed and none for WHETHER THEY MAY."""
    with pytest.raises(ClinicalImportError, match="credentials"):
        s = _submission()
        del s["reviewer_credentials"]
        validate(s)


@pytest.mark.parametrize("field", SUBMISSION_FIELDS)
def test_every_declared_submission_field_is_actually_enforced(field):
    """Pins the list to the behaviour. A field added to SUBMISSION_FIELDS and
    not checked would otherwise document a guarantee nobody provides."""
    s = _submission()
    del s[field]
    with pytest.raises(ClinicalImportError):
        validate(s)


# --------------------------------------------------------------------------
# provenance -- the review must describe the content that is actually there
# --------------------------------------------------------------------------


def test_a_review_of_a_different_catalogue_is_refused_as_stale():
    """The blocker that made the handoff unusable: it bound a review to a
    BRANCH, which moves. A review names the bytes it read."""
    with pytest.raises(ClinicalImportError, match="STALE"):
        validate(_submission(catalogue_sha256="a" * 64))


def test_the_stale_refusal_says_reissue_rather_than_discard():
    """A clinician's work is expensive. 'Not importable' must not read as
    'thrown away'."""
    with pytest.raises(ClinicalImportError) as exc:
        validate(_submission(catalogue_sha256="a" * 64))
    assert "reissue" in str(exc.value)
    assert "NOT discarded" in str(exc.value)


def test_the_digest_checked_is_the_catalogue_the_worklist_shipped():
    """If these two ever read different files, a review of the worklist would
    be refused as stale against a catalogue nobody sent."""
    assert worklist()["catalogue_sha256"] == catalogue_digest()


def test_a_schema_from_another_version_is_refused():
    with pytest.raises(ClinicalImportError, match="validator is"):
        validate(_submission(schema_version=SCHEMA_VERSION + 1))


@pytest.mark.parametrize("bad", ["", None, "yesterday", "2026-08-17"])
def test_an_unusable_review_timestamp_is_refused(bad):
    with pytest.raises(ClinicalImportError, match="reviewed_at"):
        validate(_submission(reviewed_at=bad))


def test_a_naive_timestamp_is_refused():
    """Without an offset it cannot be ordered against a catalogue change, so
    'reviewed before the content moved' is unanswerable."""
    with pytest.raises(ClinicalImportError, match="UTC offset"):
        validate(_submission(reviewed_at="2026-08-17T10:00:00"))


# --------------------------------------------------------------------------
# rows
# --------------------------------------------------------------------------


def test_a_review_of_a_row_that_does_not_exist_is_refused():
    with pytest.raises(ClinicalImportError, match="not an exercise"):
        validate(_submission(rows=[{"item_id": "no-such-row",
                                    "disposition": "ACCEPT"}]))


def test_the_same_row_reviewed_twice_is_refused():
    """Not silently last-wins, and not silently first-wins. Which entry is the
    review is a question the file cannot answer, so a human must."""
    rid = _ids(1)[0]
    with pytest.raises(ClinicalImportError, match="reviewed twice"):
        validate(_submission(rows=[
            {"item_id": rid, "disposition": "ACCEPT"},
            {"item_id": rid, "disposition": "REJECT"},
        ]))


def test_duplicates_are_refused_even_when_they_agree():
    """An agreeing duplicate is still two rows where the export produced one,
    and the export is the thing under suspicion."""
    rid = _ids(1)[0]
    with pytest.raises(ClinicalImportError, match="reviewed twice"):
        validate(_submission(rows=[
            {"item_id": rid, "disposition": "ACCEPT"},
            {"item_id": rid, "disposition": "ACCEPT"},
        ]))


@pytest.mark.parametrize("field", ROW_FIELDS)
def test_a_row_missing_a_required_field_is_refused(field):
    row = {"item_id": _ids(1)[0], "disposition": "ACCEPT"}
    del row[field]
    with pytest.raises(ClinicalImportError, match=field):
        validate(_submission(rows=[row]))


def test_an_empty_submission_is_not_a_review():
    """Otherwise a clinician who returned nothing would be recorded as having
    reviewed, with a validated file to prove it."""
    for empty in ([], None, "rows"):
        with pytest.raises(ClinicalImportError, match="not a review"):
            validate(_submission(rows=empty))


def test_an_unknown_disposition_is_refused():
    with pytest.raises(ClinicalImportError, match="not one of"):
        validate(_submission(rows=[{"item_id": _ids(1)[0],
                                    "disposition": "PROBABLY_FINE"}]))


def test_unknown_is_a_first_class_answer_and_not_a_missing_one():
    """Forcing a disposition on a row nobody can decide manufactures exactly
    the clinical judgement this repository must not manufacture."""
    assert "UNKNOWN" in DISPOSITIONS
    result = validate(_submission(rows=[{"item_id": _ids(1)[0],
                                         "disposition": "UNKNOWN"}]))
    assert result["counts"]["UNKNOWN"] == 1


# --------------------------------------------------------------------------
# tags -- vocabulary only, never which tag belongs anywhere
# --------------------------------------------------------------------------


def test_an_amendment_to_a_tag_the_app_cannot_match_is_refused():
    """A tag outside the nine is invisible to every safety filter, so it looks
    like a screened row and behaves like an unscreened one."""
    with pytest.raises(ClinicalImportError, match="region vocabulary"):
        validate(_submission(rows=[{"item_id": _ids(1)[0],
                                    "disposition": "AMEND",
                                    "tags": ["lumbar_spine"]}]))


def test_the_vocabulary_is_read_from_the_catalog_file_not_restated():
    """Nine regions, and the same nine the baseline scanner enforces. A second
    hand-typed copy would drift and this validator would be the last place
    anybody looked."""
    sys.path.insert(0, str(REPO / "scripts" / "ct1"))
    from baseline import REGION_TAGS  # noqa: E402

    assert set(regions()) == set(REGION_TAGS)
    assert len(regions()) == 9


def test_a_vocabulary_file_that_lost_its_key_is_refused(tmp_path, monkeypatch):
    """The quietest failure in this module. `injury_regions.json` is a
    PROJECTION of the Dart enum InjuryRegion, so its shape is not this file's
    to control; if the key is renamed and the read falls back to an empty
    vocabulary, every tag in every submission validates and the refusal above
    becomes decorative while still passing its own test."""
    import clinical_import

    for content in ({"regions": ["knee"]}, {"tags": []}, {}):
        broken = tmp_path / "injury_regions.json"
        broken.write_text(json.dumps(content), encoding="utf-8")
        monkeypatch.setattr(clinical_import, "REGIONS_FILE", broken)
        with pytest.raises(ClinicalImportError, match="no `tags` list"):
            clinical_import.regions()


def test_an_amendment_with_valid_tags_is_accepted():
    result = validate(_submission(rows=[{"item_id": _ids(1)[0],
                                         "disposition": "AMEND",
                                         "tags": ["knee", "hip"]}]))
    assert result["rows"][0]["tags"] == ["hip", "knee"]


def test_amending_to_no_tags_is_expressible():
    """'This row should carry none' is a real clinical answer and must not be
    indistinguishable from 'the clinician left the field blank'."""
    result = validate(_submission(rows=[{"item_id": _ids(1)[0],
                                         "disposition": "AMEND", "tags": []}]))
    assert result["rows"][0]["tags"] == []


def test_amend_without_a_tag_list_is_refused():
    with pytest.raises(ClinicalImportError, match="requires a `tags` list"):
        validate(_submission(rows=[{"item_id": _ids(1)[0],
                                    "disposition": "AMEND"}]))


@pytest.mark.parametrize("disposition", ["ACCEPT", "REJECT", "UNKNOWN"])
def test_tags_on_a_non_amendment_are_refused_rather_than_ignored(disposition):
    """Ignoring them would silently drop a clinician's intent; whether the list
    is the new value or a restatement of the old one is unanswerable here."""
    with pytest.raises(ClinicalImportError, match="only AMEND carries tags"):
        validate(_submission(rows=[{"item_id": _ids(1)[0],
                                    "disposition": disposition,
                                    "tags": ["knee"]}]))


def test_duplicate_tags_are_refused():
    with pytest.raises(ClinicalImportError, match="duplicate tags"):
        validate(_submission(rows=[{"item_id": _ids(1)[0],
                                    "disposition": "AMEND",
                                    "tags": ["knee", "knee"]}]))


# --------------------------------------------------------------------------
# the worklist a clinician actually receives
# --------------------------------------------------------------------------


def test_the_worklist_covers_both_populations():
    """A worklist of only the 360 untagged rows would answer Q2 by omission --
    'the existing tags are fine, we did not ask'."""
    payload = worklist()
    assert payload["counts"] == {"total": 1887, "tagged": 1527, "untagged": 360}
    assert payload["counts"]["tagged"] + payload["counts"]["untagged"] == 1887


def test_every_worklist_row_carries_the_content_needed_to_judge_it():
    """A row-level worklist that omits the steps is a list of IDs."""
    for row in worklist()["rows"][:50]:
        assert row["title"], row["item_id"]
        assert row["steps"] or row["summary"], row["item_id"]
        assert row["population"] in ("TAGGED", "UNTAGGED")


def test_the_worklist_states_the_behaviour_under_review_per_row():
    """The corrected F013 claim, on the row rather than in a section the
    reader may not reach: an untagged row is SHOWN, not withheld."""
    rows = {r["population"]: r for r in worklist()["rows"]}
    untagged = rows["UNTAGGED"]["current_app_behaviour"]
    assert "SHOWN" in untagged
    assert "withheld" not in untagged.lower()
    assert "F013" in untagged
    assert "Removed" in rows["TAGGED"]["current_app_behaviour"]


def test_the_worklist_proposes_no_answer():
    """The single most important property. If this file ever suggested a tag,
    the returned review would be measuring this repository's guess."""
    payload = worklist()
    text = json.dumps(payload, ensure_ascii=False)
    assert "suggested_tags" not in text
    assert "proposed_tags" not in text
    assert "recommended" not in text.lower()
    for row in payload["rows"]:
        assert set(row) & {"suggestion", "proposal", "prefill"} == set()


def test_the_worklist_names_the_authority_it_lacks():
    assert "EXTERNAL_CLINICAL_VALIDATION_REQUIRED" in worklist()["authority"]
    assert "H3 = HOLD" in worklist()["authority"]


def test_worklist_rows_are_unique():
    ids = [r["item_id"] for r in worklist()["rows"]]
    assert len(ids) == len(set(ids))


# --------------------------------------------------------------------------
# the fillable sheet -- the gap that made the handoff unusable in practice
# --------------------------------------------------------------------------


@pytest.fixture
def issued(tmp_path):
    """A worklist as a clinician receives it."""
    write_worklist(tmp_path)
    return tmp_path


def _fill(directory: Path, answers: dict[str, tuple[str, str, str]]) -> Path:
    """Fill the disposition columns of the issued sheet, as a spreadsheet would."""
    sheet = directory / "worklist.csv"
    with sheet.open(encoding="utf-8-sig", newline="") as fh:
        rows = list(csv.DictReader(fh))
        columns = list(rows[0])
    for row in rows:
        if row["item_id"] in answers:
            row["disposition"], row["tags"], row["rationale"] = \
                answers[row["item_id"]]
    with sheet.open("w", encoding="utf-8-sig", newline="") as fh:
        out = csv.DictWriter(fh, columns)
        out.writeheader()
        out.writerows(rows)

    body = json.loads((directory / "submission.json").read_text(encoding="utf-8"))
    body.update({
        "reviewer_name": "A. Reviewer",
        "reviewer_credentials": "MSc Physiotherapy, HCPC PH000000",
        "reviewer_authority": "Independent; engaged for this review only",
        "reviewed_at": "2026-08-17T10:00:00+00:00",
    })
    (directory / "submission.json").write_text(
        json.dumps(body, indent=2), encoding="utf-8"
    )
    return directory / "submission.json"


def test_a_filled_spreadsheet_round_trips(issued):
    """The whole point: a clinician works in Excel, not in JSON."""
    a, b, c = _ids(3)
    path = _fill(issued, {
        a: ("ACCEPT", "", ""),
        b: ("AMEND", "knee hip", "loaded knee flexion under bodyweight"),
        c: ("UNKNOWN", "", "steps do not describe the loading"),
    })
    result = validate(load_submission(path))
    assert result["counts"] == {"ACCEPT": 1, "AMEND": 1, "UNKNOWN": 1, "REJECT": 0}
    assert result["rows"][1]["tags"] == ["hip", "knee"]
    assert result["rows"][2]["rationale"].startswith("steps do not")


def test_an_unfilled_row_is_not_reviewed_rather_than_accepted(issued):
    """1,884 blank rows must not arrive as 1,884 approvals. This is the single
    most damaging thing a tolerant CSV reader could do."""
    path = _fill(issued, {_ids(1)[0]: ("ACCEPT", "", "")})
    result = validate(load_submission(path))
    assert result["coverage"]["reviewed"] == 1
    assert result["coverage"]["not_reviewed"] == 1886
    assert result["counts"]["ACCEPT"] == 1


def test_a_sheet_with_no_filled_row_is_refused(issued):
    """A clinician who returned the file untouched has not reviewed anything,
    and must not end up with a validated submission proving they did."""
    path = _fill(issued, {})
    with pytest.raises(ClinicalImportError, match="not a review"):
        validate(load_submission(path))


def test_amend_with_an_empty_tags_cell_means_no_tags(issued):
    """Distinct from 'left the row alone'. A clinician saying 'this row should
    carry none' is a real answer and the CSV must be able to express it."""
    path = _fill(issued, {_ids(1)[0]: ("AMEND", "  ", "")})
    result = validate(load_submission(path))
    assert result["rows"][0]["tags"] == []


def test_a_tag_left_in_the_cell_of_a_non_amendment_is_refused(issued):
    """Not silently dropped: whether they meant to amend is unanswerable, and
    guessing loses a clinician's intent invisibly."""
    path = _fill(issued, {_ids(1)[0]: ("ACCEPT", "knee", "")})
    with pytest.raises(ClinicalImportError, match="only AMEND carries tags"):
        validate(load_submission(path))


def test_a_lowercase_disposition_is_accepted(issued):
    """Typed by hand into a spreadsheet. Case is not a clinical distinction and
    refusing on it would send real work back for a cosmetic reason."""
    path = _fill(issued, {_ids(1)[0]: ("accept", "", "")})
    assert validate(load_submission(path))["counts"]["ACCEPT"] == 1


def test_a_misspelled_disposition_is_still_refused(issued):
    """The tolerance above must not become tolerance of an unknown answer."""
    path = _fill(issued, {_ids(1)[0]: ("approved", "", "")})
    with pytest.raises(ClinicalImportError, match="not one of"):
        validate(load_submission(path))


def test_a_sheet_that_is_not_the_one_issued_is_refused(issued):
    """Columns removed or renamed means this is not the worklist that was sent,
    so the review cannot be tied to the catalogue version it names."""
    path = _fill(issued, {_ids(1)[0]: ("ACCEPT", "", "")})
    sheet = issued / "worklist.csv"
    text = sheet.read_text(encoding="utf-8-sig")
    sheet.write_text(text.replace("current_tags,", "", 1), encoding="utf-8-sig")
    with pytest.raises(ClinicalImportError, match="current_tags"):
        validate(load_submission(path))


def test_a_missing_spreadsheet_is_refused(issued):
    path = _fill(issued, {_ids(1)[0]: ("ACCEPT", "", "")})
    (issued / "worklist.csv").unlink()
    with pytest.raises(ClinicalImportError, match="not beside"):
        validate(load_submission(path))


def test_rows_and_rows_csv_together_are_refused(issued):
    path = _fill(issued, {_ids(1)[0]: ("ACCEPT", "", "")})
    body = json.loads(path.read_text(encoding="utf-8"))
    body["rows"] = [{"item_id": _ids(1)[0], "disposition": "REJECT"}]
    path.write_text(json.dumps(body), encoding="utf-8")
    with pytest.raises(ClinicalImportError, match="both"):
        load_submission(path)


def test_the_issued_submission_header_is_blank_where_the_clinician_signs(issued):
    """Pre-filling a name would put words in a reviewer's mouth; pre-filling the
    digest is the opposite -- it is the machine's job and they must not retype
    a 64-character hash."""
    body = json.loads((issued / "submission.json").read_text(encoding="utf-8"))
    assert body["catalogue_sha256"] == catalogue_digest()
    for field in ("reviewer_name", "reviewer_credentials", "reviewer_authority",
                  "reviewed_at"):
        assert body[field] == ""


def test_the_issued_sheet_leaves_every_answer_column_empty(issued):
    """A pre-filled disposition would be this repository's guess, returned to
    us as a clinician's judgement."""
    with (issued / "worklist.csv").open(encoding="utf-8-sig", newline="") as fh:
        rows = list(csv.DictReader(fh))
    assert len(rows) == 1887
    assert set(rows[0]) == {*CSV_READONLY, *CSV_FILLABLE}
    for row in rows:
        assert row["disposition"] == ""
        assert row["tags"] == ""
        assert row["rationale"] == ""


def test_the_sheet_is_written_where_excel_reads_it_correctly(issued):
    """Without the BOM, Excel on Windows reads UTF-8 as the local codepage and
    mangles every accented character in the exercise titles."""
    assert (issued / "worklist.csv").read_bytes().startswith(b"\xef\xbb\xbf")


def test_the_instructions_state_the_three_things_a_reader_could_get_wrong(issued):
    text = (issued / "HOW_TO_REVIEW.md").read_text(encoding="utf-8")
    assert "UNKNOWN` is a real answer" in text
    assert "NOT\nREVIEWED" in text or "NOT REVIEWED" in text
    assert "should carry no tags" in text
    for region in regions():                      # the vocabulary, spelled out
        assert region in text


def test_the_metadata_file_carries_no_duplicate_row_payload(issued):
    """Two copies of 1,887 rows disagree the moment one is edited, and nothing
    would say which is the review."""
    meta = json.loads((issued / "worklist.meta.json").read_text(encoding="utf-8"))
    assert "rows" not in meta
    assert meta["counts"]["total"] == 1887
    assert meta["catalogue_sha256"] == catalogue_digest()


# --------------------------------------------------------------------------
# drift -- the worklist in the tree must still describe the catalogue
# --------------------------------------------------------------------------


def test_the_checked_in_worklist_is_the_one_the_catalogue_produces():
    """Runs against the real tree. If the catalogue is edited and the sheet is
    not regenerated, a clinician reviews content that moved."""
    meta = verify_worklist(REPO / "core" / "review" / "worklist")
    assert meta["counts"]["total"] == 1887
    assert meta["catalogue_sha256"] == catalogue_digest()


def test_a_worklist_whose_metadata_drifted_is_refused(issued):
    meta = issued / "worklist.meta.json"
    body = json.loads(meta.read_text(encoding="utf-8"))
    body["counts"]["untagged"] = 0
    meta.write_text(json.dumps(body), encoding="utf-8")
    with pytest.raises(ClinicalImportError, match="not what the catalogue"):
        verify_worklist(issued)


def test_a_returned_review_committed_over_the_blank_sheet_is_named_as_such(issued):
    """The dangerous repair. Somebody commits the filled sheet, CI reports
    drift, and the obvious fix -- regenerate -- destroys a clinician's work.
    The refusal has to say what it is looking at."""
    _fill(issued, {i: ("ACCEPT", "", "") for i in _ids(4)})
    with pytest.raises(ClinicalImportError) as exc:
        verify_worklist(issued)
    assert "4 rows carry a disposition" in str(exc.value)
    assert "RETURNED review" in str(exc.value)
    assert "do not overwrite" in str(exc.value)


def test_a_worklist_that_is_simply_out_of_date_says_regenerate(issued):
    """The other branch: no dispositions, so regenerating is the right fix and
    the message must not warn about destroying work that is not there."""
    sheet = issued / "worklist.csv"
    lines = sheet.read_text(encoding="utf-8-sig").splitlines(keepends=True)
    sheet.write_text("".join(lines[:-1]), encoding="utf-8-sig")   # a row went
    with pytest.raises(ClinicalImportError, match="Regenerate it"):
        verify_worklist(issued)


def test_verifying_an_absent_worklist_is_refused_rather_than_passing(tmp_path):
    """A missing worklist must not read as a clean check."""
    with pytest.raises(ClinicalImportError, match="no worklist"):
        verify_worklist(tmp_path)


# --------------------------------------------------------------------------
# the boundary: what a validated submission does NOT mean
# --------------------------------------------------------------------------


def test_an_unreviewed_row_is_not_an_accepted_row():
    """The quiet failure this exists to prevent: 3 of 1,887 rows reviewed,
    reported as a validated clinical review of the catalogue."""
    result = validate(_submission())
    assert result["coverage"]["reviewed"] == 3
    assert result["coverage"]["not_reviewed"] == 1887 - 3
    assert "NOT REVIEWED" in result["coverage"]["note"]
    assert "accepted by default" in result["coverage"]["note"]


def test_a_valid_submission_closes_nothing():
    """D1 and H3 are closed by a decision about what the app does, not by a
    file passing a shape check."""
    result = validate(_submission())
    assert result["closes"] == []
    assert "D1" in result["does_not_close"]
    assert "H3 = HOLD" in result["does_not_close"]


def test_this_module_produces_no_training_label():
    """label_contract makes CLINICALLY_VALIDATED_LABEL raise on construction.
    A validated submission is a reviewed FILE; turning one into a label is a
    decision nobody has taken, and it must not arrive as a side effect."""
    assert "label_contract" not in _body()
    assert "Label(" not in _body()


def test_this_module_has_no_clinical_opinion_in_it():
    """The failure mode a green suite would hide: a heuristic quietly appears
    that maps content to a tag, and every submission afterwards measures it."""
    for banned in ("if 'knee' in", 'if "knee" in', "SAFE_FOR", "CONTRAINDICATED_IF"):
        assert banned not in _body(), f"a clinical heuristic appeared: {banned}"


def test_the_clinical_and_content_review_paths_stay_separate():
    """CT-1's importer refuses to ask whether an exercise is safe, and that
    refusal is load-bearing: a content reviewer must never be able to produce a
    clinical claim. One file with a boolean between them would end that."""
    ct1 = (REPO / "scripts" / "ct1" / "review_import.py").read_text(
        encoding="utf-8"
    )
    assert "clinical_import" not in ct1
    mine = (Path(__file__).resolve().parent / "clinical_import.py").read_text(
        encoding="utf-8"
    )
    assert "import review_import" not in mine
    assert "from review_import" not in mine
