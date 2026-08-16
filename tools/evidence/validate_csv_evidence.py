#!/usr/bin/env python3
"""Validate the CSV evidence under `core/`, which no Flutter test can reach.

## Why this exists

`flutter test` opens Dart and the files `pubspec.yaml` declares as assets. It does
not open `core/plans/*.csv` or `core/audit/**`, so a green suite has never said
anything at all about them. That was stated plainly when the action ledger was
introduced, and this is the tool that closes it rather than leaving the note.

Two things are checked, and they are different kinds of claim:

1. **The action ledger** (`core/plans/FINAL_AUTONOMOUS_ACTION_LOG.csv`) is a
   record of what was done. Its rows must be well-formed, ordered, and — where a
   row claims a commit — that commit must exist in this repository's history.
   A ledger naming a SHA that is not in `git log` is worse than no ledger.

2. **The imported audit evidence** (`core/audit/**/MANIFEST.csv`) is a record of
   what was received. Every file it lists must still hash to the value recorded
   at import time. That is the whole point of importing originals: a later reader
   can prove the bytes were not edited on the way in, or since.

Exit code is 0 when everything holds and 1 otherwise, so CI and a shell `&&`
chain both behave.

Run from the repository root:

    python tools/evidence/validate_csv_evidence.py
"""

from __future__ import annotations

import csv
import datetime as dt
import hashlib
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

ACTION_LOG = os.path.join(REPO, "core", "plans", "FINAL_AUTONOMOUS_ACTION_LOG.csv")

ACTION_LOG_HEADER = [
    "sequence",
    "timestamp",
    "marker",
    "action",
    "command_or_change",
    "target",
    "result",
    "related_gate",
    "commit",
    "notes",
]

# The control protocol defines exactly three marker shapes. Anything else is
# either a typo or an invented marker, and both should fail rather than pass
# quietly into an audit trail.
ALLOWED_MARKERS = {"+ГО", "+ГО|КОМИТ", "+ГО|+ПУШ"}

SHA_RE = re.compile(r"^[0-9a-f]{7,40}$")

failures: list[str] = []
notes: list[str] = []


def fail(msg: str) -> None:
    failures.append(msg)


def note(msg: str) -> None:
    notes.append(msg)


def git(*args: str) -> str:
    return subprocess.run(
        ["git", "-C", REPO, *args], capture_output=True, text=True
    ).stdout.strip()


def validate_action_log() -> None:
    if not os.path.exists(ACTION_LOG):
        fail(f"action log missing: {ACTION_LOG}")
        return

    # `newline=''` and the csv module rather than a split on commas: a `notes`
    # field legitimately contains commas inside quotes, and a hand-rolled parser
    # would report a field-count error on correct data.
    with open(ACTION_LOG, encoding="utf-8", newline="") as fh:
        reader = csv.reader(fh)
        try:
            header = next(reader)
        except StopIteration:
            fail("action log is empty")
            return
        rows = list(reader)

    if header != ACTION_LOG_HEADER:
        fail(f"action log header is {header}, expected {ACTION_LOG_HEADER}")
        return

    if not rows:
        fail("action log has a header and no rows")
        return

    seen_sequences: set[int] = set()
    previous = 0
    known_commits: set[str] = set()

    for line_no, row in enumerate(rows, start=2):
        where = f"action log line {line_no}"

        if len(row) != len(ACTION_LOG_HEADER):
            fail(f"{where}: {len(row)} fields, expected {len(ACTION_LOG_HEADER)}")
            continue

        record = dict(zip(ACTION_LOG_HEADER, row))

        try:
            sequence = int(record["sequence"])
        except ValueError:
            fail(f"{where}: sequence {record['sequence']!r} is not an integer")
            continue

        if sequence in seen_sequences:
            fail(f"{where}: duplicate sequence {sequence}")
        seen_sequences.add(sequence)

        # Monotonic, not merely unique. An out-of-order ledger cannot be read as
        # a sequence of events, which is the only thing it is for.
        if sequence <= previous:
            fail(f"{where}: sequence {sequence} does not follow {previous}")
        previous = sequence

        try:
            dt.datetime.fromisoformat(record["timestamp"])
        except ValueError:
            fail(f"{where}: timestamp {record['timestamp']!r} does not parse as ISO-8601")

        if record["marker"] not in ALLOWED_MARKERS:
            fail(f"{where}: marker {record['marker']!r} is not one of {sorted(ALLOWED_MARKERS)}")

        if not record["action"].strip():
            fail(f"{where}: action is empty")

        commit = record["commit"].strip()
        if commit:
            if not SHA_RE.match(commit):
                fail(f"{where}: commit {commit!r} is not a hex SHA")
            else:
                known_commits.add(commit)

        # A row that says it committed has to name what it committed.
        if "КОМИТ" in record["marker"] and not commit:
            fail(f"{where}: marker claims a commit and the commit column is empty")

    # Every SHA the ledger names must be reachable from HEAD. A ledger that
    # names a commit this branch does not contain is either a typo or a claim
    # about work that is not here.
    for sha in sorted(known_commits):
        if git("cat-file", "-t", sha) != "commit":
            fail(f"action log names {sha}, which is not a commit in this repository")
        elif not _is_ancestor(sha):
            fail(f"action log names {sha}, which is not reachable from HEAD")

    note(f"action log: {len(rows)} rows, {len(known_commits)} distinct commits, all reachable")

    # The historical gap is deliberate and documented — see the 2026-08-16
    # DECISION_LOG entry. It is asserted here so that removing the explanation
    # from the ledger fails this validator rather than quietly turning an
    # acknowledged gap into an unexplained one.
    text = open(ACTION_LOG, encoding="utf-8").read()
    if "not journalled" not in text:
        fail(
            "action log no longer carries its historical-gap note; the rows before "
            "the control protocol were never journalled and that must stay stated"
        )


