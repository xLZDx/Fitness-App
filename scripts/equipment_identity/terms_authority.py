"""B1 steps 3, 4 and 6 -- the authority chain.

THE ONE IDEA
------------
A reference string is not authority. Four conditions must hold before a basis
authorises anything, and existence is the WEAKEST of them:

1. the reference resolves to a committed (or injected) basis record;
2. that record explicitly carries the CAPABILITY being asked for;
3. its scope covers this SOURCE;
4. its scope covers this CANDIDATE DOCUMENT and this ACQUISITION METHOD.

An earlier revision of this gate required only (1). That reintroduced, one code
path later, exactly the defect the network path had just been fixed for: a
command-line string that authorises itself. Obtaining a document and having the
right to keep a copy are different questions, so ACQUISITION and RETENTION are
separate capabilities and **neither implies the other**.

WHY THE ORIGIN CARRIES A PORT
-----------------------------
`https://host` and `https://host:8443` are different origins. Keying
authorization on `(scheme, host)` alone silently merges them, so an authorization
for the ordinary site would cover an unrelated service on another port of the
same machine. The key is `(scheme, host, effective_port)`, with the effective
port defaulted from the scheme so `https://h` and `https://h:443` are the same
origin -- which they are.

WHY INJECTION IS A PARAMETER AND NOT A FLAG
-------------------------------------------
Tests pass registries in as arguments. There is deliberately no `--basis-file`
or equivalent on any shipped command line: a caller able to hand over the
authority it is being checked against is not being checked.

WHY sourceId IS RESOLVED HERE TOO
---------------------------------
`sourceId` reaches filesystem paths, so hardening only `candidateDocId` would
leave this tool's boundary wider than the three records it claims to govern. It
is looked up in the real registry, compared BYTE-FOR-BYTE with the stored id,
and required to be a B1 target -- all before any path is constructed. That is
also why the pre-existing `_SOURCE_ID_RE` defect in `rights.py` (a `$`
terminator, which accepts a trailing newline) cannot reach this tool: nothing
here trusts the caller's string, it only ever uses the stored one.
"""

from __future__ import annotations

import json
import pathlib
from typing import Any
from urllib.parse import urlsplit

from terms_acquisition import B1_TARGET_SOURCE_IDS, P0_DIR

# Deliberately NOT re-validating the candidateDocId grammar here. `resolve_candidate`
# is the door a document enters through and enforces it there; repeating it would be
# a guard no fixture could distinguish from its own absence, which this repository
# has already deleted once (`rights.py::_resolve_terms_snapshot`). What this module
# checks about a candidate is SCOPE MEMBERSHIP, which is a different question.

BASES_PATH = P0_DIR / "terms_acquisition_bases.json"
AUTHORIZATIONS_PATH = P0_DIR / "terms_acquisition_authorizations.json"
SOURCE_REGISTRY_PATH = P0_DIR / "source_registry.json"

CAPABILITIES: frozenset[str] = frozenset({"ACQUISITION", "RETENTION"})
ACQUISITION_METHODS: frozenset[str] = frozenset({
    "HUMAN_MANUAL_RETRIEVAL",
    "AUTOMATED_FETCH",
})
PERMITTING_STATE = "AUTO_FETCH_PERMITTED_BY_BASIS"

DEFAULT_PORTS = {"https": 443, "http": 80}


class AuthorityError(Exception):
    """A reference that does not authorise what it is being used for."""


# ---------------------------------------------------------------------------
# Loading. Every loader tolerates absence the same way: it raises AuthorityError
# rather than crashing, because a missing registry means "no authority", which
# is a state the system must be able to report rather than die on.
# ---------------------------------------------------------------------------

def _load_json(path: pathlib.Path, kind: str) -> dict[str, Any]:
    try:
        raw = path.read_bytes()
    except FileNotFoundError as exc:
        raise AuthorityError(f"{kind} registry not found at {path}") from exc
    try:
        doc = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise AuthorityError(f"{path}: not valid UTF-8 JSON -- {exc}") from exc
    if not isinstance(doc, dict):
        raise AuthorityError(f"{path}: {kind} registry must be a JSON object")
    return doc


def load_bases(path: pathlib.Path | None = None) -> dict[str, Any]:
    return _load_json(BASES_PATH if path is None else path, "basis")


def load_authorizations(path: pathlib.Path | None = None) -> dict[str, Any]:
    return _load_json(AUTHORIZATIONS_PATH if path is None else path, "authorization")


# ---------------------------------------------------------------------------
# Step 6 -- sourceId resolution.
# ---------------------------------------------------------------------------

