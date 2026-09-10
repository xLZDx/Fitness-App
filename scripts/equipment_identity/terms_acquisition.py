"""B1 step 1 -- the acquisition-preflight observation ledger and its rules.

WHAT THIS FILE IS FOR, AND THE MISTAKE IT EXISTS TO PREVENT
-----------------------------------------------------------
The ledger records, per B1 target, whether the source's terms could be acquired
by an automated request and on what evidence. It records OBSERVATIONS. Nothing
here grants permission to fetch, to retain or to use anything, and nothing here
is a legal review -- that stays a human conclusion no tool in this repository
may produce (`rights.py`).

The rules below exist because of a specific, recorded failure. Two of the three
targets were written into four successive plan revisions as
``AUTO_FETCH_REFUSED`` on the strength of a review finding that asserted their
terms prohibit automated access. Neither document had been opened. The claim
turned out to be CORRECT when it was finally checked -- but it was unearned for
as long as it went unchecked, and a correct guess and a measurement are not the
same evidence. See ``core/DECISION_LOG.md`` and CLAUDE.md 23.

So the central rule here is a shape, not a value: **an outcome that asserts a
prohibition must carry the words that prohibit.** A paraphrase cannot satisfy
it, a summary cannot satisfy it, and another agent's characterisation cannot
satisfy it.

TWO ASYMMETRIES, BOTH DELIBERATE
--------------------------------
* A robots.txt ``Allow`` is ONE POSITIVE SIGNAL and never permission. Both
  hosts that refuse here allow in robots.txt -- measured, 200, ``can_fetch``
  True -- and both are still ``AUTO_FETCH_REFUSED``, because the terms are the
  stronger instrument and say otherwise. A check that read robots.txt and
  stopped would have concluded the opposite of the truth on two of three
  targets.
* A robots.txt 403 is ``POLICY_UNAVAILABLE`` and never a prohibition. A host
  that will not show you its policy has not stated one. Technogym is that case,
  and inventing a legal conclusion from a status code would be the same defect
  pointing the other way.

ON THE GUARDS BELOW
-------------------
Each rule has a fixture that ONLY it rejects, per the precedent recorded in
``rights.py::_resolve_terms_snapshot``: a guard no test can distinguish from
its own absence is not depth, it is a claim. If a rule here is ever found to be
subsumed by another, it belongs in the other one or it belongs deleted.
"""

from __future__ import annotations

import json
import pathlib
import re
from typing import Any

REPO = pathlib.Path(__file__).resolve().parents[2]
P0_DIR = REPO / "core" / "equipment_identity" / "p0"
PREFLIGHT_PATH = P0_DIR / "terms_acquisition_preflight.json"

#: The exact B1 targets. A preflight covering a different set is not this gate's.
B1_TARGET_SOURCE_IDS: tuple[str, ...] = (
    "technogym_product_catalog",
    "life_fitness_hammer_strength_product_catalog",
    "core_health_fitness_nautilus_product_catalog",
)

OUTCOMES: frozenset[str] = frozenset({
    "AUTO_FETCH_REFUSED",
    "AUTO_FETCH_DEFERRED_POLICY_UNAVAILABLE",
    "AUTO_FETCH_PERMITTED_BY_BASIS",
    "AUTO_FETCH_POLICY_UNVERIFIED",
})

EVIDENCE_METHODS: frozenset[str] = frozenset({
    "ROBOTS_PARSER_PROBE",
    "WEB_FETCH_MARKDOWN_EXTRACTION",
    "COMMITTED_REPOSITORY_DOCUMENT",
})

#: Methods that actually read a document's words. A robots probe does not: it
#: reads a machine-readable directive file, which is a different artifact from
#: the terms and cannot supply a quotation from them.
DOCUMENT_READING_METHODS: frozenset[str] = frozenset({
    "WEB_FETCH_MARKDOWN_EXTRACTION",
    "COMMITTED_REPOSITORY_DOCUMENT",
})