def _is_ancestor(sha: str) -> bool:
    """Whether [sha] is reachable from HEAD.

    `merge-base --is-ancestor` answers through its exit code and prints nothing,
    so this cannot go through `git()` — a helper that returns stdout would read
    every answer as an empty string and therefore as false.
    """
    return (
        subprocess.run(
            ["git", "-C", REPO, "merge-base", "--is-ancestor", sha, "HEAD"],
            capture_output=True,
        ).returncode
        == 0
    )


def validate_audit_manifests() -> None:
    audit_root = os.path.join(REPO, "core", "audit")
    if not os.path.isdir(audit_root):
        note("no core/audit directory; nothing to check")
        return

    manifests = []
    for dirpath, _dirnames, filenames in os.walk(audit_root):
        if "MANIFEST.csv" in filenames:
            manifests.append(os.path.join(dirpath, "MANIFEST.csv"))

    if not manifests:
        fail("core/audit exists but carries no MANIFEST.csv")
        return

    for manifest in manifests:
        directory = os.path.dirname(manifest)
        rel = os.path.relpath(manifest, REPO).replace(os.sep, "/")

        with open(manifest, encoding="utf-8", newline="") as fh:
            rows = list(csv.DictReader(fh))

        if not rows:
            fail(f"{rel}: no rows")
            continue

        required = {"filename", "sha256", "bytes", "row_count", "state", "purpose"}
        missing = required - set(rows[0].keys())
        if missing:
            fail(f"{rel}: missing columns {sorted(missing)}")
            continue

        listed = set()
        for row in rows:
            name = row["filename"]
            listed.add(name)
            path = os.path.join(directory, name)

            if not os.path.exists(path):
                fail(f"{rel}: {name} is listed and absent")
                continue

            actual_bytes = os.path.getsize(path)
            if str(actual_bytes) != row["bytes"]:
                fail(f"{rel}: {name} is {actual_bytes} bytes, manifest says {row['bytes']}")

            with open(path, "rb") as fh:
                digest = hashlib.sha256(fh.read()).hexdigest()
            if digest != row["sha256"]:
                fail(f"{rel}: {name} hashes to {digest[:16]}…, manifest says {row['sha256'][:16]}…")

            if row["state"] not in {"ORIGINAL_PRESERVED", "REGENERATED"}:
                fail(f"{rel}: {name} state {row['state']!r} is neither ORIGINAL_PRESERVED nor REGENERATED")

            if not row["purpose"].strip():
                fail(f"{rel}: {name} has no purpose recorded")

            if name.endswith(".csv") and row["row_count"].strip():
                with open(path, encoding="utf-8-sig", newline="") as fh:
                    reader = csv.reader(fh)
                    header = next(reader, None)
                    body = list(reader)
                if header is None:
                    fail(f"{rel}: {name} has no header")
                else:
                    widths = {len(r) for r in body}
                    if len(widths) > 1:
                        fail(f"{rel}: {name} has ragged rows, widths {sorted(widths)}")
                    elif widths and widths != {len(header)}:
                        fail(
                            f"{rel}: {name} rows are {widths.pop()} wide against a "
                            f"{len(header)}-column header"
                        )
                    if str(len(body)) != row["row_count"]:
                        fail(f"{rel}: {name} has {len(body)} rows, manifest says {row['row_count']}")

        # A file sitting in an evidence directory that the manifest does not
        # name is evidence nobody can prove the provenance of.
        on_disk = {f for f in os.listdir(directory) if f != "MANIFEST.csv"}
        unlisted = on_disk - listed
        if unlisted:
            fail(f"{rel}: files present and unlisted: {sorted(unlisted)}")

        note(f"{rel}: {len(rows)} artifacts, hashes and row counts verified")


def main() -> int:
    validate_action_log()
    validate_audit_manifests()

    for line in notes:
        print(f"  ok  {line}")
    for line in failures:
        print(f"FAIL  {line}")

    if failures:
        print(f"\n{len(failures)} failure(s)")
        return 1
    print("\nall CSV evidence valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
