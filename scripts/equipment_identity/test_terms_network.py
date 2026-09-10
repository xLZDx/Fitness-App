# -*- coding: utf-8 -*-
"""B1 steps 12 and 13 tests for scripts/equipment_identity/terms_network.py.

    python -m pytest scripts/equipment_identity/test_terms_network.py -q

Four required fixtures, per the plan:
  1. permitted same-host redirect            -> ACCEPTED           (real sockets)
  2. unexpected same-host final target       -> REFUSED            (real sockets)
  3. off-site intermediate hop returning on-site -> REFUSED, and the
     FORBIDDEN target's own server asserts it received ZERO requests
                                              (real sockets, two origins)
  4. HTTPS-to-HTTP downgrade                 -> REFUSED            (injected fetch_hop --
     see the module's own docstring for why a real TLS listener would test the
     transport rather than the guard)

Every network fixture points at 127.0.0.1. No fixture may pass by matching a
URL string against "/" or "homepage".
"""
from __future__ import annotations

import datetime as dt
import http.server
import sys
import threading
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import terms_network as net  # noqa: E402

SOURCE = "life_fitness_hammer_strength_product_catalog"
DOC = "terms_of_use"
CLOCK = lambda: dt.datetime(2026, 9, 10, 14, 22, 33, tzinfo=dt.timezone.utc)  # noqa: E731

HTML = (
    b"<!doctype html><html><body>"
    b"<h2>Use of the Site and Standards of Conduct</h2>"
    b"<p>unauthorised robot spider scraper</p>"
    b"</body></html>"
)


# ==========================================================================
# Real local HTTP servers. Two independent instances = two independent
# origins, exactly the property `terms_authority.normalize_origin` keys on.
# ==========================================================================

class _CountingHandler(http.server.BaseHTTPRequestHandler):
    """Serves scripted responses and counts every request it receives."""

    routes: dict[str, tuple[int, dict[str, str], bytes]] = {}
    request_count = 0
    _lock = threading.Lock()

    def do_GET(self):  # noqa: N802 -- stdlib method name
        with self._lock:
            type(self).request_count += 1
        status, headers, body = self.routes.get(self.path, (404, {}, b"not found"))
        self.send_response(status)
        for key, value in headers.items():
            self.send_header(key, value)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):  # pragma: no cover -- silence stderr noise
        pass


def _make_server(routes: dict[str, tuple[int, dict[str, str], bytes]]):
    handler = type(f"Handler{id(routes)}", (_CountingHandler,), {
        "routes": routes, "request_count": 0, "_lock": threading.Lock(),
    })
    server = http.server.HTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, handler


@pytest.fixture
def two_origins():
    """Two real local servers: ON (authorized) and OFF (never authorized)."""
    on_server, on_handler = _make_server({})
    off_server, off_handler = _make_server({})
    try:
        yield {
            "on": (on_server, on_handler, on_server.server_address[1]),
            "off": (off_server, off_handler, off_server.server_address[1]),
        }
    finally:
        on_server.shutdown()
        off_server.shutdown()


@pytest.fixture
def namespace(tmp_path, monkeypatch):
    import capture_terms as ct
    root = tmp_path / "captures"
    root.mkdir()
    monkeypatch.setattr(ct, "CAPTURES_ROOT", root)
    return root


def source_registry() -> dict:
    return {"sources": [{"sourceId": SOURCE}, {"sourceId": "wger_project"}]}


def manifest(allowed_final_urls: list[str]) -> dict:
    return {
        "manifestKind": "TERMS_CANDIDATE_DOCUMENTS",
        "sources": [{
            "sourceId": SOURCE,
            "candidates": [{
                "candidateDocId": DOC,
                "documentUrls": allowed_final_urls[:1],
                "allowedFinalUrls": allowed_final_urls,
                "declaredMediaTypes": ["text/html"],
                "observationState": "OBSERVED",
                "observedAtUtc": "2026-09-10T00:00:00Z",
                "observationMethod": "WEB_FETCH_MARKDOWN_EXTRACTION",
                "identityExpectations": {
                    "requiredMarkers": ["Use of the Site and Standards of Conduct"],
                },
            }],
            "noCandidatesReason": None,
        }],
    }


def acq_basis(**overrides) -> dict:
    base = {
        "basisRef": "acq-basis",
        "capabilities": ["ACQUISITION"],
        "scope": {
            "sourceIds": [SOURCE], "candidateDocIds": [DOC],
            "acquisitionMethods": [net.AUTOMATED_FETCH],
        },
    }
    base.update(overrides)
    return base


