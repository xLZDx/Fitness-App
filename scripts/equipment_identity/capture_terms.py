"""B1 steps 8, 9 and 10 -- capture identity, the sidecar, and atomic publication.

THREE LEVELS OF IDENTITY
------------------------
::

    sourceId        the registry source
    candidateDocId  the logical legal document
    captureId       ONE immutable observation of it

A source may have many candidate documents -- Life Fitness already has two. A
candidate may be captured many times, because a published page changes. So the
storage identity is the TRIPLE, and one-to-one is enforced at *capture identity*
<-> capture directory <-> sidecar, never at source record <-> capture. An earlier
revision declared identity to be the pair and then put a date in the path, which
cannot both be true the moment a document is captured twice.

WHY captureId IS GENERATED AND NOT SUPPLIED
-------------------------------------------
A grammar of ``^[0-9]{8}T[0-9]{6}Z$`` accepts ``20261399T996099Z``: a shape, not
an instant. A directory named like measured provenance while being a free string
is this programme's recurring defect wearing a timestamp. So the registrar reads
the clock itself, formats the id from that reading, **round-trips it** (parse,
re-format, require equality -- an impossible date dies on the parse), and binds
it to the sidecar's own timestamp. The production CLI cannot supply either; the
clock is injectable for tests only.

ASSERTED IS NOT OBSERVED
------------------------
``--from-file`` performs no network transaction, so it cannot observe a final URL
or a redirect chain. The sidecar is partitioned by acquisition method and the
fields that do not apply are ABSENT rather than null-filled, because a null in a
provenance record still occupies the shape of an observation.

PUBLICATION IS ONE RENAME
-------------------------
Two renames leave a window in which a snapshot exists without its sidecar, and
for that instant the one-to-one binding this gate promises is false. So both
files are built inside a staging directory on the same filesystem and the
DIRECTORY is renamed once, after every guard has passed.

B1 OWNS ONE NAMESPACE
---------------------
Captures live under ``terms_snapshots/captures/``. The snapshot ROOT already
holds ``synthetic_test_terms.txt``, a tracked G3 fixture referenced by
``test_rights.py``; a verifier that swept the root would call that legitimate
file an orphan and fail before B1 had created anything. Special-casing its name
would make ownership a historical exception instead of a rule.
"""

from __future__ import annotations

import datetime as _dt
import hashlib
import json
import os
import pathlib
import shutil
import time
from typing import Any, Callable

from rights import TERMS_SNAPSHOT_ROOT
from terms_authority import AuthorityError, resolve_basis, resolve_source_id
from terms_candidates import CandidateManifestError, resolve_candidate

CAPTURES_ROOT = TERMS_SNAPSHOT_ROOT / "captures"

CAPTURE_ID_FORMAT = "%Y%m%dT%H%M%SZ"
REGISTRAR_VERSION = "b1-registrar-1"

DOCUMENT_STEM = "document"
SIDECAR_NAME = "provenance.json"

HUMAN_MANUAL_RETRIEVAL = "HUMAN_MANUAL_RETRIEVAL"
AUTOMATED_FETCH = "AUTOMATED_FETCH"

#: Fields only a real network transaction can produce. A manual registration
#: carrying any of them is describing something that did not happen.
OBSERVED_ONLY_FIELDS: frozenset[str] = frozenset({
    "requestedUrlObserved", "redirectChainObserved", "finalUrlObserved",
})

#: Fields that are an actor's attestation rather than a measurement.
ASSERTED_ONLY_FIELDS: frozenset[str] = frozenset({
    "assertedDocumentUrl", "actor", "attestationRef",
})

MEDIA_TYPE_EXTENSIONS = {
    "text/html": "html",
    "application/pdf": "pdf",
    "text/plain": "txt",
}


class CaptureError(Exception):
    """A capture that may not be published, or a published one that does not verify."""


# ---------------------------------------------------------------------------
# Step 8 -- capture identity.
# ---------------------------------------------------------------------------

def utc_now() -> _dt.datetime:
    """The production clock. Injected elsewhere ONLY by tests."""
    return _dt.datetime.now(_dt.timezone.utc)


