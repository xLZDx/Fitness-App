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
    note = cover_note("Legs", legs, "2026-08-06")
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
