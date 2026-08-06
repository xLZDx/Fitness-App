# -*- coding: utf-8 -*-
"""Rules for the per-group vendor request batch.

This file leaves the repository and is read by a third party, so the failures
worth guarding are the ones that would be embarrassing rather than merely
wrong: a repository path where a file name belongs, a blank notes column that
should not have been blank, a row from the wrong muscle group.
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent))
from build_vendor_request_batch import (  # noqa: E402
    COLUMNS,
    ambiguous_titles,
    build,
    cover_note,
    file_name,
    groups,
    load_gaps,
    version_counts,
)


@pytest.fixture(scope="module")
def rows():
    return load_gaps()


@pytest.fixture(scope="module")
def legs(rows):
    return build(rows, "Legs")


def test_the_batch_is_exactly_one_group(rows, legs):
    assert len(legs) == sum(1 for r in rows if r["group"] == "Legs")
    ids = {r["Internal ID"] for r in legs}
    others = {r["exercise_id"] for r in rows if r["group"] != "Legs"}
    assert not (ids & others)


def test_the_columns_are_the_ones_the_vendor_asked_for(legs):
    """Six fields, in their order.

    Equipment and difficulty exist in our source data and are deliberately
    absent: the exercise name already carries the variation, and a request is
    processed faster when it is the shape that was requested.
    """
    for row in legs:
        assert list(row.keys()) == COLUMNS


def test_a_file_name_is_a_file_name_not_our_path():
    """The single most likely embarrassing defect.

    Our column holds `exercises/men/Legs/<name>.mp4`. The directory part is our
    repository layout; pasting it into their Dropbox search finds nothing, and
    it silently tells them where our files live.
    """
    assert (
        file_name("exercises/men/Legs/barbell bulgarian split squat left side view.mp4")
        == "barbell bulgarian split squat left side view.mp4"
    )
    # Already bare -- must survive untouched rather than lose its first word.
    assert file_name("air squat.mp4") == "air squat.mp4"


def test_no_exported_row_carries_a_directory(legs):
    for row in legs:
        assert "/" not in row["Existing File Name"], row["Internal ID"]
        assert "\\" not in row["Existing File Name"], row["Internal ID"]


def test_every_row_names_the_missing_version_in_words(legs):
    """A person reads this column, so `female` is not the answer -- but an
    unrecognised value must survive rather than blank out, because a blank cell
    reads as "no version missing", which is the opposite of the truth."""
    assert {r["Missing Version"] for r in legs} <= {"Female", "Male"}
    assert all(r["Missing Version"] for r in legs)
    # The set alone would pass if `build` stamped "Female" on every row; the
    # per-row check that closes that hole is
    # `test_every_row_keeps_its_own_missing_version` below.


def test_nothing_essential_is_empty(legs):
    for row in legs:
        assert row["Internal ID"], row
        assert row["Exercise Name"], row
        assert row["Existing File Name"], row


def test_blank_notes_are_justified_by_measurement(legs):
    """The notes column ships blank. That is only defensible while no two names
    inside the batch collide, so it is checked rather than asserted once."""
    assert ambiguous_titles(legs) == []
    assert all(r["Variation Notes"] == "" for r in legs)


def test_a_collision_is_reported_rather_than_hidden():
    """The negative control for the rule above.

    Without it, `ambiguous_titles` could return `[]` unconditionally and every
    future batch would ship blank notes with nothing noticing.
    """
    batch = [
        {"Exercise Name": "Leg Press"},
        {"Exercise Name": "leg press"},
        {"Exercise Name": "Air Squat"},
    ]
    assert ambiguous_titles(batch) == ["leg press"]


def test_rows_are_sorted_for_a_human_reader(legs):
    names = [r["Exercise Name"].lower() for r in legs]
    assert names == sorted(names)


def test_the_cover_note_states_what_we_could_not_check(legs):
    """The vendor warned that their names are revised periodically, so part of
    this list may already exist under another name. We cannot check that from
    here, and the note must say so rather than let the file imply a verified
    list."""
    note = cover_note("Legs", legs, "2026-08-06", [])
    assert "not filtered this list" in note
    assert "222" in note
    assert "202 female" in note and "20 male" in note


def test_the_source_still_holds_every_group_we_promised(rows):
    """The next two batches come from the same file. If a group vanished or was
    renamed, this fails here rather than at send time."""
    present = groups(rows)
    assert present["Legs"] == 222
    assert present["Shoulders"] == 189
    assert present["Back"] == 128
    assert sum(present.values()) == 1235


# --- Added after the 2026-08-06 audit --------------------------------------
# Three reviewers between them found: a cover note that asserted "no duplicate
# names" unconditionally while `main` printed a warning nobody keeps, a frozen
# `--date` literal, and zero coverage of `main` and `write_xlsx` — the two
# functions that actually produce the deliverable.


def test_the_note_admits_collisions_instead_of_denying_them():
    """The finding that mattered most: this file leaves the building.

    `ambiguous_titles` detected clashes and `main` printed a WARNING, but
    `cover_note` took no clashes argument and stated flatly that none existed.
    A future group with duplicate titles would have shipped that false claim to
    a third party, with the script exiting 0 and printing "wrote".
    """
    batch = [
        {"Exercise Name": "Leg Press", "Missing Version": "Female"},
        {"Exercise Name": "leg press", "Missing Version": "Male"},
    ]
    clashes = ambiguous_titles(batch)
    assert clashes == ["leg press"]

    note = cover_note("Legs", batch, "2026-08-06", clashes)
    assert "no two exercise names collide" not in note
    assert "leg press" in note
    assert "ambiguous" in note


def test_the_note_still_says_so_when_there_is_nothing_to_admit(legs):
    note = cover_note("Legs", legs, "2026-08-06", [])
    assert "no two exercise names collide" in note


def test_a_windows_path_still_yields_a_bare_file_name():
    """Confirmed absent from today's data — 0 of 1,235 rows carry a backslash —
    and cheap to survive anyway, because the source CSV is regenerated on
    Windows and the failure is silent: the vendor would receive our repository
    layout instead of a filename."""
    assert file_name(r"exercises\men\Legs\air squat.mp4") == "air squat.mp4"
    assert file_name("exercises/men/Legs/air squat.mp4") == "air squat.mp4"


def test_no_row_in_any_group_would_leak_a_path(rows):
    # The shipped test only covered Legs. Shoulders and Back go out next.
    for r in rows:
        name = file_name(r["existing_reference_clip"])
        assert "/" not in name and "\\" not in name, r["exercise_id"]


def test_the_date_default_is_computed_not_frozen():
    """It was `default="2026-08-06"`. A Shoulders run next month would have
    stamped itself with today's date in both the filename and the letter."""
    src = (Path(__file__).parent / "build_vendor_request_batch.py").read_text(
        encoding="utf-8"
    )
    assert 'default="2026-08-06"' not in src
    assert "datetime.date.today().isoformat()" in src