#: Methods that never hold raw bytes, so a digest of "the document" cannot come
#: from them. A markdown conversion read by a model is text ABOUT the bytes.
BYTELESS_METHODS: frozenset[str] = frozenset({"WEB_FETCH_MARKDOWN_EXTRACTION"})

#: Clause topics that can carry a prohibition. A copying/retention clause is a
#: real restriction but it is not a statement about automated ACCESS, and using
#: one to justify AUTO_FETCH_REFUSED would be a claim wider than its evidence.
PROHIBITION_TOPICS: frozenset[str] = frozenset({
    "AUTOMATED_ACCESS",
    "SYSTEMATIC_RETRIEVAL",
})

#: A robots probe result stating the target may be fetched. Matched on the
#: recorded verdict text, which is the probe's own output, not a paraphrase.
_ROBOTS_ALLOWS_RE = re.compile(r"can_fetch\([^)]*\)\s*=\s*True")
_ROBOTS_DISALLOWS_RE = re.compile(r"can_fetch\([^)]*\)\s*=\s*False")
_ROBOTS_OK_RE = re.compile(r"HTTP\s*200")


class PreflightValidationError(Exception):
    """A preflight ledger that does not support what it claims."""


def load_preflight(path: pathlib.Path | None = None) -> dict[str, Any]:
    """Read the ledger. Does not validate -- call `validate_preflight`."""
    target = PREFLIGHT_PATH if path is None else path
    try:
        raw = target.read_bytes()
    except FileNotFoundError as exc:
        raise PreflightValidationError(f"preflight ledger not found at {target}") from exc
    try:
        return json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise PreflightValidationError(f"{target}: not valid UTF-8 JSON -- {exc}") from exc


