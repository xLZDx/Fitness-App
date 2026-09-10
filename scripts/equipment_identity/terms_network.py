"""B1 steps 12 and 13 -- no request is made that authorization has not already covered.

THE DEFECT THIS MODULE EXISTS TO CLOSE
---------------------------------------
An ordinary HTTP client follows a redirect before its history can be inspected.
So validating a redirect chain AFTER the fact gives the right verdict about a
request that has already happened: an authorized host redirecting to a
forbidden one means the forbidden host already received the request by the
time the chain is correctly refused. The verdict is right and the guarantee is
already broken -- the check is not narrower than its claim, it is LATER than
its claim.

Corrected here by disabling automatic redirect following entirely.
`default_fetch_hop` performs exactly ONE HTTP request and returns whatever it
got, redirect or not. The orchestration loop in `register_from_network` parses
every `Location` itself, refuses an HTTPS-to-HTTP downgrade, and resolves
authorization for the NEXT normalized origin -- all before opening a
connection to it. Only then does it fetch that hop.

WHY `fetch_hop` IS A PARAMETER
-------------------------------
Same seam discipline as the clock and the registries elsewhere in this gate:
`default_fetch_hop` is the real implementation, and tests may inject another
one. The one place this matters for TESTING is the HTTPS-downgrade fixture,
where standing up a self-signed TLS listener would test the transport layer
rather than the guard -- and the guard is a comparison of two URL strings,
checked before any connection to the second one is attempted. An injected
`fetch_hop` exercises the full orchestration loop (including that comparison)
without needing real TLS to prove it. The other three required fixtures use
REAL local HTTP servers and the REAL `default_fetch_hop`, because they turn on
origin (host:port) and path, which plain sockets already prove.

WHAT IS CHECKED PER HOP VERSUS ONLY AT THE END
------------------------------------------------
* every hop: authorization must cover its normalized origin, checked BEFORE
  the connection; a downgrade from the previous hop's scheme is refused before
  even attempting that.
* only the FINAL hop (a 2xx): its URL must be one of the candidate's
  `allowedFinalUrls`. An authorized origin does not mean every path on it is
  the document B1 registered -- that is a separate, more granular claim, and
  giving it a separate guard is what makes "authorized origin, wrong path"
  (the same-host, unexpected-target fixture) a distinct, provable case from
  "unauthorized origin" (the off-site fixture).
"""

from __future__ import annotations

import http.client
import ssl
from dataclasses import dataclass
from typing import Any, Callable
from urllib.parse import urljoin, urlsplit

import datetime as _dt

from capture_terms import (
    AUTOMATED_FETCH,
    AuthorityError,
    CandidateManifestError,
    CaptureError,
    build_sidecar,
    check_identity_expectations,
    derive_media_type,
    format_capture_id,
    resolve_candidate,
    resolve_source_id,
    stage_and_publish,
    utc_now,
    validate_sidecar,
)
from terms_authority import normalize_origin, resolve_authorization, resolve_basis

MAX_REDIRECT_HOPS = 5
REDIRECT_STATUSES = frozenset({301, 302, 303, 307, 308})
_SPOKEN_SCHEMES = frozenset({"http", "https"})


@dataclass(frozen=True)
class HopResult:
    """One HTTP response, unfollowed. `location` is None unless it was sent."""
    status: int
    location: str | None
    body: bytes


def default_fetch_hop(url: str, timeout: float = 10.0) -> HopResult:
    """Issue exactly ONE request. Never follows a redirect itself."""
    parts = urlsplit(url)
    scheme = parts.scheme.lower()
    if scheme not in _SPOKEN_SCHEMES:
        raise CaptureError(f"{url!r}: scheme {parts.scheme!r} is not one this tool speaks")
    host = parts.hostname
    if not host:
        raise CaptureError(f"{url!r}: no host")

    if scheme == "https":
        conn: http.client.HTTPConnection = http.client.HTTPSConnection(
            host, parts.port or 443, timeout=timeout, context=ssl.create_default_context()
        )
    else:
        conn = http.client.HTTPConnection(host, parts.port or 80, timeout=timeout)

    path_qs = parts.path or "/"
    if parts.query:
        path_qs = f"{path_qs}?{parts.query}"

    try:
        conn.request(
            "GET", path_qs,
            headers={"Host": host, "User-Agent": "SPTR-terms-capture/1"},
        )
        response = conn.getresponse()
        location = response.getheader("Location")
        body = response.read()
        status = response.status
    finally:
        conn.close()
    return HopResult(status=status, location=location, body=body)


def _refuse_downgrade(previous_url: str, next_url: str) -> None:
    """Refuse an HTTPS-to-HTTP transition, checked as a pure string comparison.

    Runs BEFORE any connection to `next_url` is attempted -- deliberately
    stronger than an authorization check, since a downgrade is refused even if
    the next origin happens to be authorized.
    """
    previous_scheme = urlsplit(previous_url).scheme.lower()
    next_scheme = urlsplit(next_url).scheme.lower()
    if previous_scheme == "https" and next_scheme == "http":
        raise CaptureError(
            f"redirect from {previous_url!r} to {next_url!r} downgrades https to http -- "
            "refused before any connection to the downgraded target was attempted"
        )