def format_capture_id(moment: _dt.datetime) -> str:
    """Format one instant as a captureId, and prove the value round-trips.

    The round-trip is the point. Formatting alone would produce a string that
    merely LOOKS like an instant; parsing it back and requiring equality means
    the directory name denotes the reading it came from.
    """
    if not isinstance(moment, _dt.datetime):
        raise CaptureError(f"capture instant must be a datetime, got {type(moment).__name__}")
    if moment.tzinfo is None:
        raise CaptureError(
            "capture instant must be timezone-aware -- a naive datetime records an instant "
            "whose meaning depends on where the machine was standing"
        )
    moment = moment.astimezone(_dt.timezone.utc).replace(microsecond=0)
    capture_id = moment.strftime(CAPTURE_ID_FORMAT)
    if parse_capture_id(capture_id) != moment:
        raise CaptureError(f"captureId {capture_id!r} does not round-trip to {moment!r}")
    return capture_id


def parse_capture_id(capture_id: Any) -> _dt.datetime:
    """Parse a captureId back to the instant it denotes, or raise.

    `strptime` is what rejects an impossible date: `20261399T996099Z` has no
    thirteenth month and dies here rather than becoming a directory.
    """
    if not isinstance(capture_id, str):
        raise CaptureError(f"captureId must be a string, got {type(capture_id).__name__}")
    try:
        parsed = _dt.datetime.strptime(capture_id, CAPTURE_ID_FORMAT)
    except ValueError as exc:
        raise CaptureError(
            f"captureId {capture_id!r} is not a real UTC instant -- {exc}. A shape that "
            "resembles a timestamp is not a measurement of one"
        ) from exc

    # `strptime` alone is NOT a grammar, which the tests measured rather than
    # assumed: `%d` accepts a single digit, so "2026091T142233Z" parses happily
    # as 2026-09-01, and CPython matches the literal `T`/`Z` case-insensitively,
    # so "20260910t142233z" parses too. Both would then have become directory
    # names denoting an instant they do not render.
    #
    # So the rule is stated as one thing rather than bolted on as a second
    # guard: the CANONICAL RENDERING of the instant this string denotes must be
    # this string. An impossible date dies above; a non-canonical spelling dies
    # here; and neither check can be dropped, because each accepts what the
    # other rejects.
    canonical = parsed.strftime(CAPTURE_ID_FORMAT)
    if canonical != capture_id:
        raise CaptureError(
            f"captureId {capture_id!r} is not the canonical rendering of the instant it "
            f"denotes ({canonical!r}) -- two spellings of one moment would name two "
            "directories, and capture identity would stop being an identity"
        )
    return parsed.replace(tzinfo=_dt.timezone.utc)


def capture_id_matches_timestamp(capture_id: str, timestamp: str) -> bool:
    """True when the directory name and the sidecar's own stamp denote one instant."""
    try:
        from_id = parse_capture_id(capture_id)
    except CaptureError:
        return False
    try:
        from_stamp = _dt.datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
    except (AttributeError, ValueError):
        return False
    if from_stamp.tzinfo is None:
        return False
    return from_stamp.astimezone(_dt.timezone.utc).replace(microsecond=0) == from_id


# ---------------------------------------------------------------------------
# Step 9 -- the namespace and the single rename.
# ---------------------------------------------------------------------------

def capture_directory_name(source_id: str, candidate_doc_id: str, capture_id: str) -> str:
    """The directory name for one capture identity.

    Every component comes from a value that has already been validated, and none
    of the three alphabets admits ``.`` -- so the joined name can never be ``.``
    or ``..``. That is a structural property of the alphabets, not a check.
    """
    return f"{source_id}__{candidate_doc_id}__{capture_id}"


def capture_directory(source_id: str, candidate_doc_id: str, capture_id: str) -> pathlib.Path:
    name = capture_directory_name(source_id, candidate_doc_id, capture_id)
    target = (CAPTURES_ROOT / name).resolve()
    root = CAPTURES_ROOT.resolve()
    # Re-checked AFTER resolution, deliberately. The identifier grammars make a
    # traversal component unrepresentable, but a link is not a string: only
    # resolving both sides can see one.
    if not target.is_relative_to(root):
        raise CaptureError(
            f"capture directory {target} resolves outside the B1 namespace {root}"
        )
    return target