def ret_basis(**overrides) -> dict:
    base = {
        "basisRef": "ret-basis",
        "capabilities": ["RETENTION"],
        "scope": {
            "sourceIds": [SOURCE], "candidateDocIds": [DOC],
            "acquisitionMethods": [net.AUTOMATED_FETCH],
        },
    }
    base.update(overrides)
    return base


def bases(*records) -> dict:
    return {"bases": list(records) if records else [acq_basis(), ret_basis()]}


def authorization_for(port: int, candidate_doc_id: str | None = None, **overrides) -> dict:
    base = {
        "scheme": "http", "host": "127.0.0.1", "port": port,
        "candidateDocId": candidate_doc_id,
        "state": "AUTO_FETCH_PERMITTED_BY_BASIS",
        "basisRef": "acq-basis",
    }
    base.update(overrides)
    return base


def auth_registry(*records) -> dict:
    return {"authorizations": list(records)}


def call(*, requested_url, manifest_doc, auth_registry_doc, **overrides):
    args = dict(
        source_id=SOURCE,
        candidate_doc_id=DOC,
        requested_url=requested_url,
        acquisition_basis_ref="acq-basis",
        retention_basis_ref="ret-basis",
        clock=CLOCK,
        manifest=manifest_doc,
        basis_registry=bases(),
        authorization_registry=auth_registry_doc,
        source_registry=source_registry(),
    )
    args.update(overrides)
    return net.register_from_network(**args)


# ==========================================================================
# Fixture 1 -- permitted same-host redirect -> ACCEPTED.
# ==========================================================================

def test_fixture_1_a_permitted_same_host_redirect_is_accepted(two_origins, namespace):
    _, handler, port = two_origins["on"]
    start_url = f"http://127.0.0.1:{port}/start"
    terms_url = f"http://127.0.0.1:{port}/terms"
    handler.routes = {
        "/start": (302, {"Location": terms_url}, b""),
        "/terms": (200, {}, HTML),
    }

    target = call(
        requested_url=start_url,
        manifest_doc=manifest([terms_url]),
        auth_registry_doc=auth_registry(authorization_for(port)),
    )

    assert (target / "document.html").read_bytes() == HTML
    assert (target / "provenance.json").is_file()
    assert handler.request_count == 2, "start, then terms -- exactly the two real hops"


# ==========================================================================
# Fixture 2 -- unexpected same-host final target -> REFUSED.
# ==========================================================================

def test_fixture_2_an_unexpected_same_host_final_target_is_refused(two_origins, namespace):
    """Same origin, same authorization -- refused by allowedFinalUrls, a DIFFERENT guard."""
    _, handler, port = two_origins["on"]
    start_url = f"http://127.0.0.1:{port}/start"
    other_url = f"http://127.0.0.1:{port}/other"
    terms_url = f"http://127.0.0.1:{port}/terms"
    handler.routes = {
        "/start": (302, {"Location": other_url}, b""),
        "/other": (200, {}, HTML),
    }

    with pytest.raises(net.CaptureError, match="not in the manifest's allowedFinalUrls"):
        call(
            requested_url=start_url,
            manifest_doc=manifest([terms_url]),  # /other is NOT in this set
            auth_registry_doc=auth_registry(authorization_for(port)),
        )
    assert list(namespace.iterdir()) == []


# ==========================================================================
# Fixture 3 -- off-site intermediate hop returning on-site -> REFUSED,
# and the forbidden target receives ZERO requests.
# ==========================================================================

def test_fixture_3_an_off_site_hop_is_refused_before_any_connection_to_it(
    two_origins, namespace
):
    on_server, on_handler, on_port = two_origins["on"]
    off_server, off_handler, off_port = two_origins["off"]

    on_url = f"http://127.0.0.1:{on_port}/start"
    off_url = f"http://127.0.0.1:{off_port}/detour"
    back_on_url = f"http://127.0.0.1:{on_port}/terms"

    on_handler.routes = {"/start": (302, {"Location": off_url}, b"")}
    # "returning on-site": if the off-site hop were ever reached, it would
    # redirect right back. It must never be reached.
    off_handler.routes = {"/detour": (302, {"Location": back_on_url}, b"")}

    with pytest.raises(net.AuthorityError, match="no authorization for origin"):
        call(
            requested_url=on_url,
            manifest_doc=manifest([back_on_url]),
            # Only the ON origin is authorized. The OFF origin has no entry.
            auth_registry_doc=auth_registry(authorization_for(on_port)),
        )

    assert off_handler.request_count == 0, (
        "the forbidden target must receive ZERO requests -- a caller that eventually "
        "refuses is not the same guarantee as a caller that never connected"
    )
    assert on_handler.request_count == 1, "only the authorized first hop was ever contacted"
    assert list(namespace.iterdir()) == []