def register_from_network(
    *,
    source_id: str,
    candidate_doc_id: str,
    requested_url: str,
    acquisition_basis_ref: str,
    retention_basis_ref: str,
    clock: Callable[[], Any] = utc_now,
    manifest: dict[str, Any] | None = None,
    basis_registry: dict[str, Any] | None = None,
    authorization_registry: dict[str, Any] | None = None,
    source_registry: dict[str, Any] | None = None,
    fetch_hop: Callable[[str], HopResult] = default_fetch_hop,
    on_before_publish: Callable[[], None] | None = None,
    max_hops: int = MAX_REDIRECT_HOPS,
):
    """Capture one document over the network. Publishes, or publishes nothing.

    Every hop's origin is authorized BEFORE `fetch_hop` is called for it. A
    redirect is never auto-followed by the transport -- this function decides,
    for every `Location`, whether to continue, and stops before connecting
    when it will not.
    """
    for name, value in (
        ("sourceId", source_id), ("candidateDocId", candidate_doc_id),
        ("requestedUrl", requested_url),
        ("acquisitionBasisRef", acquisition_basis_ref),
        ("retentionBasisRef", retention_basis_ref),
    ):
        if not isinstance(value, str) or not value.strip():
            raise CaptureError(f"register_from_network requires {name}")

    resolved_source = resolve_source_id(source_id, registry=source_registry)
    candidate = resolve_candidate(resolved_source, candidate_doc_id, manifest)
    if candidate["observationState"] != "OBSERVED":
        raise CaptureError(
            f"candidate {candidate_doc_id!r} is NOT_OBSERVED -- the manifest holds no "
            "identity expectations or allowedFinalUrls for it"
        )

    # RETENTION is resolved up front, exactly as on the manual path: a
    # resolvable acquisition path never by itself implies a right to keep what
    # it fetches.
    resolve_basis(
        retention_basis_ref, "RETENTION", resolved_source, candidate_doc_id,
        AUTOMATED_FETCH, registry=basis_registry,
    )

    current_url = requested_url
    chain: list[str] = []
    hop = HopResult(status=0, location=None, body=b"")

    for attempt in range(1, max_hops + 2):
        if attempt > max_hops:
            raise CaptureError(
                f"redirect chain exceeded {max_hops} hops -- refused rather than followed "
                "indefinitely"
            )

        # Order matters: normalize, then authorize, THEN connect. Nothing
        # above this line has opened a socket for this hop.
        normalize_origin(current_url)
        resolve_authorization(
            current_url, resolved_source, candidate_doc_id, AUTOMATED_FETCH,
            registry=authorization_registry, basis_registry=basis_registry,
        )
        hop = fetch_hop(current_url)

        if 200 <= hop.status < 300:
            break

        if hop.status in REDIRECT_STATUSES and hop.location:
            next_url = urljoin(current_url, hop.location)
            _refuse_downgrade(current_url, next_url)
            chain.append(next_url)
            current_url = next_url
            continue

        raise CaptureError(
            f"hop at {current_url!r} returned status {hop.status} -- neither a success nor "
            "a followable redirect"
        )
    else:  # pragma: no cover -- unreachable, loop always breaks or raises
        raise CaptureError("redirect loop terminated without a result")

    final_url = current_url
    if final_url not in candidate["allowedFinalUrls"]:
        raise CaptureError(
            f"final URL {final_url!r} is not in the manifest's allowedFinalUrls for "
            f"{candidate_doc_id!r} -- an authorized origin does not make every path on it "
            "the document this gate registered"
        )

    payload = hop.body
    if not payload:
        raise CaptureError("the final response body is empty -- nothing was captured")

    media_type = derive_media_type(payload)
    if media_type not in candidate["declaredMediaTypes"]:
        raise CaptureError(
            f"the fetched bytes are {media_type}, which {candidate_doc_id!r} does not "
            f"declare (declares: {candidate['declaredMediaTypes']})"
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
        acquisition_method=AUTOMATED_FETCH,
        acquisition_basis_ref=acquisition_basis_ref,
        retention_basis_ref=retention_basis_ref,
        media_type=media_type,
        payload=payload,
        timestamp=timestamp,
        observed={
            "requestedUrlObserved": requested_url,
            "redirectChainObserved": chain,
            "finalUrlObserved": final_url,
        },
    )
    validate_sidecar(sidecar)
    return stage_and_publish(
        resolved_source, candidate_doc_id, capture_id, media_type, payload, sidecar,
        on_before_publish=on_before_publish,
    )


__all__ = [
    "HopResult", "MAX_REDIRECT_HOPS", "REDIRECT_STATUSES",
    "default_fetch_hop", "register_from_network",
    "AuthorityError", "CandidateManifestError", "CaptureError", "AUTOMATED_FETCH",
]
