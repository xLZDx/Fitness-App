# -*- coding: utf-8 -*-
"""External clinical review — the worklist to send, and the validator for what comes back.

    python scripts/review/clinical_import.py --worklist core/review/worklist
    python scripts/review/clinical_import.py --check <submission.json>
    python -m pytest scripts/review/test_clinical_import.py -q

``D1 = EXTERNAL_CLINICAL_VALIDATION_REQUIRED`` and ``H3 = HOLD``. This module
does not close either and cannot: it validates STRUCTURE and PROVENANCE and has
no opinion whatsoever about which tag belongs on which exercise. That judgement
is the thing this repository does not have and must not simulate.

## Why it exists

An independent review asked whether a real clinician could start work on Monday
morning using only ``core/review/CLINICAL_VALIDATION_HANDOFF.md``. They could
not. Five of the six blockers needed no clinical judgement at all:

* the handoff bound a review to a BRANCH, which moves;
* there was no row-level worklist — the 360 untagged rows existed only as an
  absence inside a 3 MB JSON, and the 1,527 tagged ones only as nine CSVs keyed
  by region rather than by row;
* the review format was prose: no template, no schema, no import path;
* there was no field anywhere in the repository for a reviewer's credentials or
  authority — the CT-1 importer records ``reviewer_kind`` and nothing else,
  deliberately, because it handles content and not clinical review;
* the rule vocabulary was readable only as Python.

Those are engineering. This is the engineering.

## Why it is NOT the CT-1 importer with a flag

``scripts/ct1/review_import.py`` refuses to ask whether an exercise is safe, in
its own docstring, and that refusal is load-bearing: a content reviewer must
never be able to produce a clinical claim. Adding a mode to it would put the
two authorities in one file with a boolean between them. They stay separate.

The strongest structural expression of that: ``label_contract`` makes
``CLINICALLY_VALIDATED_LABEL`` raise on construction. This module produces no
``Label`` at all. A validated clinical submission is a reviewed FILE, and
turning one into a training label is a decision nobody has taken.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[2]
CATALOGUE = REPO / "mobile" / "assets" / "data" / "exercises_vendor.json"
REGIONS_FILE = REPO / "scripts" / "catalog" / "injury_regions.json"

SCHEMA_VERSION = 1

#: What a clinician may say about one row.
#:
#: ``UNKNOWN`` is not a failure to answer. It is the answer for a row whose
#: content does not let anyone decide, and forcing a disposition on it would
#: manufacture a clinical judgement — the same reason CT-1's content review has
#: ``unsure``, applied to a domain where the cost of manufacturing one is far
#: higher.
DISPOSITIONS = ("ACCEPT", "REJECT", "AMEND", "UNKNOWN")

#: Fields a submission must carry before anything in it is read.
SUBMISSION_FIELDS = (
    "schema_version", "handoff_commit", "catalogue_sha256",
    "reviewer_name", "reviewer_credentials", "reviewer_authority",
    "reviewed_at", "rows",
)

#: Fields every reviewed row must carry.
ROW_FIELDS = ("item_id", "disposition")


class ClinicalImportError(ValueError):
    """A submission that would let an unvalidated claim look validated."""


def regions() -> list[str]:
    """The nine-region vocabulary, read from its file rather than restated.

    Strict about the key: a tolerant fallback here would silently accept a
    renamed field and validate submissions against an empty or wrong
    vocabulary, which is the failure mode where every tag looks valid.
    """
    data = json.loads(REGIONS_FILE.read_text(encoding="utf-8"))
    tags = data.get("tags") if isinstance(data, dict) else None
    if not tags:
        raise ClinicalImportError(
            f"{REGIONS_FILE.name} has no `tags` list. Its source of truth is "
            "the Dart enum InjuryRegion; this validator will not guess a "
            "vocabulary, because an empty one makes every tag look valid"
        )
    return sorted(str(t) for t in tags)


def catalogue_digest() -> str:
    return hashlib.sha256(CATALOGUE.read_bytes()).hexdigest()


def _rows() -> list[dict[str, Any]]:
    data = json.loads(CATALOGUE.read_text(encoding="utf-8"))
    if isinstance(data, dict):
        data = data.get("exercises") or data.get("items") or []
    return [r for r in data if isinstance(r, dict) and r.get("id")]


def worklist() -> dict[str, Any]:
    """One row per exercise, with what it is currently tagged and what that means.

    Deliberately covers BOTH populations. Q2 is about the 1,527 rows the rules
    tagged and Q3 is about the 360 they did not, and a worklist containing only
    the untagged ones would silently answer Q2 by omission.
    """
    seen: set[str] = set()
    rows = []
    for r in _rows():
        rid = r["id"]
        if rid in seen:
            continue
        seen.add(rid)
        tags = sorted(r.get("contraindications") or [])
        rows.append({
            "item_id": rid,
            "title": r.get("title"),
            "summary": r.get("summary"),
            "steps": list(r.get("steps") or []),
            "equipment_id": r.get("equipmentId"),
            "primary_muscles": list(r.get("primaryMuscles") or []),
            "vendor_group": r.get("vendorGroup"),
            "is_stretch": bool(r.get("isStretch")),
            "current_tags": tags,
            "population": "TAGGED" if tags else "UNTAGGED",
            # The behaviour under review, stated per row rather than left in a
            # section the reader may not reach. Corrected 2026-08-17: an
            # untagged row is SHOWN, not withheld.
            "current_app_behaviour": (
                "Removed from the library of a user whose declared injury "
                "region intersects these tags."
                if tags else
                "SHOWN to every user, including one with a declared injury. "
                "It carries no tag to screen against and the app does not tell "
                "the user it could not screen it. This is finding F013: the "
                "behaviour is reproduced and verified; its severity is what Q3 "
                "asks you to judge."
            ),
        })
    return {
        "schema_version": SCHEMA_VERSION,
        "handoff_commit": _commit(),
        "catalogue_sha256": catalogue_digest(),
        "catalogue_bytes": CATALOGUE.stat().st_size,
        "regions": regions(),
        "dispositions": list(DISPOSITIONS),
        "rows": rows,
        "counts": {
            "total": len(rows),
            "tagged": sum(1 for r in rows if r["population"] == "TAGGED"),
            "untagged": sum(1 for r in rows if r["population"] == "UNTAGGED"),
        },
        "authority": (
            "This worklist asks for a CLINICAL judgement and this repository "
            "cannot supply one. Nothing generated here proposes a tag value, "
            "and no agent, model or heuristic may fill in a disposition. "
            "D1 = EXTERNAL_CLINICAL_VALIDATION_REQUIRED; H3 = HOLD."
        ),
    }


#: The three columns a clinician fills, and the ones they read.
#:
#: CSV rather than JSON because the reviewer is a clinician with a spreadsheet,
#: not a programmer with an editor. The read-only columns come first so the row
#: is legible left to right, and the fillable ones are last and empty, so an
#: unfilled row is visibly unfilled rather than defaulted.
CSV_READONLY = (
    "item_id", "population", "current_tags", "title", "summary", "steps",
    "equipment_id", "current_app_behaviour",
)
CSV_FILLABLE = ("disposition", "tags", "rationale")


def write_worklist(directory: Path) -> dict[str, Any]:
    """Write the worklist a clinician receives: the data, and a sheet to fill."""
    import csv

    payload = worklist()
    directory.mkdir(parents=True, exist_ok=True)

    # Metadata only. The rows live in the CSV and nowhere else: a JSON twin of
    # 1,887 rows would be 2.3 MB of derived duplicate, and the moment somebody
    # edits one copy the two disagree with no way to tell which is the review.
    (directory / "worklist.meta.json").write_text(
        json.dumps({k: v for k, v in payload.items() if k != "rows"},
                   ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    # utf-8-sig: Excel on Windows reads a BOM-less UTF-8 CSV as the local
    # codepage and mangles every non-ASCII character in the exercise titles.
    with (directory / "worklist.csv").open(
        "w", encoding="utf-8-sig", newline=""
    ) as fh:
        out = csv.writer(fh)
        out.writerow([*CSV_READONLY, *CSV_FILLABLE])
        for row in payload["rows"]:
            out.writerow([
                row["item_id"],
                row["population"],
                " ".join(row["current_tags"]),
                row["title"] or "",
                row["summary"] or "",
                " ".join(row["steps"]),
                row["equipment_id"] or "",
                row["current_app_behaviour"],
                "", "", "",
            ])

    (directory / "submission.json").write_text(
        json.dumps({
            "schema_version": SCHEMA_VERSION,
            "handoff_commit": payload["handoff_commit"],
            "catalogue_sha256": payload["catalogue_sha256"],
            "reviewer_name": "",
            "reviewer_credentials": "",
            "reviewer_authority": "",
            "reviewed_at": "",
            "rows_csv": "worklist.csv",
        }, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    (directory / "HOW_TO_REVIEW.md").write_text(_instructions(payload), "utf-8")
    return payload


def verify_worklist(directory: Path) -> dict[str, Any]:
    """Refuse a committed worklist that no longer describes the catalogue.

    The drift that matters: somebody edits an exercise, the checked-in sheet
    still says 1,887 rows and still names the old digest, and a clinician
    reviews content that moved. Regenerating and comparing makes that a CI
    failure rather than a discovery — the same contract the CT-1 review batch
    already holds itself to.
    """
    import csv
    import tempfile

    meta_path = directory / "worklist.meta.json"
    if not meta_path.exists():
        raise ClinicalImportError(f"{directory} holds no worklist to verify")
    committed_meta = json.loads(meta_path.read_text(encoding="utf-8"))

    with tempfile.TemporaryDirectory() as tmp:
        fresh = Path(tmp)
        write_worklist(fresh)
        rebuilt_meta = json.loads(
            (fresh / "worklist.meta.json").read_text(encoding="utf-8")
        )
        # `handoff_commit` moves with every commit and is not a claim about the
        # content, so it is excluded — the same exclusion the review batch
        # makes for `source_commit`.
        for m in (committed_meta, rebuilt_meta):
            m.pop("handoff_commit", None)
        if committed_meta != rebuilt_meta:
            raise ClinicalImportError(
                "the checked-in worklist metadata is not what the catalogue "
                "produces today. Either the catalogue changed without the "
                "worklist being regenerated -- in which case any review in "
                "flight is reviewing content that moved -- or the file was "
                "hand-edited"
            )
        a = (directory / "worklist.csv").read_bytes()
        b = (fresh / "worklist.csv").read_bytes()
        if a != b:
            with (directory / "worklist.csv").open(
                encoding="utf-8-sig", newline=""
            ) as fh:
                filled = sum(
                    1 for r in csv.DictReader(fh)
                    if (r.get("disposition") or "").strip()
                )
            raise ClinicalImportError(
                "the checked-in worklist.csv is not the one the catalogue "
                "produces today"
                + (
                    f". {filled} rows carry a disposition: this looks like a "
                    "RETURNED review committed over the blank sheet. Keep it "
                    "somewhere else and reissue -- do not overwrite a "
                    "clinician's work by regenerating"
                    if filled else ". Regenerate it with --worklist"
                )
            )
    return committed_meta


def _instructions(payload: dict[str, Any]) -> str:
    return f"""# How to review