def test_fixture_3_control_the_off_site_server_DOES_receive_a_request_if_authorized(
    two_origins, namespace
):
    """The counter itself is proven live: authorize BOTH origins and watch it move.

    Without this, a bug that always reports request_count==0 (e.g. a broken
    counter) would make the refusal fixture above pass for the wrong reason.
    """
    on_server, on_handler, on_port = two_origins["on"]
    off_server, off_handler, off_port = two_origins["off"]

    on_url = f"http://127.0.0.1:{on_port}/start"
    off_url = f"http://127.0.0.1:{off_port}/detour"

    on_handler.routes = {"/start": (302, {"Location": off_url}, b"")}
    off_handler.routes = {"/detour": (200, {}, HTML)}

    target = call(
        requested_url=on_url,
        manifest_doc=manifest([off_url]),
        auth_registry_doc=auth_registry(
            authorization_for(on_port), authorization_for(off_port)
        ),
    )
    assert off_handler.request_count == 1
    assert (target / "document.html").read_bytes() == HTML


# ==========================================================================
# Fixture 4 -- HTTPS-to-HTTP downgrade -> REFUSED.
# ==========================================================================

def test_fixture_4_an_https_to_http_downgrade_is_refused_before_connecting(namespace):
    """Injected fetch_hop -- see the module docstring for why.

    hop 1 is answered without ever calling the real transport for hop 2: the
    downgrade guard runs on the parsed Location string alone, before hop 2's
    origin is even authorization-checked, let alone connected to.
    """
    calls: list[str] = []

    def fake_fetch_hop(url: str) -> net.HopResult:
        calls.append(url)
        if url == "https://127.0.0.1:9443/start":
            return net.HopResult(status=302, location="http://127.0.0.1:9080/terms", body=b"")
        raise AssertionError(f"fetch_hop must never be called for {url!r}")

    with pytest.raises(net.CaptureError, match="downgrades https to http"):
        call(
            requested_url="https://127.0.0.1:9443/start",
            manifest_doc=manifest(["http://127.0.0.1:9080/terms"]),
            auth_registry_doc=auth_registry(
                authorization_for(9443, scheme="https"),
                authorization_for(9080),
            ),
            fetch_hop=fake_fetch_hop,
        )
    assert calls == ["https://127.0.0.1:9443/start"], (
        "hop 2 must never be fetched -- the downgrade check runs before it would be"
    )
    assert list(namespace.iterdir()) == []


def test_the_downgrade_predicate_in_isolation():
    """The pure comparison, tested directly, independent of the orchestration loop."""
    net._refuse_downgrade("https://h/a", "https://h/b")  # same scheme: fine
    net._refuse_downgrade("http://h/a", "http://h/b")     # same scheme: fine
    net._refuse_downgrade("http://h/a", "https://h/b")    # UPGRADE: fine
    with pytest.raises(net.CaptureError, match="downgrades"):
        net._refuse_downgrade("https://h/a", "http://h/b")


# ==========================================================================
# Supporting guards.
# ==========================================================================

def test_a_non_2xx_non_redirect_status_is_refused(two_origins, namespace):
    _, handler, port = two_origins["on"]
    url = f"http://127.0.0.1:{port}/missing"
    handler.routes = {}  # 404 for anything unlisted
    with pytest.raises(net.CaptureError, match="neither a success nor a followable redirect"):
        call(
            requested_url=url,
            manifest_doc=manifest([url]),
            auth_registry_doc=auth_registry(authorization_for(port)),
        )
    assert list(namespace.iterdir()) == []


def test_a_redirect_loop_refuses_on_the_hop_bound_rather_than_running(two_origins, namespace):
    _, handler, port = two_origins["on"]
    a = f"http://127.0.0.1:{port}/a"
    b = f"http://127.0.0.1:{port}/b"
    handler.routes = {
        "/a": (302, {"Location": b}, b""),
        "/b": (302, {"Location": a}, b""),
    }
    with pytest.raises(net.CaptureError, match="exceeded"):
        call(
            requested_url=a,
            manifest_doc=manifest([a, b]),
            auth_registry_doc=auth_registry(authorization_for(port)),
        )
    assert list(namespace.iterdir()) == []