def resolve_source_id(value: Any, registry: dict[str, Any] | None = None) -> str:
    """Return the STORED source id for `value`, or raise.

    Returns the registry's own string rather than the caller's, so nothing
    downstream can be built from a value that merely compared equal under some
    looser rule. Membership in the B1 target set is required here, not assumed
    by the caller.
    """
    if not isinstance(value, str):
        raise AuthorityError(f"sourceId must be a string, got {type(value).__name__}")

    doc = _load_json(SOURCE_REGISTRY_PATH, "source") if registry is None else registry
    sources = doc.get("sources")
    if not isinstance(sources, list):
        raise AuthorityError("source registry has no 'sources' list")

    for entry in sources:
        if not isinstance(entry, dict):
            continue
        stored = entry.get("sourceId")
        if not isinstance(stored, str):
            continue
        # Byte-for-byte. A trailing newline, different case or stray whitespace
        # is a DIFFERENT string, and this is the boundary that decides so.
        if stored.encode("utf-8") != value.encode("utf-8"):
            continue
        if stored not in B1_TARGET_SOURCE_IDS:
            raise AuthorityError(
                f"sourceId {stored!r} is a real registry record but not a B1 target "
                f"(targets: {', '.join(B1_TARGET_SOURCE_IDS)}) -- this gate governs three "
                "sources and may not construct a path for a fourth"
            )
        return stored

    raise AuthorityError(
        f"sourceId {value!r} matches no record in the source registry -- nothing is built "
        "from a caller's string, only from a stored one"
    )


# ---------------------------------------------------------------------------
# Step 3 -- basis resolution.
# ---------------------------------------------------------------------------

def _scope_covers(scope: Any, field: str, value: str, basis_ref: str) -> None:
    if not isinstance(scope, dict):
        raise AuthorityError(f"basis {basis_ref!r}: scope must be an object")
    allowed = scope.get(field)
    if not isinstance(allowed, list) or not allowed:
        raise AuthorityError(
            f"basis {basis_ref!r}: scope.{field} must be a non-empty list -- an absent "
            "scope dimension would read as 'everything', and a basis that covers "
            "everything by omission was never deliberately granted"
        )
    if value not in allowed:
        raise AuthorityError(
            f"basis {basis_ref!r}: scope.{field} does not cover {value!r} "
            f"(covers: {', '.join(map(str, allowed))})"
        )