def _replace_with_bounded_retry(source: pathlib.Path, target: pathlib.Path) -> None:
    """`os.replace`, retried briefly.

    On Windows a transient handle from an indexer or a virus scanner produces
    winerror 5/32 on a directory that is about to be renamable. Retrying a
    bounded number of times is honest; catching the error and reporting success
    would not be.
    """
    last: OSError | None = None
    for attempt in range(5):
        try:
            os.replace(source, target)
            return
        except OSError as exc:
            last = exc
            time.sleep(0.05 * (attempt + 1))
    raise CaptureError(
        f"could not publish {target.name}: {last} -- the capture was NOT published and the "
        "staging directory is being removed"
    ) from last


def publish_capture(
    staging: pathlib.Path,
    target: pathlib.Path,
    *,
    on_before_publish: Callable[[], None] | None = None,
) -> pathlib.Path:
    """Rename one prepared staging directory into place. All of it, or none of it.

    `on_before_publish` is a TEST SEAM for injecting a failure in the instant
    before the rename. There is no CLI equivalent.
    """
    document = [p for p in staging.iterdir() if p.name.startswith(DOCUMENT_STEM + ".")]
    if len(document) != 1 or not (staging / SIDECAR_NAME).is_file():
        shutil.rmtree(staging, ignore_errors=True)
        raise CaptureError(
            f"staging directory must hold exactly one {DOCUMENT_STEM}.* and one "
            f"{SIDECAR_NAME} -- publishing half an evidence pair is the thing this "
            "function exists to prevent"
        )

    if target.exists():
        shutil.rmtree(staging, ignore_errors=True)
        raise CaptureError(
            f"capture {target.name} already exists -- an existing capture is REFUSED, never "
            "overwritten: its bytes may already be cited by a decision"
        )

    try:
        if on_before_publish is not None:
            on_before_publish()
        target.parent.mkdir(parents=True, exist_ok=True)
        _replace_with_bounded_retry(staging, target)
    except BaseException:
        shutil.rmtree(staging, ignore_errors=True)
        raise
    return target


# ---------------------------------------------------------------------------
# Step 10 -- the sidecar, partitioned by acquisition method.
# ---------------------------------------------------------------------------