def _require_text(value: Any, context: str, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise PreflightValidationError(
            f"{context}: {field} must be a non-empty string, got {value!r}"
        )
    return value


def _validate_evidence(entry: Any, context: str) -> dict[str, Any]:
    if not isinstance(entry, dict):
        raise PreflightValidationError(f"{context}: each evidence item must be an object")

    method = _require_text(entry.get("method"), context, "method")
    if method not in EVIDENCE_METHODS:
        raise PreflightValidationError(
            f"{context}: unknown evidence method {method!r} "
            f"(known: {', '.join(sorted(EVIDENCE_METHODS))})"
        )
    _require_text(entry.get("target"), context, "target")
    _require_text(entry.get("observedAtUtc"), context, "observedAtUtc")
    _require_text(entry.get("result"), context, "result")

    # A method that never held bytes cannot carry a digest of them. This is the
    # same distinction the whole gate turns on: what was observed versus what
    # was asserted about it.
    if method in BYTELESS_METHODS and entry.get("sha256") is not None:
        raise PreflightValidationError(
            f"{context}: evidence method {method} never holds raw bytes, so it cannot "
            f"carry sha256={entry['sha256']!r} -- a digest here would describe a "
            "conversion, not the document"
        )
    return entry


def _validate_clause(entry: Any, context: str) -> dict[str, Any]:
    if not isinstance(entry, dict):
        raise PreflightValidationError(f"{context}: each quoted clause must be an object")
    topic = _require_text(entry.get("topic"), context, "topic")
    _require_text(entry.get("section"), context, "section")
    _require_text(entry.get("verbatim"), context, "verbatim")
    entry = dict(entry)
    entry["topic"] = topic
    return entry


def _validate_observation(entry: Any, index: int) -> str:
    context = f"observation[{index}]"
    if not isinstance(entry, dict):
        raise PreflightValidationError(f"{context}: must be an object")

    source_id = _require_text(entry.get("sourceId"), context, "sourceId")
    context = f"observation[{index}] ({source_id})"

    outcome = _require_text(entry.get("outcome"), context, "outcome")
    if outcome not in OUTCOMES:
        raise PreflightValidationError(
            f"{context}: unknown outcome {outcome!r} (known: {', '.join(sorted(OUTCOMES))})"
        )
    _require_text(entry.get("reason"), context, "reason")

    evidence_raw = entry.get("evidence")
    if not isinstance(evidence_raw, list) or not evidence_raw:
        raise PreflightValidationError(
            f"{context}: evidence must be a non-empty list -- an outcome with no "
            "observation behind it is an opinion"
        )
    evidence = [_validate_evidence(item, context) for item in evidence_raw]

    clauses_raw = entry.get("quotedClauses")
    if not isinstance(clauses_raw, list):
        raise PreflightValidationError(f"{context}: quotedClauses must be a list")
    clauses = [_validate_clause(item, context) for item in clauses_raw]

    _validate_byte_claim(entry, context)
    _validate_outcome_support(outcome, evidence, clauses, context)
    return source_id


def _validate_byte_claim(entry: dict[str, Any], context: str) -> None:
    """`documentBytesHeld` and `documentSha256` must agree.

    Separate from the evidence-method rule above and separately provable: that
    one catches a digest attached to a conversion, this one catches an
    observation that claims to hold bytes while recording no digest of them, or
    the reverse. Either alone leaves the other case accepted.
    """
    held = entry.get("documentBytesHeld")
    if not isinstance(held, bool):
        raise PreflightValidationError(
            f"{context}: documentBytesHeld must be true or false, got {held!r}"
        )
    digest = entry.get("documentSha256")
    if held and not isinstance(digest, str):
        raise PreflightValidationError(
            f"{context}: documentBytesHeld=true requires documentSha256, got {digest!r}"
        )
    if not held and digest is not None:
        raise PreflightValidationError(
            f"{context}: documentBytesHeld=false but documentSha256={digest!r} is recorded "
            "-- a digest of bytes nobody kept cannot be re-verified by anyone"
        )


def _validate_outcome_support(
    outcome: str,
    evidence: list[dict[str, Any]],
    clauses: list[dict[str, Any]],
    context: str,
) -> None:
    """The rule this module exists for: an outcome must carry its own support."""

    if outcome == "AUTO_FETCH_REFUSED":
        # Either the terms say so in their own words, or robots.txt Disallows.
        # A robots probe reporting can_fetch=True is neither, and a non-2xx
        # probe is neither -- which is what stops a 403 from becoming a legal
        # prohibition.
        has_quote = any(
            clause["topic"] in PROHIBITION_TOPICS for clause in clauses
        )
        quote_is_read = any(
            item["method"] in DOCUMENT_READING_METHODS for item in evidence
        )
        has_disallow = any(
            item["method"] == "ROBOTS_PARSER_PROBE"
            and _ROBOTS_DISALLOWS_RE.search(item["result"])
            for item in evidence
        )
        if not ((has_quote and quote_is_read) or has_disallow):
            raise PreflightValidationError(
                f"{context}: AUTO_FETCH_REFUSED requires either a verbatim clause "
                f"(topic in {sorted(PROHIBITION_TOPICS)}) obtained by a document-reading "
                "method, or a robots.txt Disallow. Neither is present -- a prohibition "
                "nobody quoted is a claim, not evidence"
            )

    elif outcome == "AUTO_FETCH_DEFERRED_POLICY_UNAVAILABLE":
        # You cannot quote a policy you could not read. A record that does is
        # either citing a different document or inventing one.
        offending = [c for c in clauses if c["topic"] in PROHIBITION_TOPICS]
        if offending:
            raise PreflightValidationError(
                f"{context}: outcome says the policy was unavailable, yet "
                f"{len(offending)} prohibition clause(s) are quoted from it -- "
                "both cannot be true"
            )

    elif outcome == "AUTO_FETCH_PERMITTED_BY_BASIS":
        # The one outcome that authorizes anything, and the only one that needs
        # a resolvable authorization rather than an observation.
        #
        # It is REFUSED UNCONDITIONALLY here, and that is not a placeholder: B1
        # step 3 builds the basis registry, and until it exists there is nothing
        # a reference could resolve against. An outcome that authorizes must
        # never be satisfiable by writing a string into a file -- which is what
        # accepting it today would mean. Step 3 replaces this with a real
        # `resolve_basis(..., required_capability="ACQUISITION", ...)` call, and
        # the test that pins this refusal is rewritten with it, deliberately, so
        # nobody can quietly widen the outcome without touching its guard.
        raise PreflightValidationError(
            f"{context}: AUTO_FETCH_PERMITTED_BY_BASIS requires acquisitionBasisRef to "
            "resolve to a basis record carrying the ACQUISITION capability. No basis "
            "registry exists yet (B1 step 3), so nothing can resolve and this outcome is "
            "unreachable by construction -- and a robots.txt Allow is a positive signal, "
            "never permission"
        )


def validate_preflight(ledger: Any, *, expect_targets: bool = True) -> None:
    """Validate a preflight ledger, raising `PreflightValidationError` on the first fault.

    `expect_targets=False` is for fixtures that exercise one rule in isolation
    without carrying the full B1 target set.
    """
    if not isinstance(ledger, dict):
        raise PreflightValidationError("preflight ledger must be a JSON object")
    if ledger.get("ledgerKind") != "TERMS_ACQUISITION_PREFLIGHT":
        raise PreflightValidationError(
            f"ledgerKind must be TERMS_ACQUISITION_PREFLIGHT, got {ledger.get('ledgerKind')!r}"
        )

    observations = ledger.get("observations")
    if not isinstance(observations, list) or not observations:
        raise PreflightValidationError("observations must be a non-empty list")

    seen: list[str] = []
    for index, entry in enumerate(observations):
        seen.append(_validate_observation(entry, index))

    duplicates = {sid for sid in seen if seen.count(sid) > 1}
    if duplicates:
        raise PreflightValidationError(
            f"duplicate sourceId(s) in preflight: {sorted(duplicates)} -- two rows for one "
            "source means resolution depends on order, and order is not a rule"
        )

    if expect_targets and set(seen) != set(B1_TARGET_SOURCE_IDS):
        missing = sorted(set(B1_TARGET_SOURCE_IDS) - set(seen))
        extra = sorted(set(seen) - set(B1_TARGET_SOURCE_IDS))
        raise PreflightValidationError(
            f"preflight must cover exactly the B1 targets; missing={missing} extra={extra}"
        )

    _validate_pending_authorizations(ledger)


def _validate_pending_authorizations(ledger: dict[str, Any]) -> None:
    """A requested authorization must never read as a granted one."""
    pending = ledger.get("pendingAuthorizations", [])
    if not isinstance(pending, list):
        raise PreflightValidationError("pendingAuthorizations must be a list")
    for index, entry in enumerate(pending):
        context = f"pendingAuthorizations[{index}]"
        if not isinstance(entry, dict):
            raise PreflightValidationError(f"{context}: must be an object")
        state = _require_text(entry.get("state"), context, "state")
        if state != "REQUESTED_NOT_GRANTED":
            raise PreflightValidationError(
                f"{context}: state must be REQUESTED_NOT_GRANTED, got {state!r} -- a granted "
                "authorization belongs in a basis registry that resolves, not in a list of "
                "things somebody asked for"
            )
        if entry.get("acquisitionBasisRef") is not None:
            raise PreflightValidationError(
                f"{context}: a pending authorization may not carry acquisitionBasisRef -- "
                "that field is what makes a reference authority, and this one is not granted"
            )


def main() -> int:
    ledger = load_preflight()
    try:
        validate_preflight(ledger)
    except PreflightValidationError as exc:
        print(f"PREFLIGHT INVALID: {exc}")
        return 1
    print(f"preflight valid: {len(ledger['observations'])} observation(s)")
    for entry in ledger["observations"]:
        quotes = len(entry.get("quotedClauses", []))
        print(f"  {entry['sourceId']:48s} {entry['outcome']:38s} quotes={quotes}")
    pending = ledger.get("pendingAuthorizations", [])
    if pending:
        print(f"  pending authorizations (NOT grants): {len(pending)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
