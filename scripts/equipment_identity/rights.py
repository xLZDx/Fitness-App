# -*- coding: utf-8 -*-
"""P0.G3 — fail-closed source & rights registry.

    python scripts/equipment_identity/rights.py
    python -m pytest scripts/equipment_identity/test_rights.py -q

This module builds RIGHTS GOVERNANCE, not legal approvals. Nothing here
declares a real license legally sufficient — it only enforces the mechanics
that make "unknown/unreviewed" fail closed instead of quietly defaulting to
allowed. Every eligibility question below reduces to the same shape: was
this source actually reviewed, is the OBJECT being asked about inside the
population that review covered, and does the recorded rights object say yes
to the SPECIFIC use. `UNREVIEWED` always fails every privileged use, with no
exception route.

## Fail-closed policy (per the gate contract, restated as code)

    DISPLAY                 REVIEWED AND subject in scope AND displayAllowed
    RECOGNITION_PROCESSING  REVIEWED AND subject in scope AND recognitionProcessingAllowed
                             AND NOT noAiRestriction
    TRAINING                REVIEWED AND subject in scope AND trainingAllowed
                             AND NOT noAiRestriction
    DERIVATIVE              REVIEWED AND subject in scope AND derivativeAllowed
                             AND NOT noAiRestriction
    REDISTRIBUTION          REVIEWED AND subject in scope AND redistributionAllowed

every one of them also requiring `commercialAllowed`, since SPTR is a
commercial product and there is no non-commercial context here to fall back
on.

`noAiRestriction=false` on an UNREVIEWED source is never read as permission
— `legalReviewState` gates every decision below before any other field is
even inspected. A SEARCH_DISCOVERY-priority source is refused for every
privileged use regardless of its rights booleans, structurally, not just by
convention — that class exists to find candidate sources, never to BE one.

## A permission is about an object, not about a source

`eligible_for(record, use, subject)` takes a `SubjectRef(key_namespace,
key)` and there is no default. A source-wide grant used to be the only thing
this contract could express, which meant reviewing the terms covering PART of
a catalogue and recording the result granted the whole of it — the review and
the grant had different populations and nothing could say so. `rightsScope`
now states the population and the subject names the object, so the two can be
compared instead of assumed equal.

## Evidence: four rows, two rules

    UNREVIEWED + termsCaptured=false   snapshot forbidden, scope forbidden
    UNREVIEWED + termsCaptured=true    snapshot required,  scope forbidden
    REVIEWED                           snapshot required,  scope required
    BLOCKED                            snapshot required,  scope forbidden

A capture must be bound to real bytes in EVERY state (path + sha256, the file
read and re-hashed, confined to `TERMS_SNAPSHOT_ROOT`), and a scope belongs to
exactly one state. Capturing terms before anyone reviews them stays legal —
`termsCaptured` is factual metadata about the world, not a claim about a
review, and `P0_G3_RIGHTS_GOVERNANCE.md` says so outright. What changed is
only that a capture must now be re-checkable, never when it may happen.

## Reused, not duplicated

`REQUIRED_RIGHTS_FIELDS`/`SOURCE_CLASSES`/`PRIORITIES` mirror
`core/equipment_identity/p0/source_registry.schema.json` and
`rights_decision.schema.json` field-for-field — this module is the
executable enforcement those schemas can only describe (a static schema
cannot express "trainingCodeCommit must resolve in this repo"-style cross
checks; here, "an UNREVIEWED source is never eligible" is exactly that kind
of check).
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path, PurePosixPath, PureWindowsPath
from typing import Any

REPO = Path(__file__).resolve().parents[2]
P0_DIR = REPO / "core" / "equipment_identity" / "p0"
SOURCE_REGISTRY = P0_DIR / "source_registry.json"

#: The only directory a captured-terms snapshot may live in. A recorded
#: `termsSnapshotPath` is written relative to the repository root and must
#: still resolve inside HERE -- see `_resolve_terms_snapshot` for the two
#: independent guards that enforce it and for why they are two.
TERMS_SNAPSHOT_ROOT = P0_DIR / "terms_snapshots"

SOURCE_CLASSES = frozenset({
    "OFFICIAL_MANUFACTURER", "OFFICIAL_BIM", "WGER", "EXERCISEDB",
    "API_NINJAS", "DISTRIBUTOR", "REFURBISHED_USED", "MARKETPLACE_3D",
    "SEARCH_DISCOVERY", "OTHER",
})

PRIORITIES = frozenset({"P0", "P1", "P2", "ENRICHMENT", "STAGING", "DISCOVERY_ONLY"})

LEGAL_REVIEW_STATES = frozenset({"UNREVIEWED", "REVIEWED", "BLOCKED"})

#: Which priorities a given sourceClass may declare — priority is not a free
#: per-record choice; it is determined by what kind of source this is.
#: SEARCH_DISCOVERY's single legal priority is the structural half of "search
#: discovery can never be a training/display source": it is impossible for a
#: SEARCH_DISCOVERY record to even pass registry validation with any other
#: priority, let alone reach an eligibility check.
CANONICAL_PRIORITIES_BY_SOURCE_CLASS: dict[str, frozenset[str]] = {
    "OFFICIAL_MANUFACTURER": frozenset({"P0", "P1"}),
    "OFFICIAL_BIM": frozenset({"P0", "P1"}),
    "WGER": frozenset({"ENRICHMENT"}),
    "EXERCISEDB": frozenset({"STAGING"}),
    "API_NINJAS": frozenset({"STAGING"}),
    "DISTRIBUTOR": frozenset({"P1", "P2"}),
    "REFURBISHED_USED": frozenset({"P2"}),
    "MARKETPLACE_3D": frozenset({"STAGING"}),
    "SEARCH_DISCOVERY": frozenset({"DISCOVERY_ONLY"}),
    "OTHER": frozenset({"STAGING", "ENRICHMENT", "P2"}),
}

REQUIRED_RIGHTS_FIELDS: tuple[str, ...] = (
    "legalReviewState", "commercialAllowed", "displayAllowed",
    "recognitionProcessingAllowed", "trainingAllowed", "derivativeAllowed",
    "redistributionAllowed", "attributionRequired", "shareAlike",
    "noAiRestriction", "termsCaptured",
)

REQUIRED_RIGHTS_BOOLEAN_FIELDS: tuple[str, ...] = tuple(
    f for f in REQUIRED_RIGHTS_FIELDS if f != "legalReviewState"
)

#: The subset of REQUIRED_RIGHTS_BOOLEAN_FIELDS that actually GRANT a use —
#: what "zero fake permissions on an UNREVIEWED source" means. Deliberately
#: excludes `attributionRequired`/`shareAlike` (obligations, not grants — true
#: only makes a use MORE restrictive) and `termsCaptured`/`noAiRestriction`
#: (factual/restriction metadata, not permissions): terms text can honestly be
#: captured before anyone reviews it, and a No-AI restriction is the opposite
#: of a grant.
PERMISSION_FIELDS: tuple[str, ...] = (
    "commercialAllowed", "displayAllowed", "recognitionProcessingAllowed",
    "trainingAllowed", "derivativeAllowed", "redistributionAllowed",
)

REQUIRED_SOURCE_FIELDS: tuple[str, ...] = (
    "sourceId", "providerName", "sourceClass", "priority",
    "canonicalUrl", "retrievedAt", "termsUrl", "rights",
)

_SOURCE_ID_RE = re.compile(r"^[a-z0-9][a-z0-9_-]*$")

#: A sha256 digest, ending with the same portable end-of-input assertion as
#: `IDENTIFIER_PATTERN` below and for the same measured reason: Python's `$`
#: also matches just before a trailing newline while JavaScript's does not, so
#: `"a"*64 + "\n"` was accepted here and by the JSON Schema while the Zod
#: mirror refused it. Not a permission bypass — the byte comparison rejects
#: such a digest anyway — but it made "all three layers agree" untrue.
SHA256_PATTERN = r"^[0-9a-f]{64}(?![\s\S])"
_SHA256_RE = re.compile(SHA256_PATTERN)

#: The lexical shape of a recorded `termsSnapshotPath`, shared verbatim with
#: `rights_decision.schema.json` and the Zod mirror. A relative POSIX-style
#: path of conservative components, nothing else.
#:
#: The component alphabet is what closes an NTFS **alternate data stream**:
#: `terms.txt:legal-review` is lexically innocent — not absolute, no drive, no
#: `..`, resolving to a regular file inside the snapshot root — but on NTFS it
#: addresses a SEPARATE stream whose bytes Git has never seen and cannot
#: store, and `.gitattributes -text` does nothing for it. Measured: before
#: this pattern existed, such a record validated and its hash matched, so a
#: legal decision could be bound to bytes that do not exist in a fresh
#: checkout. Colons are refused on every platform, not just Windows: a path
#: that names one file on Linux and a hidden stream on Windows is not the
#: portable repository reference this field claims to be.
#:
#: Deliberately does NOT reject `..` — a `..` component matches
#: `[A-Za-z0-9._-]+` quite happily. That is what keeps the explicit `..` ban
#: in `_resolve_terms_snapshot` separately load-bearing and separately
#: mutation-provable, instead of being silently subsumed here. For the same
#: reason this check runs AFTER the absolute/drive checks rather than before.
SNAPSHOT_PATH_PATTERN = r"^[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+)*(?![\s\S])"
_SNAPSHOT_PATH_RE = re.compile(SNAPSHOT_PATH_PATTERN)

#: One grammar for every scope identifier: `rightsScope.keyNamespace`, each
#: member of `rightsScope.keys`, and both halves of `SubjectRef`. The exact
#: same pattern TEXT also appears in `rights_decision.schema.json` and in the
#: Zod mirror at `functions-equipment-identity/src/p1/contracts.ts` — and the
#: two odd-looking choices in it are precisely what make that sharing honest
#: instead of decorative. Identical characters are not identical meaning:
#:
#: * The alphabet is enumerated ASCII, never `\w` or `\S`, because Python and
#:   JavaScript disagree about which code points count as whitespace. Measured
#:   in both engines, not assumed: Python's `\S` REJECTS U+0085 and ACCEPTS
#:   U+FEFF; JavaScript's does exactly the opposite. A shared `\S` pattern is
#:   two engines' differing opinions wearing one costume.
#: * The end assertion is `(?![\s\S])`, not `$`, because Python's `$` also
#:   matches just before a trailing newline while JavaScript's does not — so
#:   `"abc\n"` would be a legal identifier to Python AND to the `jsonschema`
#:   package (which compiles `pattern` with Python's own `re`) while Zod
#:   refused it, leaving two layers agreeing and the third silently apart.
#:   `[\s\S]` is a set unioned with its own complement, so it means "any
#:   character" in BOTH engines no matter what either calls whitespace, and
#:   the negative lookahead is therefore a true end-of-input in both.
#:
#: Whitespace is absent from the alphabet rather than merely banned at the
#: edges, so an empty or whitespace-only identifier cannot be formed at all —
#: which is the point, since the whole reason this boundary exists is that a
#: grant must not be readable as covering a population nobody reviewed.
#: Non-ASCII identifiers are refused deliberately: a source whose upstream
#: keys cannot be expressed here fails closed and says so, rather than being
#: silently transliterated into something that no longer identifies anything.
#:
#: If you are about to "simplify" this to `^[\w.:-]+$`, read the two bullets
#: above first — `scripts/equipment_identity/test_rights.py` will catch you,
#: but it will cost you the afternoon.
IDENTIFIER_PATTERN = r"^[A-Za-z0-9](?:[A-Za-z0-9._:-]*[A-Za-z0-9])?(?![\s\S])"
_IDENTIFIER_RE = re.compile(IDENTIFIER_PATTERN)

#: The two shapes a `rightsScope` may take. `WHOLE_SOURCE` says every subject
#: in the declared namespace is covered; `SUBSET` enumerates the covered keys.
SCOPE_KINDS = frozenset({"WHOLE_SOURCE", "SUBSET"})

#: The uses a caller may ask about — NAMES, deliberately, not the callables
#: that answer. An earlier version of this module exported a dict mapping each
#: use to its eligibility function, which meant a caller could reach a
#: permission through `ELIGIBILITY_BY_USE["DISPLAY"](record)` without ever
#: presenting a subject. Renaming the functions would not have closed that;
#: publishing names instead of callables does. See `eligible_for`.
USES: tuple[str, ...] = (
    "DISPLAY", "RECOGNITION_PROCESSING", "TRAINING", "DERIVATIVE", "REDISTRIBUTION",
)


class RightsValidationError(RuntimeError):
    """A registry record that cannot honestly support the rights claim it
    makes — either malformed, or missing the evidence a REVIEWED state
    requires."""


@dataclass(frozen=True)
class SubjectRef:
    """The object a permission is being asked about, named in full.

    Both halves are required and both are checked HERE, at construction.
    `frozen=True` only prevents reassignment; it says nothing whatever about
    content, so without this `__post_init__` a `SubjectRef("", "")` would be
    a perfectly well-formed subject whose identity is nothing at all. On a
    boundary that exists specifically so a grant cannot be read as covering a
    population it was never reviewed for, an identity that collapses to empty
    is the failure worth making impossible rather than merely unlikely.

    The namespace is not decoration. Two upstream catalogues can easily both
    number an item `123`, and only the namespace distinguishes them — so it
    participates in every authorization decision, including under
    `WHOLE_SOURCE` (see `_subject_in_scope`).
    """

    key_namespace: str
    key: str

    def __post_init__(self) -> None:
        for field_name in ("key_namespace", "key"):
            value = getattr(self, field_name)
            # `.search`, not `.match`, so this is literally the same operation
            # a JSON Schema `pattern` performs — the anchors in the pattern do
            # the anchoring, and no layer gets a subtly different one.
            if not isinstance(value, str) or not _IDENTIFIER_RE.search(value):
                raise RightsValidationError(
                    f"SubjectRef.{field_name} {value!r} is not a valid scope identifier "
                    f"(must match {IDENTIFIER_PATTERN})"
                )


def _looks_like_iso_datetime(value: Any) -> bool:
    if not isinstance(value, str):
        return False
    try:
        datetime.fromisoformat(value.replace("Z", "+00:00"))
        return True
    except ValueError:
        return False


def _resolve_terms_snapshot(path_value: Any, *, context: str) -> Path:
    """Turn a recorded `termsSnapshotPath` into a real file inside the
    snapshot root, or refuse it.

    THREE checks, and the third is not a third guard — read the note on
    subsumption below before adding a fourth.

    * **The grammar** (`SNAPSHOT_PATH_PATTERN`) runs on the recorded text
      before anything touches the filesystem and admits one shape only:
      `/`-separated components drawn from `[A-Za-z0-9._-]`. Everything a path
      needs in order to be absolute, drive-qualified or UNC — a leading `/`, a
      `:`, a `\\` — is outside that alphabet, so those forms are refused by
      the shape rule rather than by a check of their own. So is a colon
      naming an NTFS alternate data stream, and so is any stray whitespace or
      non-ASCII character that would name different files on different
      platforms.
    * **The `..` ban** is separate and stays separate, because it catches
      something the grammar structurally cannot: `sub/../terms.txt` is a
      perfectly well-shaped relative path. It would resolve INSIDE the root,
      which resolution alone accepts happily, because the answer really is
      inside.
    * **Resolved containment** resolves both sides, following symlinks and
      junctions, and refuses a target outside the root or one that is not a
      regular file. It catches a lexically spotless name that simply IS a link
      pointing somewhere else, which no amount of string inspection can see.

    **On the guard that used to be here.** An explicit absolute/drive/UNC
    check ran before the grammar, and the comment where it stood claimed each
    ordered check kept a fixture only IT rejected. That claim was false, and a
    closure review caught it: every absolute form is already outside the
    grammar's alphabet. Measured rather than argued — an exhaustive search over
    11,110 strings built from that alphabet plus `:`, `\\`, `/` and space found
    NO string the grammar accepts and the absolute check would reject. It was
    therefore unkillable by construction: deleting it left every test green.

    It is gone rather than kept as defence in depth, deliberately. A guard no
    test can distinguish from its own absence is not depth; it is a claim, and
    this contract has already been bitten twice by a check that described more
    than it did. The absolute, drive and UNC forms are still refused — by the
    grammar, with fixtures in `scope_identifier_cases.json` proving it in all
    three engines, and with a mutation proving the grammar itself is
    load-bearing. Anything added here in future must come with a fixture that
    ONLY it rejects, or it belongs in the grammar.
    """
    if not isinstance(path_value, str) or not path_value.strip():
        raise RightsValidationError(
            f"{context}: termsSnapshotPath must be a non-empty string, got {path_value!r}"
        )

    if not _SNAPSHOT_PATH_RE.search(path_value):
        raise RightsValidationError(
            f"{context}: termsSnapshotPath {path_value!r} is not a portable relative path "
            f"(must match {SNAPSHOT_PATH_PATTERN}) — it must be relative to the repository "
            "root, so a leading '/', a drive letter or a UNC prefix would bind a legal "
            "decision to bytes that are not in this repository at all; a colon would name "
            "an NTFS alternate data stream whose bytes Git never stored; and a backslash "
            "or stray whitespace would name different files on different platforms"
        )
    # Separate from the grammar, and separately provable: `sub/../terms.txt`
    # matches the shape rule and is refused only here.
    windows = PureWindowsPath(path_value)
    posix = PurePosixPath(path_value)
    if ".." in windows.parts or ".." in posix.parts:
        raise RightsValidationError(
            f"{context}: termsSnapshotPath {path_value!r} contains a '..' component; a "
            "snapshot path may not climb out of the repository, even if it climbs back in"
        )

    root = TERMS_SNAPSHOT_ROOT.resolve()
    candidate = (REPO / path_value).resolve()
    if not candidate.is_relative_to(root):
        raise RightsValidationError(
            f"{context}: termsSnapshotPath {path_value!r} resolves to {candidate}, which "
            f"is outside the snapshot root {root} — a link out of the root is still out "
            "of the root"
        )
    if not candidate.is_file():
        raise RightsValidationError(
            f"{context}: termsSnapshotPath {path_value!r} is not a regular file"
        )
    return candidate


def _validate_rights_scope(scope: Any, *, context: str) -> None:
    """Refuse a `rightsScope` that cannot answer "is THIS object covered?".

    Absent, malformed or unrecognised scope grants nothing — the same
    direction this module already takes for an UNREVIEWED source, and for the
    same reason: the failure mode worth engineering against is a grant that
    quietly reads as broader than the review behind it.
    """
    if not isinstance(scope, dict):
        raise RightsValidationError(
            f"{context}: rights.rightsScope must be an object, got {scope!r}"
        )

    kind = scope.get("kind")
    if kind not in SCOPE_KINDS:
        raise RightsValidationError(
            f"{context}: rights.rightsScope.kind {kind!r} is not one of {sorted(SCOPE_KINDS)}"
        )

    expected = {"kind", "keyNamespace"} | ({"keys"} if kind == "SUBSET" else set())
    missing = sorted(expected - set(scope))
    unexpected = sorted(set(scope) - expected)
    if missing:
        raise RightsValidationError(f"{context}: rights.rightsScope missing {missing}")
    if unexpected:
        raise RightsValidationError(
            f"{context}: rights.rightsScope has unexpected field(s) {unexpected} for "
            f"kind={kind}"
        )

    namespace = scope["keyNamespace"]
    if not isinstance(namespace, str) or not _IDENTIFIER_RE.search(namespace):
        raise RightsValidationError(
            f"{context}: rights.rightsScope.keyNamespace {namespace!r} is not a valid "
            f"scope identifier (must match {IDENTIFIER_PATTERN})"
        )

    if kind == "SUBSET":
        keys = scope["keys"]
        if not isinstance(keys, list) or not keys:
            raise RightsValidationError(
                f"{context}: rights.rightsScope.keys must be a non-empty array; a SUBSET "
                "covering nothing is an ambiguity, not a grant"
            )
        for key in keys:
            if not isinstance(key, str) or not _IDENTIFIER_RE.search(key):
                raise RightsValidationError(
                    f"{context}: rights.rightsScope.keys entry {key!r} is not a valid "
                    f"scope identifier (must match {IDENTIFIER_PATTERN})"
                )


def validate_rights(rights: dict[str, Any], *, context: str) -> None:
    missing = [f for f in REQUIRED_RIGHTS_FIELDS if f not in rights]
    if missing:
        raise RightsValidationError(f"{context}: rights object missing {missing}")

    state = rights["legalReviewState"]
    if state not in LEGAL_REVIEW_STATES:
        raise RightsValidationError(
            f"{context}: legalReviewState {state!r} is not one of {sorted(LEGAL_REVIEW_STATES)}"
        )

    for field in REQUIRED_RIGHTS_BOOLEAN_FIELDS:
        if not isinstance(rights[field], bool):
            raise RightsValidationError(
                f"{context}: rights.{field} must be a boolean, got {rights[field]!r}"
            )

    if state in ("UNREVIEWED", "BLOCKED"):
        granted = [f for f in PERMISSION_FIELDS if rights[f] is True]
        if granted:
            raise RightsValidationError(
                f"{context}: legalReviewState={state} but {granted} is/are "
                f"already true — only a REVIEWED source may carry a granted "
                "permission; zero fake permissions is a P0.G3 close condition"
            )

    if state in ("REVIEWED", "BLOCKED") and not rights.get("reviewedAt"):
        raise RightsValidationError(
            f"{context}: legalReviewState={state} requires reviewedAt to be set"
        )
    if state in ("REVIEWED", "BLOCKED") and rights["termsCaptured"] is not True:
        raise RightsValidationError(
            f"{context}: legalReviewState={state} requires termsCaptured=true — "
            "REVIEWED means a human reviewed actual captured terms, not a "
            "reputation- or category-based guess, and BLOCKED means a human read "
            "those terms and concluded no. A source whose terms could not be "
            "reached at all is UNREVIEWED, which is already fail-closed and is "
            "already the honest word for 'nobody could look'"
        )
    if rights.get("reviewedAt") is not None and not _looks_like_iso_datetime(rights["reviewedAt"]):
        raise RightsValidationError(f"{context}: reviewedAt is not a valid ISO-8601 timestamp")
    if rights.get("recheckAt") is not None and not _looks_like_iso_datetime(rights["recheckAt"]):
        raise RightsValidationError(f"{context}: recheckAt is not a valid ISO-8601 timestamp")

    # --- The evidence/scope matrix ------------------------------------------
    #
    # Four rows, reducing to two rules: a capture must be bound to real bytes
    # in EVERY state, and a scope belongs to exactly one state.
    #
    #   UNREVIEWED + termsCaptured=false  snapshot forbidden, scope forbidden
    #   UNREVIEWED + termsCaptured=true   snapshot required,  scope forbidden
    #   REVIEWED                          snapshot required,  scope required
    #   BLOCKED                           snapshot required,  scope forbidden
    #
    # The second row is capture-before-review and it is deliberate: terms text
    # can honestly exist before anyone has reviewed it, which
    # `core/equipment_identity/p0/P0_G3_RIGHTS_GOVERNANCE.md` states outright.
    # Folding capture and legal review into one atomic act would have been a
    # quiet regression of that, so what changed is only that a capture must
    # now be re-checkable — not when it is allowed to happen.
    #
    # BLOCKED forbids a scope because BLOCKED grants nothing, so a scope on it
    # could only mean a PARTIAL block — which this contract cannot express and
    # should not appear to. That limitation is named here rather than left for
    # someone to discover from behaviour.
    captured = rights["termsCaptured"]
    has_path = "termsSnapshotPath" in rights
    has_hash = "termsSnapshotSha256" in rights

    if captured:
        if not (has_path and has_hash):
            raise RightsValidationError(
                f"{context}: termsCaptured=true requires BOTH termsSnapshotPath and "
                "termsSnapshotSha256 — a captured snapshot nobody can re-read is a "
                "boolean somebody set, not evidence"
            )
        declared = rights["termsSnapshotSha256"]
        if not (isinstance(declared, str) and _SHA256_RE.search(declared)):
            raise RightsValidationError(
                f"{context}: termsSnapshotSha256 {declared!r} is not a 64-hex-character sha256"
            )
        snapshot = _resolve_terms_snapshot(rights["termsSnapshotPath"], context=context)
        actual = hashlib.sha256(snapshot.read_bytes()).hexdigest()
        if actual != declared:
            raise RightsValidationError(
                f"{context}: termsSnapshotSha256 says {declared} but the bytes at "
                f"{rights['termsSnapshotPath']} hash to {actual} — the decision is not "
                "bound to the terms it claims to rest on"
            )
    elif has_path or has_hash:
        raise RightsValidationError(
            f"{context}: termsSnapshotPath/termsSnapshotSha256 is set but "
            "termsCaptured=false — a captured snapshot without the flag admitting it "
            "is captured is exactly the kind of drift this registry exists to prevent"
        )

    scope = rights.get("rightsScope")
    if state == "REVIEWED":
        if scope is None:
            raise RightsValidationError(
                f"{context}: legalReviewState=REVIEWED requires rightsScope — a grant "
                "with no stated population reads as covering the whole source, which "
                "is a claim the review behind it may never have made"
            )
        _validate_rights_scope(scope, context=context)
    elif scope is not None:
        raise RightsValidationError(
            f"{context}: legalReviewState={state} must not carry rightsScope — only a "
            "REVIEWED source grants anything, so a scope anywhere else either means "
            "nothing or means a partial block this contract cannot express"
        )


def validate_source_record(record: dict[str, Any]) -> None:
    missing = [f for f in REQUIRED_SOURCE_FIELDS if f not in record]
    if missing:
        raise RightsValidationError(f"source record missing {missing}")

    source_id = record["sourceId"]
    if not (isinstance(source_id, str) and _SOURCE_ID_RE.match(source_id)):
        raise RightsValidationError(f"sourceId {source_id!r} does not match {_SOURCE_ID_RE.pattern}")

    context = f"source {source_id!r}"

    if not isinstance(record["providerName"], str) or not record["providerName"].strip():
        raise RightsValidationError(f"{context}: providerName must be a non-empty string")

    source_class = record["sourceClass"]
    if source_class not in SOURCE_CLASSES:
        raise RightsValidationError(f"{context}: sourceClass {source_class!r} not in {sorted(SOURCE_CLASSES)}")

    priority = record["priority"]
    if priority not in PRIORITIES:
        raise RightsValidationError(f"{context}: priority {priority!r} not in {sorted(PRIORITIES)}")
    allowed_priorities = CANONICAL_PRIORITIES_BY_SOURCE_CLASS[source_class]
    if priority not in allowed_priorities:
        raise RightsValidationError(
            f"{context}: sourceClass={source_class} may only declare priority "
            f"in {sorted(allowed_priorities)}, got {priority!r} — priority is "
            "determined by source class, not freely chosen per record"
        )

    if not isinstance(record["canonicalUrl"], str) or not record["canonicalUrl"].strip():
        raise RightsValidationError(f"{context}: canonicalUrl must be a non-empty string")
    if not _looks_like_iso_datetime(record["retrievedAt"]):
        raise RightsValidationError(f"{context}: retrievedAt is not a valid ISO-8601 timestamp")
    if record["termsUrl"] is not None and not isinstance(record["termsUrl"], str):
        raise RightsValidationError(f"{context}: termsUrl must be a string or null")

    rights = record["rights"]
    if not isinstance(rights, dict):
        raise RightsValidationError(f"{context}: rights must be an object, got {rights!r}")
    validate_rights(rights, context=context)


def load_registry(path: Path = SOURCE_REGISTRY) -> list[dict[str, Any]]:
    """Load and fully validate every entry. Raises on the first invalid
    record rather than returning a partially-trustworthy list.

    Also enforces sourceId uniqueness across the whole registry (reviewer-
    found gap, P1.G2 review, 2026-08-22): neither this function nor the
    JSON Schema previously checked for a duplicate sourceId, so a future
    copy-paste record (e.g. cloning an existing entry and only editing
    canonicalUrl/decisionBasis, leaving sourceId stale) would pass every
    per-record check and then silently shadow the original in any consumer
    that builds a {sourceId: record} map -- exactly the kind of silent
    provenance loss this registry exists to prevent."""
    data = json.loads(path.read_text(encoding="utf-8"))
    sources = data.get("sources", [])
    if not sources:
        raise RightsValidationError(f"{path}: registry has no sources")
    seen_ids: set[str] = set()
    for record in sources:
        validate_source_record(record)
        source_id = record["sourceId"]
        if source_id in seen_ids:
            raise RightsValidationError(f"{path}: duplicate sourceId {source_id!r}")
        seen_ids.add(source_id)
    return sources


# ---------------------------------------------------------------------------
# Fail-closed eligibility. Every function takes the WHOLE source record (not
# just `rights`) so a SEARCH_DISCOVERY-priority record can be refused
# structurally, in addition to whatever its rights booleans happen to say —
# defence in depth against a future bug that sets a permission boolean true
# on a class that must never carry one.
# ---------------------------------------------------------------------------

def _reviewed(record: dict[str, Any]) -> bool:
    return record["rights"]["legalReviewState"] == "REVIEWED"


def _not_discovery_only(record: dict[str, Any]) -> bool:
    return record["priority"] != "DISCOVERY_ONLY"


def _commercially_allowed(record: dict[str, Any], subject: Any) -> bool:
    # SPTR is a commercial product -- every privileged use happens in that
    # context, so a source that is REVIEWED+*Allowed but explicitly not
    # cleared for commercial use must still be refused for every use, not
    # just silently accepted because no single use-specific flag mentions
    # "commercial." See P0_G3_RIGHTS_GOVERNANCE.md's review record.
    #
    # It takes `subject` and demands it although it never reads it, which
    # looks like noise and is not. The structural check in test_rights.py
    # enforces one rule with no allowlist -- ANY module-level function that
    # reads a name in PERMISSION_FIELDS must require a subject -- and an
    # allowlist of "helpers that are exempt" is exactly the bookkeeping that
    # goes stale and lets the next bypass through. Paying one unused
    # parameter here keeps that rule mechanical.
    _require_subject(subject)
    return record["rights"]["commercialAllowed"]


def _require_subject(subject: Any) -> SubjectRef:
    """Refuse to answer a permission question that names no object.

    Called by `eligible_for` AND by every per-use predicate below, which is
    redundant on the happy path and deliberately so: the redundancy is what
    makes the subject requirement structural rather than a convention held up
    by whoever remembers to route through the front door.
    """
    if not isinstance(subject, SubjectRef):
        raise RightsValidationError(
            f"a permission question needs the object it is about: expected SubjectRef, "
            f"got {type(subject).__name__}"
        )
    return subject


def _subject_in_scope(record: dict[str, Any], subject: SubjectRef) -> bool:
    """Is THIS object inside the population the source was reviewed for?

    Only ever consulted for a REVIEWED record — every caller checks
    `_reviewed` first, and validation guarantees a REVIEWED record carries a
    well-formed scope — so there is no state here in which `rightsScope` is
    absent.

    The namespace must match for BOTH kinds, including `WHOLE_SOURCE`. Two
    upstream catalogues can each number an item `123`, and only the namespace
    tells them apart; a grant reviewed for one catalogue saying yes to the
    other's identically-numbered item would be exactly the over-broad read
    this whole mechanism exists to prevent.

    `WHOLE_SOURCE` then admits any key in that namespace, and this is a
    deliberate act of trust in upstream provenance rather than an oversight:
    the registry holds no population oracle, so it genuinely cannot know that
    some key does NOT belong to a source. An earlier draft of this contract
    claimed an "unknown" key would be denied; nothing could have implemented
    that, so the claim was removed rather than left standing as decoration.
    What IS knowable is the namespace, because the source declares it — hence
    namespace matching for both kinds and key matching only under SUBSET.
    """
    scope = record["rights"]["rightsScope"]
    if subject.key_namespace != scope["keyNamespace"]:
        return False
    if scope["kind"] == "WHOLE_SOURCE":
        return True
    return subject.key in scope["keys"]


def _eligible_for_display(record: dict[str, Any], subject: Any) -> bool:
    _require_subject(subject)
    return (
        _not_discovery_only(record)
        and _reviewed(record)
        and _subject_in_scope(record, subject)
        and _commercially_allowed(record, subject)
        and record["rights"]["displayAllowed"]
    )


def _eligible_for_recognition_processing(record: dict[str, Any], subject: Any) -> bool:
    _require_subject(subject)
    rights = record["rights"]
    return (
        _not_discovery_only(record)
        and _reviewed(record)
        and _subject_in_scope(record, subject)
        and _commercially_allowed(record, subject)
        and rights["recognitionProcessingAllowed"]
        and not rights["noAiRestriction"]
    )


def _eligible_for_training(record: dict[str, Any], subject: Any) -> bool:
    _require_subject(subject)
    rights = record["rights"]
    return (
        _not_discovery_only(record)
        and _reviewed(record)
        and _subject_in_scope(record, subject)
        and _commercially_allowed(record, subject)
        and rights["trainingAllowed"]
        and not rights["noAiRestriction"]
    )


def _eligible_for_derivative(record: dict[str, Any], subject: Any) -> bool:
    _require_subject(subject)
    rights = record["rights"]
    return (
        _not_discovery_only(record)
        and _reviewed(record)
        and _subject_in_scope(record, subject)
        and _commercially_allowed(record, subject)
        and rights["derivativeAllowed"]
        and not rights["noAiRestriction"]
    )


def _eligible_for_redistribution(record: dict[str, Any], subject: Any) -> bool:
    _require_subject(subject)
    return (
        _not_discovery_only(record)
        and _reviewed(record)
        and _subject_in_scope(record, subject)
        and _commercially_allowed(record, subject)
        and record["rights"]["redistributionAllowed"]
    )


#: Private, and its entries are private too, and each entry independently
#: demands the subject. Any ONE of those three would be defeatable on its own:
#: a leading underscore is a convention, a private table can still be reached
#: by name, and a front-door check is only as good as the front door being the
#: only door. Together they mean no route through this module answers "may I?"
#: without being told "about what?".
_ELIGIBILITY_BY_USE: dict[str, Any] = {
    "DISPLAY": _eligible_for_display,
    "RECOGNITION_PROCESSING": _eligible_for_recognition_processing,
    "TRAINING": _eligible_for_training,
    "DERIVATIVE": _eligible_for_derivative,
    "REDISTRIBUTION": _eligible_for_redistribution,
}


def eligible_for(record: dict[str, Any], use: str, subject: Any) -> bool:
    """The single public way to obtain a permission — record, use, and the
    object being asked about.

    P1.G1 §6.8 hardening (forward note accepted at P0.G3 close): validating
    the record HERE, before any eligibility field is read, means a
    malformed/inconsistent record can never silently produce a `True` (or a
    wrong `False`) by having its fields misread. Previously each per-use
    function trusted its `record` argument structurally, so a record that had
    skipped `validate_source_record` could raise a bare `KeyError`/`TypeError`
    instead of the typed `RightsValidationError` every other rights failure
    raises — or, worse, could have a booleanish-but-wrong value read as truthy.

    The `subject` argument is not optional and has no default. A default would
    have made "no particular object" the cheapest thing to write at every call
    site, and the whole point of this parameter is that the cheapest thing to
    write should be the honest one.
    """
    _require_subject(subject)
    validate_source_record(record)
    if use not in _ELIGIBILITY_BY_USE:
        raise RightsValidationError(f"unknown use {use!r}, expected one of {sorted(USES)}")
    return _ELIGIBILITY_BY_USE[use](record, subject)


def _describe_scope(rights: dict[str, Any]) -> str:
    scope = rights.get("rightsScope")
    if scope is None:
        return "scope=NONE"
    if scope["kind"] == "WHOLE_SOURCE":
        return f"scope=WHOLE_SOURCE:{scope['keyNamespace']}"
    return f"scope=SUBSET:{scope['keyNamespace']}({len(scope['keys'])} key(s))"


def main() -> int:
    """Validate the registry and describe each source's rights STATE.

    This deliberately does not print per-use eligibility any more. Eligibility
    is now a question about a specific object, and this diagnostic has no
    object to ask about — feeding it a synthetic subject would print a
    permission concerning something that does not exist, which is a worse
    answer than no answer. Nothing informative was lost in the change: every
    source in the registry is UNREVIEWED, so the old column read
    `eligible_for=NONE` for all of them.
    """
    sources = load_registry()
    print(f"{len(sources)} source(s) validated")
    for record in sources:
        rights = record["rights"]
        captured = "captured" if rights["termsCaptured"] else "no-capture"
        print(
            f"  {record['sourceId']:40} {rights['legalReviewState']:10} "
            f"{captured:10} {_describe_scope(rights)}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
