# -*- coding: utf-8 -*-
"""Tests for the catalog generator's write path.

Every case is about one question: what does a rebuild destroy? The answer used
to be "every field this script does not produce", which by the time it was
noticed meant 1,887 posters and 1,384 equipment links, and would have meant
weeks of contraindication tagging.

    python -m pytest scripts/catalog/test_build_vendor_catalog.py -q
"""
from __future__ import annotations

import json
from pathlib import Path

import pytest

import build_vendor_catalog
from build_vendor_catalog import CURATED, merge_rows

ROOT = Path(__file__).resolve().parents[2]
SHIPPED = ROOT / "mobile" / "assets" / "data" / "exercises_vendor.json"


def generated(exercise_id: str, **overrides) -> dict:
    """A row shaped the way `build()` emits one: no `poster` key at all, and
    `equipmentId` explicitly null."""
    row = {
        "id": exercise_id,
        "title": exercise_id.title(),
        "equipmentId": None,
        "muscles": ["core"],
        "primaryMuscles": ["core"],
        "difficulty": "beginner",
        "durationMinutes": 10,
        "summary": "",
        "steps": [],
        "video": {"men": f"vendor/men/{exercise_id}.mp4"},
        "isStretch": False,
        "vendorGroup": "Abdominals",
        "equipmentLabel": "Unknown",
    }
    row.update(overrides)
    return row


class TestFieldsWeDoNotProduce:
    def test_a_poster_survives_a_rebuild(self):
        # The live bug: `make_vendor_posters.py` writes `poster` back into the
        # catalog, this script has never emitted it, and --write replaced the
        # file wholesale.
        on_disk = generated("ea_plank", poster={"men": "assets/posters/men/ea_plank.jpg"})
        merged, _ = merge_rows([generated("ea_plank")], [on_disk])
        assert merged[0]["poster"] == {"men": "assets/posters/men/ea_plank.jpg"}

    def test_a_field_nobody_has_invented_yet_survives(self):
        # The rule is "keys we do not produce", not a list of known ones --
        # otherwise every future pass re-learns this the expensive way.
        on_disk = generated("ea_plank", licence="CC-BY-4.0")
        merged, _ = merge_rows([generated("ea_plank")], [on_disk])
        assert merged[0]["licence"] == "CC-BY-4.0"

    def test_a_field_we_stopped_producing_is_kept(self):
        # Stale tips beat deleted tips: the vendor sheet losing a row should
        # not silently empty the app's screen.
        on_disk = generated("ea_plank", tips=["Brace the core"])
        merged, _ = merge_rows([generated("ea_plank")], [on_disk])
        assert merged[0]["tips"] == ["Brace the core"]


class TestCuratedFields:
    def test_our_null_equipment_id_does_not_overwrite_a_real_link(self):
        on_disk = generated("ea_plank", equipmentId="eq_ab_bench")
        merged, _ = merge_rows([generated("ea_plank")], [on_disk])
        assert merged[0]["equipmentId"] == "eq_ab_bench"

    def test_contraindications_survive(self):
        # The field the whole remediation is about. It has no producer yet, so
        # this is the test that has to exist before the tagging starts rather
        # than after it is lost.
        on_disk = generated("ea_plank", contraindications=["lower_back"])
        merged, _ = merge_rows([generated("ea_plank")], [on_disk])
        assert merged[0]["contraindications"] == ["lower_back"]

    def test_pose_target_ids_survive(self):
        # `poseTargetId` is written by `tag_pose_targets.py` and never by this
        # script, so a rebuild without it in CURATED drops all 570 tags in
        # silence: the exercises simply stop offering the Form Coach, nothing
        # fails, nothing is logged.
        on_disk = generated("ea_air_squat", poseTargetId="squat")
        merged, _ = merge_rows([generated("ea_air_squat")], [on_disk])
        assert merged[0]["poseTargetId"] == "squat"

    def test_curated_names_every_field(self):
        # A guard, and it earned its keep: adding `poseTargetId` to CURATED
        # failed here first, which is what this line is for. Update it
        # deliberately, never to make a run go green.
        assert CURATED == {"equipmentId", "contraindications", "poseTargetId"}


class TestGeneratedFieldsStillWin:
    def test_a_corrected_title_lands(self):
        # The merge must not become a write-once file: fixing `tidy_title` or
        # the muscle aliases has to reach the catalog on the next run.
        on_disk = generated("ea_plank", title="ea plank", muscles=[])
        merged, _ = merge_rows(
            [generated("ea_plank", title="Ea Plank", muscles=["core"])], [on_disk]
        )
        assert merged[0]["title"] == "Ea Plank"
        assert merged[0]["muscles"] == ["core"]

    def test_a_new_exercise_passes_straight_through(self):
        merged, _ = merge_rows([generated("ea_new")], [])
        assert len(merged) == 1
        assert merged[0]["id"] == "ea_new"
        assert merged[0]["equipmentId"] is None

    def test_order_follows_the_generated_list(self):
        merged, _ = merge_rows(
            [generated("ea_a"), generated("ea_b")], [generated("ea_b")]
        )
        assert [r["id"] for r in merged] == ["ea_a", "ea_b"]


