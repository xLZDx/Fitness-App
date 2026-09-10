"""B1 step 14 -- `--verify --all`. Offline, exhaustive over B1's own namespace.

WHY THE DIRECTORY NAME IS NOT PARSED BY SPLITTING
---------------------------------------------------
A capture directory is named ``<sourceId>__<candidateDocId>__<captureId>``. Both
the sourceId and candidateDocId grammars permit a run of underscores inside the
identifier itself (``[a-z0-9_-]*`` does not exclude ``__``), so a naive
``name.split("__")`` is ambiguous the moment either component contains one.

The captureId suffix is unambiguous -- it is always the fixed shape
``YYYYMMDDTHHMMSSZ``, which contains no ``_``. So the name is parsed from the
END: strip the ``__<captureId>`` suffix first, matching it against the real
captureId grammar (not a length guess), then match the remaining
``<sourceId>__<candidateDocId>`` against each of the three known B1 target
sourceIds as an exact prefix followed by ``__``. Reconstruction against a known
set, not generic splitting -- the same discipline `resolve_source_id` already
uses for the string itself.

WHAT "OFFLINE" MEANS HERE, AND HOW IT IS PROVEN
-------------------------------------------------
Verification re-hashes committed bytes already on disk and resolves basis
references against a committed (or injected) registry -- neither touches a
socket. `test_terms_verify.py` proves this by monkeypatching `socket.socket` to
raise if constructed at all, then running a full verification pass.

WHAT "EXHAUSTIVE OVER ITS OWN NAMESPACE" MEANS
-------------------------------------------------
Only `terms_snapshots/captures/` is scanned. `terms_snapshots/` itself already
holds a tracked G3 fixture (`synthetic_test_terms.txt`) this gate does not own;
sweeping the ROOT would call it an orphan. A file sitting BESIDE the namespace
is invisible to this scan by construction -- it is never listed, never
inspected, never counted.
"""

from __future__ import annotations

import hashlib
import json
import pathlib
from dataclasses import dataclass, field
from typing import Any

from capture_terms import (
    CAPTURES_ROOT,
    CaptureError,
    SIDECAR_NAME,
    capture_id_matches_timestamp,
    parse_capture_id,
    validate_sidecar,
)
from terms_acquisition import B1_TARGET_SOURCE_IDS
from terms_authority import AuthorityError, resolve_basis
from terms_candidates import is_valid_candidate_doc_id


class VerificationError(CaptureError):
    """A committed capture that does not verify. Subclasses CaptureError."""


@dataclass
class VerifiedCapture:
    directory: str
    source_id: str
    candidate_doc_id: str
    capture_id: str
    sha256: str


@dataclass
class VerificationReport:
    captures: list[VerifiedCapture] = field(default_factory=list)

    @property
    def count(self) -> int:
        return len(self.captures)


def _parse_capture_directory_name(name: str) -> tuple[str, str] | None:
    """Split `name` into (sourceId, candidateDocId), or None if it does not parse.

    Tries every known B1 target as an exact prefix rather than guessing a split
    point generically -- see the module docstring.
    """
    # captureId is fixed-width: "YYYYMMDDTHHMMSSZ" = 16 characters, preceded by "__".
    marker = "__"
    if len(name) < 16 + len(marker):
        return None
    candidate_capture_id = name[-16:]
    if name[-16 - len(marker):-16] != marker:
        return None
    try:
        parse_capture_id(candidate_capture_id)
    except CaptureError:
        return None

    remainder = name[: -16 - len(marker)]
    for source_id in B1_TARGET_SOURCE_IDS:
        prefix = source_id + marker
        if remainder.startswith(prefix):
            candidate_doc_id = remainder[len(prefix):]
            if is_valid_candidate_doc_id(candidate_doc_id):
                return source_id, candidate_doc_id
    return None