def test_main_writes_all_three_files(tmp_path, monkeypatch):
    """`main` and `write_xlsx` had no coverage at all — between them they do the
    argument handling, the validation and every write."""
    import build_vendor_request_batch as mod

    monkeypatch.setattr(mod, "OUT_DIR", tmp_path)
    monkeypatch.setattr(
        sys, "argv", ["x", "--group", "Legs", "--date", "2026-01-02", "--write"]
    )
    assert mod.main() == 0

    stem = tmp_path / "legs_2026-01-02"
    for ext in (".csv", ".md", ".xlsx"):
        assert stem.with_suffix(ext).exists(), ext
    assert stem.with_suffix(".xlsx").stat().st_size > 1000

    import csv as _csv

    with stem.with_suffix(".csv").open(encoding="utf-8", newline="") as f:
        written = list(_csv.DictReader(f))
    assert len(written) == 222
    assert list(written[0].keys()) == COLUMNS


def test_a_dry_run_writes_nothing(tmp_path, monkeypatch):
    import build_vendor_request_batch as mod

    monkeypatch.setattr(mod, "OUT_DIR", tmp_path)
    monkeypatch.setattr(sys, "argv", ["x", "--group", "Legs"])
    assert mod.main() == 0
    assert list(tmp_path.iterdir()) == []


def test_an_unknown_group_exits_nonzero_without_writing(tmp_path, monkeypatch):
    import build_vendor_request_batch as mod

    monkeypatch.setattr(mod, "OUT_DIR", tmp_path)
    monkeypatch.setattr(
        sys, "argv", ["x", "--group", "Elbows", "--write"]
    )
    assert mod.main() == 1
    assert list(tmp_path.iterdir()) == []


def test_a_malformed_date_is_refused(tmp_path, monkeypatch):
    """It is concatenated straight into the output path."""
    import build_vendor_request_batch as mod

    monkeypatch.setattr(mod, "OUT_DIR", tmp_path)
    monkeypatch.setattr(
        sys, "argv", ["x", "--group", "Legs", "--date", "../../etc", "--write"]
    )
    assert mod.main() == 1
    assert list(tmp_path.iterdir()) == []


def test_every_row_keeps_its_own_missing_version(rows, legs):
    """The weak assertion the reviewer named: checking that the SET of values is
    a subset of {Female, Male} would pass if `build` stamped "Female" on every
    row. This checks each row against its own source."""
    source = {
        r["exercise_id"]: r["missing_version"] for r in rows if r["group"] == "Legs"
    }
    for row in legs:
        want = {"female": "Female", "male": "Male"}[source[row["Internal ID"]]]
        assert row["Missing Version"] == want, row["Internal ID"]


def test_the_values_are_under_the_right_keys(rows, legs):
    """The other weak assertion: matching the six key names says nothing about
    whether Exercise Name and Existing File Name got swapped."""
    source = {r["exercise_id"]: r for r in rows if r["group"] == "Legs"}
    for row in legs:
        src = source[row["Internal ID"]]
        assert row["Exercise Name"] == src["title_en"]
        assert row["Existing File Name"] == file_name(src["existing_reference_clip"])