def build_sidecar(
    *,
    source_id: str,
    candidate_doc_id: str,
    capture_id: str,
    acquisition_method: str,
    acquisition_basis_ref: str,
    retention_basis_ref: str,
    media_type: str,
    payload: bytes,
    timestamp: str,
    asserted: dict[str, Any] | None = None,
    observed: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Assemble one provenance sidecar, refusing an impossible combination."""
    if acquisition_method not in (HUMAN_MANUAL_RETRIEVAL, AUTOMATED_FETCH):
        raise CaptureError(f"unknown acquisitionMethod {acquisition_method!r}")
    if not capture_id_matches_timestamp(capture_id, timestamp):
        raise CaptureError(
            f"captureId {capture_id!r} and capturedAtUtc {timestamp!r} do not denote the "
            "same instant -- the directory name would read as provenance it does not carry"
        )

    sidecar: dict[str, Any] = {
        "schemaVersion": 1,
        "registrarVersion": REGISTRAR_VERSION,
        "sourceId": source_id,
        "candidateDocId": candidate_doc_id,
        "captureId": capture_id,
        "acquisitionMethod": acquisition_method,
        "acquisitionBasisRef": acquisition_basis_ref,
        "retentionBasisRef": retention_basis_ref,
        "mediaType": media_type,
        "byteLength": len(payload),
        "sha256": hashlib.sha256(payload).hexdigest(),
        "capturedAtUtc": timestamp,
    }

    if acquisition_method == HUMAN_MANUAL_RETRIEVAL:
        fields = asserted or {}
        missing = sorted(ASSERTED_ONLY_FIELDS - set(fields))
        if missing:
            raise CaptureError(f"{HUMAN_MANUAL_RETRIEVAL} requires {missing}")
        if observed:
            raise CaptureError(
                f"{HUMAN_MANUAL_RETRIEVAL} carries observed fields {sorted(observed)} -- no "
                "network transaction happened, so nothing was observed to record"
            )
        sidecar.update({k: fields[k] for k in sorted(ASSERTED_ONLY_FIELDS)})
    else:
        fields = observed or {}
        missing = sorted(OBSERVED_ONLY_FIELDS - set(fields))
        if missing:
            raise CaptureError(f"{AUTOMATED_FETCH} requires {missing}")
        if asserted:
            raise CaptureError(
                f"{AUTOMATED_FETCH} carries asserted fields {sorted(asserted)} -- what was "
                "measured must not be recorded beside a claim in the same shape"
            )
        sidecar.update({k: fields[k] for k in sorted(OBSERVED_ONLY_FIELDS)})

    return sidecar


def validate_sidecar(sidecar: Any) -> None:
    """Refuse an impossible method/field combination, in BOTH directions."""
    if not isinstance(sidecar, dict):
        raise CaptureError("sidecar must be a JSON object")

    method = sidecar.get("acquisitionMethod")
    if method not in (HUMAN_MANUAL_RETRIEVAL, AUTOMATED_FETCH):
        raise CaptureError(f"unknown acquisitionMethod {method!r}")

    present_observed = OBSERVED_ONLY_FIELDS & set(sidecar)
    present_asserted = ASSERTED_ONLY_FIELDS & set(sidecar)

    if method == HUMAN_MANUAL_RETRIEVAL:
        if present_observed:
            raise CaptureError(
                f"a {HUMAN_MANUAL_RETRIEVAL} sidecar carries {sorted(present_observed)} -- "
                "`--from-file` opens no connection, so it cannot have observed a final URL "
                "or a redirect chain"
            )
        missing = sorted(ASSERTED_ONLY_FIELDS - present_asserted)
        if missing:
            raise CaptureError(f"a {HUMAN_MANUAL_RETRIEVAL} sidecar is missing {missing}")
    else:
        if present_asserted:
            raise CaptureError(
                f"an {AUTOMATED_FETCH} sidecar carries {sorted(present_asserted)} -- an "
                "actor's assertion must not sit in the same record shape as a measurement"
            )
        missing = sorted(OBSERVED_ONLY_FIELDS - present_observed)
        if missing:
            raise CaptureError(
                f"an {AUTOMATED_FETCH} sidecar is missing {missing} -- a network capture that "
                "observed no final URL did not observe the transaction it claims to record"
            )

    for field in ("sourceId", "candidateDocId", "captureId", "sha256", "capturedAtUtc",
                  "acquisitionBasisRef", "retentionBasisRef", "mediaType"):
        value = sidecar.get(field)
        if not isinstance(value, str) or not value.strip():
            raise CaptureError(f"sidecar {field} must be a non-empty string, got {value!r}")

    if not capture_id_matches_timestamp(sidecar["captureId"], sidecar["capturedAtUtc"]):
        raise CaptureError(
            f"sidecar captureId {sidecar['captureId']!r} and capturedAtUtc "
            f"{sidecar['capturedAtUtc']!r} do not denote the same instant"
        )

    length = sidecar.get("byteLength")
    if not isinstance(length, int) or length <= 0:
        raise CaptureError(
            f"sidecar byteLength must be a positive integer, got {length!r} -- a zero-byte "
            "document is not a captured document"
        )


def media_type_extension(media_type: str) -> str:
    try:
        return MEDIA_TYPE_EXTENSIONS[media_type]
    except KeyError:
        raise CaptureError(
            f"media type {media_type!r} has no declared extension "
            f"(known: {', '.join(sorted(MEDIA_TYPE_EXTENSIONS))})"
        ) from None


# ---------------------------------------------------------------------------
# Step 11 -- `--from-file`, and the guards that make it more than a copy.
# ---------------------------------------------------------------------------

def derive_media_type(payload: bytes) -> str:
    """Determine the media type from the BYTES, never from the caller's word.

    A caller-declared type is a claim about a file the caller also supplied; the
    registrar would then be checking a statement against its own source. So the
    type is read off the content, and the candidate record decides whether that
    type is one it declares.

    Deliberately narrow. A sniffer that guesses widely would let an unexpected
    kind of file through by finding something plausible in it, and refusing to
    guess is a better answer than a confident wrong one.
    """
    if not isinstance(payload, bytes):
        raise CaptureError(f"payload must be bytes, got {type(payload).__name__}")
    if not payload:
        raise CaptureError("payload is empty -- a zero-byte document is not a document")

    if payload.startswith(b"%PDF-"):
        return "application/pdf"

    head = payload[:4096].lstrip()
    lowered = head.lower()
    if lowered.startswith(b"<!doctype html") or lowered.startswith(b"<html"):
        return "text/html"
    # A served page often opens with a comment, a stripped byte-order mark or an
    # XML prolog before <html>; look a little further before giving up, but only
    # for a real tag, not for the word "html" appearing anywhere in the bytes.
    if b"<html" in lowered or b"<!doctype html" in lowered:
        return "text/html"

    raise CaptureError(
        "could not determine the media type from the bytes. The registrar does not accept "
        "the caller's declaration in place of reading the content -- that would check a "
        "claim against the file the same caller supplied"
    )


def check_identity_expectations(payload: bytes, expectations: dict[str, Any]) -> None:
    """Assert the bytes are the document the manifest describes.

    FACTUAL only: every marker is something printed in the document. Nothing here
    decides whether the terms permit anything -- that is a legal conclusion and
    no tool in this repository may produce one.
    """
    if not isinstance(expectations, dict):
        raise CaptureError("identityExpectations must be an object")
    markers = expectations.get("requiredMarkers")
    if not isinstance(markers, list) or not markers:
        raise CaptureError(
            "identityExpectations.requiredMarkers is empty -- the identity check would be "
            "vacuously true, which is worse than absent because it looks like a check"
        )
    text = payload.decode("utf-8", errors="replace")

    missing = [m for m in markers if m not in text]
    if missing:
        raise CaptureError(
            f"the supplied bytes do not carry {len(missing)} of {len(markers)} expected "
            f"marker(s): {missing[:3]}{'...' if len(missing) > 3 else ''} -- this is not the "
            "document the manifest registered, however correct the rest of the request"
        )


def register_from_file(
    *,
    source_id: str,
    candidate_doc_id: str,
    document_path: pathlib.Path,
    acquisition_basis_ref: str,
    retention_basis_ref: str,
    actor: str,
    attestation_ref: str,
    asserted_document_url: str,
    clock: Callable[[], _dt.datetime] = utc_now,
    manifest: dict[str, Any] | None = None,
    basis_registry: dict[str, Any] | None = None,
    source_registry: dict[str, Any] | None = None,
    on_before_publish: Callable[[], None] | None = None,
) -> pathlib.Path:
    """Register locally supplied bytes as one capture. Publishes, or publishes nothing.

    Ordered so that everything cheap and refusable happens before anything is
    written: identity resolves, authority resolves, the bytes are read and
    checked, and only then is a staging directory created at all.
    """
    for name, value in (
        ("sourceId", source_id), ("candidateDocId", candidate_doc_id),
        ("acquisitionBasisRef", acquisition_basis_ref),
        ("retentionBasisRef", retention_basis_ref),
        ("actor", actor), ("attestationRef", attestation_ref),
        ("assertedDocumentUrl", asserted_document_url),
    ):
        if not isinstance(value, str) or not value.strip():
            raise CaptureError(
                f"--from-file requires {name}. A capture missing it is a file on disk with a "
                "story attached, not a record anyone can check"
            )

    # Assigning the RETURN VALUE rather than reusing `source_id` is deliberate
    # defence in depth, and it is recorded as exactly that rather than as a
    # mutation-proven guard: `resolve_source_id` compares byte-for-byte, so on
    # every path where it does not raise, its return value is PROVABLY
    # identical to the input -- no fixture can currently make the two diverge.
    # A mutation collapsing this into `resolved_source = source_id` survives
    # for that reason, confirmed inert, not silently dropped (see
    # test_capture_terms's mutation log). It is kept because it costs nothing
    # and it stops being inert the moment `resolve_source_id`'s comparison is
    # ever loosened -- at which point this line is what keeps a caller's raw
    # string from reaching a path.
    resolved_source = resolve_source_id(source_id, registry=source_registry)
    candidate = resolve_candidate(resolved_source, candidate_doc_id, manifest)

    if candidate["observationState"] != "OBSERVED":
        raise CaptureError(
            f"candidate {candidate_doc_id!r} is NOT_OBSERVED, so the manifest holds no "
            "identity expectations for it and the identity guard would be vacuous. Register "
            "what the document is before registering a copy of it"
        )

    if asserted_document_url not in candidate["documentUrls"]:
        raise CaptureError(
            f"assertedDocumentUrl {asserted_document_url!r} is not a URL this manifest owns "
            f"for {candidate_doc_id!r} (owns: {candidate['documentUrls']}) -- a caller may "
            "name a document, never define one"
        )

    # BOTH references resolve, with the capability each is being used for. An
    # earlier revision checked only that they were present, which put a
    # self-authorising string back one code path after it was removed.
    resolve_basis(
        acquisition_basis_ref, "ACQUISITION", resolved_source, candidate_doc_id,
        HUMAN_MANUAL_RETRIEVAL, registry=basis_registry,
    )
    resolve_basis(
        retention_basis_ref, "RETENTION", resolved_source, candidate_doc_id,
        HUMAN_MANUAL_RETRIEVAL, registry=basis_registry,
    )

    try:
        payload = pathlib.Path(document_path).read_bytes()
    except OSError as exc:
        raise CaptureError(f"could not read {document_path}: {exc}") from exc

    media_type = derive_media_type(payload)
    if media_type not in candidate["declaredMediaTypes"]:
        raise CaptureError(
            f"the bytes are {media_type}, which {candidate_doc_id!r} does not declare "
            f"(declares: {candidate['declaredMediaTypes']})"
        )
    check_identity_expectations(payload, candidate["identityExpectations"])

    moment = clock()
    capture_id = format_capture_id(moment)
    timestamp = moment.astimezone(_dt.timezone.utc).replace(microsecond=0).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
    sidecar = build_sidecar(
        source_id=resolved_source,
        candidate_doc_id=candidate_doc_id,
        capture_id=capture_id,
        acquisition_method=HUMAN_MANUAL_RETRIEVAL,
        acquisition_basis_ref=acquisition_basis_ref,
        retention_basis_ref=retention_basis_ref,
        media_type=media_type,
        payload=payload,
        timestamp=timestamp,
        asserted={
            "assertedDocumentUrl": asserted_document_url,
            "actor": actor,
            "attestationRef": attestation_ref,
        },
    )
    validate_sidecar(sidecar)
    return stage_and_publish(
        resolved_source, candidate_doc_id, capture_id, media_type, payload, sidecar,
        on_before_publish=on_before_publish,
    )


def stage_and_publish(
    source_id: str,
    candidate_doc_id: str,
    capture_id: str,
    media_type: str,
    payload: bytes,
    sidecar: dict[str, Any],
    *,
    on_before_publish: Callable[[], None] | None = None,
) -> pathlib.Path:
    """Write the document and sidecar into staging, then publish by one rename.

    Shared by `register_from_file` and the network path in `terms_network.py`,
    so the staging/publish sequence exists exactly once rather than being
    reimplemented per acquisition method -- a divergence between the two would
    be exactly the kind of unearned claim this gate keeps finding.
    """
    target = capture_directory(source_id, candidate_doc_id, capture_id)
    staging = target.parent / f".staging__{target.name}"
    if staging.exists():
        shutil.rmtree(staging, ignore_errors=True)
    staging.mkdir(parents=True)
    (staging / f"{DOCUMENT_STEM}.{media_type_extension(media_type)}").write_bytes(payload)
    (staging / SIDECAR_NAME).write_bytes(
        (json.dumps(sidecar, indent=2, ensure_ascii=True) + "\n").encode("utf-8")
    )
    return publish_capture(staging, target, on_before_publish=on_before_publish)


__all__ = [
    "CAPTURES_ROOT", "CaptureError", "REGISTRAR_VERSION",
    "utc_now", "format_capture_id", "parse_capture_id", "capture_id_matches_timestamp",
    "capture_directory", "capture_directory_name", "publish_capture",
    "build_sidecar", "validate_sidecar", "media_type_extension",
    "derive_media_type", "check_identity_expectations", "register_from_file",
    "stage_and_publish", "DOCUMENT_STEM", "SIDECAR_NAME",
    "HUMAN_MANUAL_RETRIEVAL", "AUTOMATED_FETCH",
    "AuthorityError", "CandidateManifestError",
    "resolve_basis", "resolve_source_id", "resolve_candidate",
]