class TestDropReporting:
    def test_a_row_that_stops_being_generated_is_named(self):
        # Not silently kept and not silently deleted: reported, so `main()` can
        # refuse the write. An empty bundle zip otherwise wipes the catalog and
        # every test downstream reads the empty file as the truth.
        _, dropped = merge_rows([generated("ea_a")], [generated("ea_a"), generated("ea_gone")])
        assert dropped == ["ea_gone"]

    def test_nothing_dropped_is_an_empty_list(self):
        _, dropped = merge_rows([generated("ea_a")], [generated("ea_a")])
        assert dropped == []


class TestTheWritePath:
    """`main()` end to end, with `build()` stubbed.

    The vendor zip and metadata sheet live outside the repo and are absent on
    most machines, so `build()` cannot run here. Stubbing it is the only way
    the drop guard -- the part that decides whether a write is allowed to
    destroy anything -- gets exercised at all rather than being reasoned about.
    """

    @pytest.fixture
    def catalog(self, tmp_path, monkeypatch):
        out = tmp_path / "exercises_vendor.json"
        monkeypatch.setattr(build_vendor_catalog, "OUT", out)
        return out

    def _run(self, monkeypatch, rows, argv):
        monkeypatch.setattr(build_vendor_catalog, "build", lambda: rows)
        monkeypatch.setattr("sys.argv", ["build_vendor_catalog.py", *argv])
        build_vendor_catalog.main()

    def test_writing_over_an_absent_file_just_writes(self, catalog, monkeypatch):
        self._run(monkeypatch, [generated("ea_a")], ["--write"])
        assert json.loads(catalog.read_text(encoding="utf-8"))[0]["id"] == "ea_a"

    def test_a_write_preserves_curated_fields_on_disk(self, catalog, monkeypatch):
        catalog.write_text(
            json.dumps([generated("ea_a", poster={"men": "p.jpg"}, equipmentId="eq_1")]),
            encoding="utf-8",
        )
        self._run(monkeypatch, [generated("ea_a")], ["--write"])
        row = json.loads(catalog.read_text(encoding="utf-8"))[0]
        assert row["poster"] == {"men": "p.jpg"}
        assert row["equipmentId"] == "eq_1"

    def test_a_write_that_would_drop_a_row_refuses(self, catalog, monkeypatch):
        before = json.dumps([generated("ea_a"), generated("ea_keep")])
        catalog.write_text(before, encoding="utf-8")
        with pytest.raises(SystemExit) as exit_info:
            self._run(monkeypatch, [generated("ea_a")], ["--write"])
        # A string exit code is a non-zero exit status carrying that message.
        assert "refusing to write" in str(exit_info.value)
        assert "ea_keep" not in str(exit_info.value)  # the ids go to stdout
        # Refused means refused: the file is untouched, not truncated first.
        assert catalog.read_text(encoding="utf-8") == before

    def test_allow_drop_lets_the_removal_through(self, catalog, monkeypatch):
        catalog.write_text(
            json.dumps([generated("ea_a"), generated("ea_keep")]), encoding="utf-8"
        )
        self._run(monkeypatch, [generated("ea_a")], ["--write", "--allow-drop"])
        rows = json.loads(catalog.read_text(encoding="utf-8"))
        assert [r["id"] for r in rows] == ["ea_a"]

    def test_without_write_nothing_is_written(self, catalog, monkeypatch):
        self._run(monkeypatch, [generated("ea_a")], [])
        assert not catalog.exists()

    def test_the_measure_run_reports_safety_coverage(self, catalog, monkeypatch, capsys):
        # The counter that did not exist: six coverage numbers were printed on
        # every run and `contraindications` was not one of them, so nobody
        # watching the build output could have seen it sitting at zero.
        catalog.write_text(
            json.dumps([generated("ea_a", contraindications=["knee"])]), encoding="utf-8"
        )
        self._run(monkeypatch, [generated("ea_a")], [])
        assert "with safety tags 1" in capsys.readouterr().out