Two files. Fill both, send both back.

## 1. `worklist.csv` — {payload['counts']['total']} rows

Open it in a spreadsheet. The first eight columns are what the app currently
holds; the last three are yours:

| Column | What to put in it |
|---|---|
| `disposition` | one of `ACCEPT`, `REJECT`, `AMEND`, `UNKNOWN` |
| `tags` | **only** when the disposition is `AMEND`: the tags this row should carry, space-separated, drawn from the list below. Leave empty for the other three. An `AMEND` with an empty `tags` cell means *this row should carry no tags* — that is a real answer and it is not the same as leaving the row blank. |
| `rationale` | free text, optional |

The vocabulary, and nothing outside it — a tag the app cannot match is
invisible to every safety filter, so it looks like a screened row and behaves
like an unscreened one:

    {' '.join(payload['regions'])}

**`UNKNOWN` is a real answer.** A row whose content does not let anyone decide
should be marked `UNKNOWN`, not guessed at. Nothing downstream treats it as a
failure to answer.

**Leave a row blank if you did not review it.** A blank row is recorded as NOT
REVIEWED. It is never recorded as accepted, and a partial review is welcome —
a partial review recorded as a whole one is not.

## 2. `submission.json`

Seven lines. Your name, your registration and issuing body, what you are
entitled to sign off on, and the date. `catalogue_sha256` and `handoff_commit`
are filled in already: they pin this review to the exact bytes you reviewed,
so please do not edit them.