def resolve_basis(
    basis_ref: Any,
    required_capability: str,
    source_id: str,
    candidate_doc_id: str,
    acquisition_method: str,
    registry: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Return the basis record that authorises exactly this, or raise.

    The ONLY route from a reference to authority, and the only function any code
    path may use for it -- so a future path cannot acquire a weaker one.
    """
    if required_capability not in CAPABILITIES:
        raise AuthorityError(
            f"unknown capability {required_capability!r} (known: {', '.join(sorted(CAPABILITIES))})"
        )
    if acquisition_method not in ACQUISITION_METHODS:
        raise AuthorityError(
            f"unknown acquisition method {acquisition_method!r} "
            f"(known: {', '.join(sorted(ACQUISITION_METHODS))})"
        )
    if not isinstance(basis_ref, str) or not basis_ref.strip():
        raise AuthorityError(f"basisRef must be a non-empty string, got {basis_ref!r}")

    doc = load_bases() if registry is None else registry
    bases = doc.get("bases")
    if not isinstance(bases, list):
        raise AuthorityError("basis registry has no 'bases' list")

    matches = [b for b in bases if isinstance(b, dict) and b.get("basisRef") == basis_ref]
    if not matches:
        raise AuthorityError(
            f"basisRef {basis_ref!r} resolves to nothing. A reference that names no record "
            "authorises nothing, however plausible the string"
        )
    if len(matches) > 1:
        raise AuthorityError(
            f"basisRef {basis_ref!r} matches {len(matches)} records -- resolution would "
            "depend on order, and order is not a rule"
        )

    basis = matches[0]
    capabilities = basis.get("capabilities")
    if not isinstance(capabilities, list) or not capabilities:
        raise AuthorityError(f"basis {basis_ref!r}: capabilities must be a non-empty list")
    unknown = [c for c in capabilities if c not in CAPABILITIES]
    if unknown:
        raise AuthorityError(f"basis {basis_ref!r}: unknown capabilities {unknown}")
    if required_capability not in capabilities:
        raise AuthorityError(
            f"basis {basis_ref!r} carries {sorted(capabilities)} and is being used for "
            f"{required_capability} -- acquisition and retention are separate rights and "
            "neither implies the other"
        )

    scope = basis.get("scope")
    _scope_covers(scope, "sourceIds", source_id, basis_ref)
    _scope_covers(scope, "candidateDocIds", candidate_doc_id, basis_ref)
    _scope_covers(scope, "acquisitionMethods", acquisition_method, basis_ref)
    return dict(basis)


# ---------------------------------------------------------------------------
# Step 4 -- origin normalization and authorization resolution.
# ---------------------------------------------------------------------------

def normalize_origin(url: str) -> tuple[str, str, int]:
    """`url` -> (scheme, host, effective port). Raises on anything unusable."""
    if not isinstance(url, str) or not url.strip():
        raise AuthorityError(f"url must be a non-empty string, got {url!r}")
    parts = urlsplit(url)
    scheme = parts.scheme.lower()
    if scheme not in DEFAULT_PORTS:
        raise AuthorityError(
            f"{url!r}: scheme {parts.scheme!r} is not one this tool speaks "
            f"({', '.join(sorted(DEFAULT_PORTS))})"
        )
    host = (parts.hostname or "").lower()
    if not host:
        raise AuthorityError(f"{url!r}: no host")
    try:
        port = parts.port
    except ValueError as exc:
        raise AuthorityError(f"{url!r}: unusable port -- {exc}") from exc
    return scheme, host, port if port is not None else DEFAULT_PORTS[scheme]


def resolve_authorization(
    url: str,
    source_id: str,
    candidate_doc_id: str,
    acquisition_method: str,
    registry: dict[str, Any] | None = None,
    basis_registry: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Return the authorization permitting a fetch of `url`, or raise.

    Called BEFORE a request is constructed, and again before following any
    redirect -- a chain validated after the fact gives the right verdict about a
    request that already happened.
    """
    origin = normalize_origin(url)
    doc = load_authorizations() if registry is None else registry
    entries = doc.get("authorizations")
    if not isinstance(entries, list):
        raise AuthorityError("authorization registry has no 'authorizations' list")

    matches = []
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        try:
            key = (
                str(entry["scheme"]).lower(),
                str(entry["host"]).lower(),
                int(entry["port"]),
            )
        except (KeyError, TypeError, ValueError) as exc:
            raise AuthorityError(
                f"authorization entry {entry!r} has no usable (scheme, host, port) key -- {exc}"
            ) from exc
        if key != origin:
            continue
        narrowed = entry.get("candidateDocId")
        if narrowed is not None and narrowed != candidate_doc_id:
            continue
        matches.append(entry)

    if not matches:
        raise AuthorityError(
            f"no authorization for origin {origin[0]}://{origin[1]}:{origin[2]} -- a request "
            "is not made unless an entry already permits it"
        )
    if len(matches) > 1:
        raise AuthorityError(
            f"{len(matches)} authorizations match origin {origin[0]}://{origin[1]}:{origin[2]} "
            "-- overlapping entries REFUSE rather than resolve by precedence"
        )

    entry = matches[0]
    state = entry.get("state")
    if state != PERMITTING_STATE:
        raise AuthorityError(
            f"authorization for {origin[1]} is in state {state!r}, not {PERMITTING_STATE}"
        )

    # The whole point: the entry's own reference must itself resolve, with the
    # ACQUISITION capability, for this source, document and method.
    resolve_basis(
        entry.get("basisRef"),
        "ACQUISITION",
        source_id,
        candidate_doc_id,
        acquisition_method,
        registry=basis_registry,
    )
    return dict(entry)


# ---------------------------------------------------------------------------
# Step 5 -- what the SHIPPED registries contain.
# ---------------------------------------------------------------------------

def shipped_authority_summary() -> dict[str, Any]:
    """Report the committed registries' contents, for the closure assertion."""
    bases = load_bases().get("bases", [])
    auths = load_authorizations().get("authorizations", [])
    permitting = [a for a in auths if isinstance(a, dict) and a.get("state") == PERMITTING_STATE]
    return {
        "basisCount": len(bases),
        "authorizationCount": len(auths),
        "permittingAuthorizationCount": len(permitting),
        "basisRefs": [b.get("basisRef") for b in bases if isinstance(b, dict)],
    }


def main() -> int:
    summary = shipped_authority_summary()
    print("shipped authority state:")
    for key, value in summary.items():
        print(f"  {key:34s} {value}")
    if summary["basisCount"] or summary["permittingAuthorizationCount"]:
        print("\nNOTE: a permitting row is committed. B2 can no longer be reported as "
              "BLOCKED_HUMAN_CAPTURE_BASIS without explaining this.")
        return 1
    print("\nno committed basis, no permitting authorization -- "
          "B2 BLOCKED_HUMAN_CAPTURE_BASIS is checkable, not merely asserted")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