class TestAgainstTheRealCatalog:
    """The regression as it actually exists on disk, not a model of it."""

    def test_rebuilding_the_shipped_catalog_loses_nothing(self):
        on_disk = json.loads(SHIPPED.read_text(encoding="utf-8"))
        assert on_disk, "shipped catalog is empty"

        # Exactly what `build()` produces for these rows: no poster, null link.
        as_generated = []
        for row in on_disk:
            copy = {k: v for k, v in row.items() if k != "poster"}
            copy["equipmentId"] = None
            as_generated.append(copy)

        merged, dropped = merge_rows(as_generated, on_disk)

        assert dropped == []
        assert len(merged) == len(on_disk)
        posters_before = sum(1 for r in on_disk if r.get("poster"))
        links_before = sum(1 for r in on_disk if r.get("equipmentId"))
        assert sum(1 for r in merged if r.get("poster")) == posters_before
        assert sum(1 for r in merged if r.get("equipmentId")) == links_before
        assert merged == on_disk

    def test_the_shipped_catalog_would_have_lost_everything_before_this_fix(self):
        # States the size of the bug so a future reader does not have to trust
        # the docstring. If either number reaches 0 legitimately, this test is
        # the place to find out that the fix stopped being load-bearing.
        on_disk = json.loads(SHIPPED.read_text(encoding="utf-8"))
        assert sum(1 for r in on_disk if r.get("poster")) > 0
        assert sum(1 for r in on_disk if r.get("equipmentId")) > 0


class TestTheSafetyVocabulary:
    """S3a: which `contraindications` tags are legal, answered mechanically.

    A tag outside the vocabulary is worse than a missing one. `isContraindicated`
    compares it against `InjuryRegion.tag` exactly, so a typo screens for nobody
    -- and the row still counts as covered in every number the builder prints,
    including the ratchet the tagging batches are graded on.
    """

    def test_the_vocabulary_is_the_nine_regions(self):
        vocabulary = build_vendor_catalog.load_vocabulary()
        assert vocabulary == {
            "neck",
            # Ninth, added 2026-08-12 for the redesign's body diagram, which
            # offers upper back as its own zone. Legal to write from this
            # commit forward; nothing carries it yet, which is a tagging batch,
            # not a defect -- see the coverage assertion in
            # test_tag_contraindications.py.
            "upper_back",
            "shoulder",
            "elbow",
            "wrist",
            "lower_back",
            "hip",
            "knee",
            "ankle",
        }

    def test_a_legal_tag_is_accepted(self):
        rows = [generated("ea_a", contraindications=["knee"])]
        assert build_vendor_catalog.invalid_tags(
            rows, build_vendor_catalog.load_vocabulary()
        ) == []

    def test_a_typo_is_caught_with_its_row(self):
        rows = [generated("ea_a", contraindications=["kneee"])]
        assert build_vendor_catalog.invalid_tags(
            rows, build_vendor_catalog.load_vocabulary()
        ) == [("ea_a", "kneee")]

    def test_the_unnormalised_form_is_caught_too(self):
        # "lower back" and "lower_back" are the same region to a human and two
        # different strings to a set membership test. Only the region's own tag
        # may be written.
        rows = [generated("ea_a", contraindications=["lower back"])]
        assert build_vendor_catalog.invalid_tags(
            rows, build_vendor_catalog.load_vocabulary()
        ) == [("ea_a", "lower back")]

    def test_rows_without_tags_are_not_offenders(self):
        rows = [generated("ea_a"), generated("ea_b", contraindications=[])]
        assert build_vendor_catalog.invalid_tags(
            rows, build_vendor_catalog.load_vocabulary()
        ) == []

    def test_the_shipped_catalog_is_clean(self):
        on_disk = json.loads(SHIPPED.read_text(encoding="utf-8"))
        assert build_vendor_catalog.invalid_tags(
            on_disk, build_vendor_catalog.load_vocabulary()
        ) == []


class TestTheWriteRefusesBadTags(TestTheWritePath):
    """The guard, not just the detector.

    Inherits the stubbed-`build()` harness above for the same reason it exists:
    the vendor bundle is absent on this machine, so `main()` cannot otherwise be
    exercised end to end.
    """

    def test_a_bad_tag_blocks_the_write(self, catalog, monkeypatch):
        with pytest.raises(SystemExit) as exit_info:
            self._run(
                monkeypatch,
                [generated("ea_a", contraindications=["kneee"])],
                ["--write"],
            )
        assert "match no InjuryRegion" in str(exit_info.value)
        assert not catalog.exists(), "nothing may be written when a tag is bad"

    def test_allow_drop_does_not_also_wave_through_a_bad_tag(
        self, catalog, monkeypatch
    ):
        # Two different guards. Dropping rows can be legitimate -- a shrunken
        # bundle -- so it is overridable; a tag matching no region never is, and
        # sharing one flag would have made the override reach both.
        with pytest.raises(SystemExit):
            self._run(
                monkeypatch,
                [generated("ea_a", contraindications=["kneee"])],
                ["--write", "--allow-drop"],
            )
        assert not catalog.exists()

    def test_a_good_tag_writes_normally(self, catalog, monkeypatch):
        self._run(
            monkeypatch, [generated("ea_a", contraindications=["knee"])], ["--write"]
        )
        row = json.loads(catalog.read_text(encoding="utf-8"))[0]
        assert row["contraindications"] == ["knee"]