def _verify_one(directory: pathlib.Path, basis_registry: dict[str, Any] | None) -> VerifiedCapture:
    name = directory.name
    parsed = _parse_capture_directory_name(name)
    if parsed is None:
        raise VerificationError(
            f"{name!r} is not a valid capture directory name -- orphan inside the B1 namespace"
        )
    source_id, candidate_doc_id = parsed
    capture_id = name[-16:]

    entries = sorted(p.name for p in directory.iterdir())
    documents = [e for e in entries if e.startswith("document.")]
    if len(documents) != 1 or SIDECAR_NAME not in entries or len(entries) != 2:
        raise VerificationError(
            f"{name!r}: expected exactly one document.* and {SIDECAR_NAME}, found {entries} "
            "-- an incomplete capture is an orphan, not a partial success"
        )

    try:
        sidecar = json.loads((directory / SIDECAR_NAME).read_bytes().decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise VerificationError(f"{name!r}: {SIDECAR_NAME} is not valid UTF-8 JSON -- {exc}") from exc

    try:
        validate_sidecar(sidecar)
    except CaptureError as exc:
        # validate_sidecar raises the BASE CaptureError, not VerificationError --
        # it is shared with the write path (capture_terms.py), which has no
        # reason to know this module's subclass exists. Re-raised here so every
        # fault this module finds, including one delegated to a shared
        # validator, surfaces through the single exception type verify_all's
        # callers are told to catch.
        raise VerificationError(str(exc)) from exc

    # Cross-bound: the directory name and the sidecar's own claim must agree.
    # A directory renamed after publication, or a sidecar edited in place,
    # both show up here.
    for field_name, expected in (
        ("sourceId", source_id), ("candidateDocId", candidate_doc_id), ("captureId", capture_id),
    ):
        if sidecar.get(field_name) != expected:
            raise VerificationError(
                f"{name!r}: directory name implies {field_name}={expected!r} but the sidecar "
                f"says {sidecar.get(field_name)!r} -- the directory and its own record disagree"
            )

    # Investigated rather than assumed: by this point `validate_sidecar` (just
    # above) has already required sidecar["captureId"] to match
    # sidecar["capturedAtUtc"] via this SAME function, and the cross-bound loop
    # just above has already required sidecar["captureId"] == capture_id. So on
    # every path that reaches this line, capture_id_matches_timestamp(capture_id,
    # sidecar["capturedAtUtc"]) is PROVABLY True already -- no fixture can make
    # it fail here without first failing one of those two earlier checks. Kept
    # as explicit defence-in-depth against a future reordering of the checks
    # above, not asserted as a mutation-proven guard today.
    if not capture_id_matches_timestamp(capture_id, sidecar["capturedAtUtc"]):
        raise VerificationError(
            f"{name!r}: captureId and capturedAtUtc no longer denote the same instant"
        )

    document_path = directory / documents[0]
    actual_bytes = document_path.read_bytes()
    actual_sha256 = hashlib.sha256(actual_bytes).hexdigest()
    if actual_sha256 != sidecar["sha256"]:
        raise VerificationError(
            f"{name!r}: {documents[0]} hashes to {actual_sha256}, sidecar records "
            f"{sidecar['sha256']} -- the committed bytes no longer match their own provenance"
        )
    if len(actual_bytes) != sidecar["byteLength"]:
        raise VerificationError(
            f"{name!r}: {documents[0]} is {len(actual_bytes)} bytes, sidecar records "
            f"{sidecar['byteLength']}"
        )

    # A reference that no longer resolves is a live finding, not a historical
    # footnote: a basis can be revoked after a capture was published.
    for ref_field, capability in (
        ("acquisitionBasisRef", "ACQUISITION"), ("retentionBasisRef", "RETENTION"),
    ):
        try:
            resolve_basis(
                sidecar[ref_field], capability, source_id, candidate_doc_id,
                sidecar["acquisitionMethod"], registry=basis_registry,
            )
        except AuthorityError as exc:
            raise VerificationError(
                f"{name!r}: {ref_field} {sidecar[ref_field]!r} no longer resolves with "
                f"{capability} -- {exc}"
            ) from exc

    return VerifiedCapture(
        directory=name, source_id=source_id, candidate_doc_id=candidate_doc_id,
        capture_id=capture_id, sha256=actual_sha256,
    )


def verify_all(
    *,
    root: pathlib.Path | None = None,
    basis_registry: dict[str, Any] | None = None,
) -> VerificationReport:
    """Verify every capture under the B1 namespace. Raises on the first fault.

    Performs no network I/O -- every step here is a filesystem read plus a
    lookup against an in-memory (or committed) registry.
    """
    namespace = CAPTURES_ROOT if root is None else root
    report = VerificationReport()
    if not namespace.exists():
        return report  # zero captures is a valid, verified state

    seen_identities: dict[tuple[str, str, str], str] = {}
    for entry in sorted(namespace.iterdir()):
        if not entry.is_dir():
            raise VerificationError(
                f"{entry.name!r} is a file directly under the B1 namespace -- orphan"
            )
        if entry.name.startswith(".staging__"):
            raise VerificationError(
                f"{entry.name!r} is leftover staging debris inside the B1 namespace -- a "
                "capture must either fully publish or leave nothing behind"
            )
        verified = _verify_one(entry, basis_registry)
        identity = (verified.source_id, verified.candidate_doc_id, verified.capture_id)
        # Investigated rather than assumed: for the CURRENT three-element
        # B1_TARGET_SOURCE_IDS (no one of which is a string-prefix of another),
        # `_parse_capture_directory_name` is injective -- distinct directory
        # names always parse to distinct identity tuples, and cross-bound
        # already refuses a sidecar that disagrees with its own directory's
        # implied identity. Given that, no fixture can currently reach this
        # branch: it is UNPROVEN defence-in-depth, kept for a future
        # B1_TARGET_SOURCE_IDS whose members are not mutually prefix-free,
        # not a mutation-proven guard today. Recorded here rather than
        # silently claimed, per this repository's own standing rule against a
        # check that describes more depth than it has.
        if identity in seen_identities:
            raise VerificationError(
                f"capture identity {identity} appears in both {seen_identities[identity]!r} "
                f"and {entry.name!r}"
            )
        seen_identities[identity] = entry.name
        report.captures.append(verified)

    return report


def main() -> int:
    try:
        report = verify_all()
    except VerificationError as exc:
        print(f"VERIFY FAILED: {exc}")
        return 1
    print(f"verify: {report.count} capture(s), all consistent, offline")
    for capture in report.captures:
        print(f"  {capture.source_id:48s} {capture.candidate_doc_id:28s} {capture.capture_id}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