The credentials and authority fields are required and the import refuses a
submission without them. That is deliberate: an anonymous clinical review
cannot be attributed to anybody, and this repository has no way to tell a
clinician's judgement from a developer's guess except by who signed it.

## 3. Send it back

Both files. It is checked with:

    python scripts/review/clinical_import.py --check submission.json

That check is a **structural** one — required fields, a tag vocabulary, rows
that exist, no row reviewed twice, and the catalogue digest. It has no opinion
whatsoever about which tag belongs on which exercise. That judgement is the
thing we are asking you for and the thing we must not manufacture.

If the catalogue changes before your review comes back, the check refuses the
submission as STALE and we reissue the worklist. Your work is not discarded.
"""


def _commit() -> str:
    import subprocess
    try:
        return subprocess.run(
            ["git", "-C", str(REPO), "rev-parse", "HEAD"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except Exception:
        return "UNKNOWN"


def _timestamp(value: Any, where: str) -> dt.datetime:
    if not isinstance(value, str) or not value:
        raise ClinicalImportError(f"{where}: a timestamp is required")
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ClinicalImportError(
            f"{where}: {value!r} is not an ISO-8601 timestamp"
        ) from exc
    if parsed.tzinfo is None:
        raise ClinicalImportError(
            f"{where}: {value!r} has no UTC offset, so it cannot be ordered "
            "against a catalogue change"
        )
    return parsed


def load_submission(path: Path) -> dict[str, Any]:
    """Read a submission, pulling its rows from the filled spreadsheet."""
    import csv

    body = json.loads(path.read_text(encoding="utf-8"))
    source = body.pop("rows_csv", None)
    if source is None:
        return body
    if "rows" in body:
        raise ClinicalImportError(
            "this submission carries both `rows` and `rows_csv`. Which one is "
            "the review is a question this file cannot answer"
        )

    sheet = (path.parent / source).resolve()
    if not sheet.exists():
        raise ClinicalImportError(
            f"rows_csv points at {source!r}, which is not beside "
            f"{path.name}. Send the filled spreadsheet back with it"
        )
    rows = []
    with sheet.open(encoding="utf-8-sig", newline="") as fh:
        for line in csv.DictReader(fh):
            for column in (*CSV_READONLY, *CSV_FILLABLE):
                if column not in line:
                    raise ClinicalImportError(
                        f"{source}: column {column!r} is missing. This is not "
                        "the worklist that was issued -- columns were removed "
                        "or renamed, and a review of a sheet nobody sent "
                        "cannot be tied to a catalogue version"
                    )
            disposition = (line["disposition"] or "").strip()
            if not disposition:
                # An unfilled row is NOT REVIEWED. Never accepted by default.
                continue
            entry: dict[str, Any] = {
                "item_id": (line["item_id"] or "").strip(),
                "disposition": disposition.upper(),
                "rationale": (line["rationale"] or "").strip() or None,
            }
            # An empty cell on an AMEND row means "this row should carry no
            # tags", which is a real answer; on any other disposition it means
            # the reviewer left it alone, and sending [] would be read as an
            # amendment they did not make.
            if entry["disposition"] == "AMEND":
                entry["tags"] = (line["tags"] or "").split()
            elif (line["tags"] or "").strip():
                entry["tags"] = (line["tags"] or "").split()
            rows.append(entry)
    body["rows"] = rows
    return body


def validate(submission: dict[str, Any]) -> dict[str, Any]:
    """Structure and provenance only. No opinion about any clinical content."""
    missing = [f for f in SUBMISSION_FIELDS if f not in submission]
    if missing:
        raise ClinicalImportError(
            f"submission is missing {missing}. A partly identified review "
            "cannot be attributed, and an unattributed clinical review is not "
            "a clinical review"
        )
    if submission["schema_version"] != SCHEMA_VERSION:
        raise ClinicalImportError(
            f"schema v{submission['schema_version']!r}; this validator is "
            f"v{SCHEMA_VERSION}"
        )

    for field in ("reviewer_name", "reviewer_credentials", "reviewer_authority"):
        value = submission.get(field)
        if not isinstance(value, str) or not value.strip():
            raise ClinicalImportError(
                f"{field} is required and must not be blank. This is the field "
                "CT-1's content importer deliberately does NOT have: a content "
                "reviewer needs no licence and a clinical one does, and the "
                "distinction has to survive being written down"
            )

    _timestamp(submission.get("reviewed_at"), "reviewed_at")

    current = catalogue_digest()
    if submission["catalogue_sha256"] != current:
        raise ClinicalImportError(
            f"this review names catalogue {submission['catalogue_sha256'][:12]}"
            f"..., the file on disk is {current[:12]}.... The catalogue changed "
            "after the worklist was issued, so this review describes content "
            "that is no longer there. STALE -- reissue the worklist. It is NOT "
            "imported and it is NOT discarded"
        )

    known = {r["id"] for r in _rows()}
    vocabulary = set(regions())
    seen: set[str] = set()
    accepted: list[dict[str, Any]] = []

    rows = submission.get("rows")
    if not isinstance(rows, list) or not rows:
        raise ClinicalImportError("a submission with no reviewed rows is not a review")

    for entry in rows:
        if not isinstance(entry, dict):
            raise ClinicalImportError(
                f"a reviewed row is {type(entry).__name__}, not an object"
            )
        for field in ROW_FIELDS:
            if field not in entry:
                raise ClinicalImportError(f"a reviewed row is missing {field!r}")
        item_id = entry["item_id"]
        if item_id not in known:
            raise ClinicalImportError(
                f"{item_id!r} is not an exercise in this catalogue. A review "
                "of a row that does not exist cannot be applied to anything"
            )
        if item_id in seen:
            raise ClinicalImportError(
                f"{item_id!r} is reviewed twice. Which entry is the review is "
                "a question this file cannot answer"
            )
        seen.add(item_id)

        disposition = entry["disposition"]
        if disposition not in DISPOSITIONS:
            raise ClinicalImportError(
                f"{item_id}: disposition {disposition!r} is not one of "
                f"{DISPOSITIONS}"
            )

        tags = entry.get("tags")
        if disposition in ("ACCEPT", "REJECT", "UNKNOWN") and tags is not None:
            raise ClinicalImportError(
                f"{item_id}: only AMEND carries tags. {disposition} with a tag "
                "list is ambiguous about whether the tags are the new value or "
                "a restatement of the old one"
            )
        if disposition == "AMEND":
            if not isinstance(tags, list):
                raise ClinicalImportError(
                    f"{item_id}: AMEND requires a `tags` list -- possibly "
                    "empty, which means 'this row should carry no tags'"
                )
            unknown = sorted({t for t in tags if t not in vocabulary})
            if unknown:
                raise ClinicalImportError(
                    f"{item_id}: {unknown} are not in the region vocabulary "
                    f"{sorted(vocabulary)}. A tag the app cannot match is "
                    "invisible to every safety filter"
                )
            if len(set(tags)) != len(tags):
                raise ClinicalImportError(f"{item_id}: duplicate tags")

        accepted.append({
            "item_id": item_id,
            "disposition": disposition,
            "tags": sorted(tags) if disposition == "AMEND" else None,
            "rationale": entry.get("rationale"),
        })

    counts: dict[str, int] = {d: 0 for d in DISPOSITIONS}
    for row in accepted:
        counts[row["disposition"]] += 1

    return {
        "reviewer": {
            "name": submission["reviewer_name"],
            "credentials": submission["reviewer_credentials"],
            "authority": submission["reviewer_authority"],
        },
        "reviewed_at": submission["reviewed_at"],
        "catalogue_sha256": submission["catalogue_sha256"],
        "handoff_commit": submission["handoff_commit"],
        "rows": accepted,
        "counts": counts,
        "coverage": {
            "reviewed": len(accepted),
            "catalogue_rows": len(known),
            "not_reviewed": len(known) - len(accepted),
            "note": (
                "A row absent from this submission is NOT REVIEWED. It is not "
                "'accepted by default' and must not be counted as validated."
            ),
        },
        "closes": [],
        "does_not_close": (
            "D1 = EXTERNAL_CLINICAL_VALIDATION_REQUIRED and H3 = HOLD are not "
            "closed by a validated FILE. Applying these dispositions to the "
            "catalogue, and deciding what the app does with an UNKNOWN row, "
            "are separate decisions that this validator has no opinion about."
        ),
    }


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--worklist", metavar="DIR",
                    help="write the row-level worklist for a clinician")
    ap.add_argument("--check", metavar="FILE",
                    help="validate a returned submission")
    ap.add_argument("--verify", metavar="DIR",
                    help="refuse a checked-in worklist that has drifted (CI)")
    args = ap.parse_args(argv)

    if args.verify:
        meta = verify_worklist(Path(args.verify))
        print(f"worklist matches the catalogue: {meta['counts']['total']} rows "
              f"({meta['counts']['tagged']} tagged, "
              f"{meta['counts']['untagged']} untagged)")
        return 0

    if args.check:
        result = validate(load_submission(Path(args.check)))
        print(f"VALID  {result['reviewer']['name']} "
              f"({result['reviewer']['credentials']})")
        print(f"  {result['counts']}")
        print(f"  reviewed {result['coverage']['reviewed']} of "
              f"{result['coverage']['catalogue_rows']}; "
              f"{result['coverage']['not_reviewed']} NOT REVIEWED")
        print(f"\n  {result['does_not_close']}")
        return 0

    if args.worklist:
        out = Path(args.worklist)
        payload = write_worklist(out)
        for name in ("worklist.csv", "submission.json", "HOW_TO_REVIEW.md",
                     "worklist.meta.json"):
            print(f"-> {out / name}")
    else:
        payload = worklist()
    c = payload["counts"]
    print(f"  {c['total']} rows: {c['tagged']} tagged, {c['untagged']} untagged")
    print(f"  catalogue {payload['catalogue_sha256'][:16]}...")
    print(f"  regions   {payload['regions']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