def test_an_over_long_chain_refuses_on_the_hop_bound(two_origins, namespace):
    _, handler, port = two_origins["on"]
    routes = {}
    for i in range(net.MAX_REDIRECT_HOPS + 3):
        routes[f"/{i}"] = (302, {"Location": f"http://127.0.0.1:{port}/{i + 1}"}, b"")
    routes[f"/{net.MAX_REDIRECT_HOPS + 3}"] = (200, {}, HTML)
    handler.routes = routes
    with pytest.raises(net.CaptureError, match="exceeded"):
        call(
            requested_url=f"http://127.0.0.1:{port}/0",
            manifest_doc=manifest([f"http://127.0.0.1:{port}/{net.MAX_REDIRECT_HOPS + 3}"]),
            auth_registry_doc=auth_registry(authorization_for(port)),
        )
    assert list(namespace.iterdir()) == []


def test_a_zero_byte_final_response_is_refused(two_origins, namespace):
    _, handler, port = two_origins["on"]
    url = f"http://127.0.0.1:{port}/empty"
    handler.routes = {"/empty": (200, {}, b"")}
    with pytest.raises(net.CaptureError, match="empty"):
        call(
            requested_url=url,
            manifest_doc=manifest([url]),
            auth_registry_doc=auth_registry(authorization_for(port)),
        )
    assert list(namespace.iterdir()) == []


def test_bytes_of_an_undeclared_type_are_refused(two_origins, namespace):
    _, handler, port = two_origins["on"]
    url = f"http://127.0.0.1:{port}/pdf"
    handler.routes = {"/pdf": (200, {}, b"%PDF-1.4 not really html")}
    with pytest.raises(net.CaptureError, match="does not declare"):
        call(
            requested_url=url,
            manifest_doc=manifest([url]),
            auth_registry_doc=auth_registry(authorization_for(port)),
        )
    assert list(namespace.iterdir()) == []


def test_wrong_bytes_at_a_permitted_url_are_refused_by_identity_expectations(
    two_origins, namespace
):
    """The network-path twin of F3's own fixture on the manual path."""
    _, handler, port = two_origins["on"]
    url = f"http://127.0.0.1:{port}/terms"
    handler.routes = {"/terms": (200, {}, b"<!doctype html><html>unrelated content</html>")}
    with pytest.raises(net.CaptureError, match="do not carry"):
        call(
            requested_url=url,
            manifest_doc=manifest([url]),
            auth_registry_doc=auth_registry(authorization_for(port)),
        )
    assert list(namespace.iterdir()) == []


def test_an_unauthorized_starting_origin_is_refused_before_any_request(two_origins, namespace):
    _, handler, port = two_origins["on"]
    url = f"http://127.0.0.1:{port}/terms"
    handler.routes = {"/terms": (200, {}, HTML)}
    with pytest.raises(net.AuthorityError, match="no authorization"):
        call(
            requested_url=url,
            manifest_doc=manifest([url]),
            auth_registry_doc=auth_registry(),  # empty: nothing authorized
        )
    assert handler.request_count == 0, "the very first hop must not be contacted unauthorized"
    assert list(namespace.iterdir()) == []


def test_a_retention_only_basis_used_for_retention_still_requires_acquisition_to_resolve_too(
    two_origins, namespace
):
    """Both capabilities are checked, not just the one whose absence is being tested."""
    _, handler, port = two_origins["on"]
    url = f"http://127.0.0.1:{port}/terms"
    handler.routes = {"/terms": (200, {}, HTML)}
    with pytest.raises(net.AuthorityError, match="resolves to nothing"):
        call(
            requested_url=url,
            manifest_doc=manifest([url]),
            auth_registry_doc=auth_registry(authorization_for(port)),
            retention_basis_ref="nonexistent-ref",
        )
    assert list(namespace.iterdir()) == []


def test_a_not_observed_candidate_is_refused_on_the_network_path_too(namespace):
    doc = manifest(["http://127.0.0.1:1/terms"])
    doc["sources"][0]["candidates"][0]["observationState"] = "NOT_OBSERVED"
    del doc["sources"][0]["candidates"][0]["identityExpectations"]
    del doc["sources"][0]["candidates"][0]["observedAtUtc"]
    del doc["sources"][0]["candidates"][0]["observationMethod"]
    with pytest.raises(net.CaptureError, match="NOT_OBSERVED"):
        call(
            requested_url="http://127.0.0.1:1/terms",
            manifest_doc=doc,
            auth_registry_doc=auth_registry(),
        )
