# -*- coding: utf-8 -*-
"""B1 steps 3, 4, 5 and 6 tests for scripts/equipment_identity/terms_authority.py.

    python -m pytest scripts/equipment_identity/test_terms_authority.py -q

Every permitting record below is INJECTED as a parameter. None of them exists in
a committed file, and `test_no_permitting_record_appears_in_any_committed_file`
proves that by reading the repository rather than by intent.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import terms_authority as auth  # noqa: E402

TARGET = "life_fitness_hammer_strength_product_catalog"
DOC = "terms_of_use"


# --------------------------------------------------------------------------
# Injected fixtures. Test seam only -- see the module docstring.
# --------------------------------------------------------------------------

def basis(**overrides) -> dict:
    base = {
        "basisRef": "test-basis-001",
        "capabilities": ["ACQUISITION"],
        "scope": {
            "sourceIds": [TARGET],
            "candidateDocIds": [DOC],
            "acquisitionMethods": ["AUTOMATED_FETCH"],
        },
    }
    base.update(overrides)
    return base


def basis_registry(*records) -> dict:
    return {"registryKind": "TERMS_ACQUISITION_BASES", "bases": list(records) or [basis()]}


def authorization(**overrides) -> dict:
    base = {
        "scheme": "https",
        "host": "127.0.0.1",
        "port": 8443,
        "candidateDocId": None,
        "state": "AUTO_FETCH_PERMITTED_BY_BASIS",
        "basisRef": "test-basis-001",
    }
    base.update(overrides)
    return base


def auth_registry(*records) -> dict:
    return {
        "registryKind": "TERMS_ACQUISITION_AUTHORIZATIONS",
        "authorizations": list(records) or [authorization()],
    }


def resolve(ref="test-basis-001", capability="ACQUISITION", source=TARGET,
            doc=DOC, method="AUTOMATED_FETCH", registry=None):
    return auth.resolve_basis(
        ref, capability, source, doc, method,
        registry=basis_registry() if registry is None else registry,
    )


# ==========================================================================
# STEP 3 -- a basis carries a capability and a scope, or it authorises nothing.
# ==========================================================================

def test_a_matching_basis_resolves():
    assert resolve()["basisRef"] == "test-basis-001"


def test_a_reference_naming_no_record_resolves_to_nothing():
    with pytest.raises(auth.AuthorityError, match="resolves to nothing"):
        resolve(ref="whatever-i-typed")


def test_an_acquisition_basis_does_not_authorise_retention():
    """The headline of step 3.

    Obtaining a document and having the right to keep a copy are different
    questions. An earlier revision required only that a reference resolve, which
    made this pass.
    """
    with pytest.raises(auth.AuthorityError, match="neither implies the other"):
        resolve(capability="RETENTION")


def test_a_retention_basis_does_not_authorise_acquisition():
    """The same rule in the other direction, so it is a rule and not a special case."""
    registry = basis_registry(basis(capabilities=["RETENTION"]))
    with pytest.raises(auth.AuthorityError, match="neither implies the other"):
        resolve(capability="ACQUISITION", registry=registry)


def test_a_basis_carrying_both_capabilities_authorises_both():
    registry = basis_registry(basis(capabilities=["ACQUISITION", "RETENTION"]))
    assert resolve(capability="ACQUISITION", registry=registry)
    assert resolve(capability="RETENTION", registry=registry)


def test_a_basis_scoped_to_another_source_does_not_cover_this_one():
    registry = basis_registry(basis(scope={
        "sourceIds": ["core_health_fitness_nautilus_product_catalog"],
        "candidateDocIds": [DOC],
        "acquisitionMethods": ["AUTOMATED_FETCH"],
    }))
    with pytest.raises(auth.AuthorityError, match="scope.sourceIds does not cover"):
        resolve(registry=registry)


def test_a_basis_scoped_to_another_candidate_does_not_cover_this_one():
    registry = basis_registry(basis(scope={
        "sourceIds": [TARGET],
        "candidateDocIds": ["legal_terms_conditions"],
        "acquisitionMethods": ["AUTOMATED_FETCH"],
    }))
    with pytest.raises(auth.AuthorityError, match="scope.candidateDocIds does not cover"):
        resolve(registry=registry)


def test_a_basis_scoped_to_manual_retrieval_does_not_cover_an_automated_fetch():
    registry = basis_registry(basis(scope={
        "sourceIds": [TARGET],
        "candidateDocIds": [DOC],
        "acquisitionMethods": ["HUMAN_MANUAL_RETRIEVAL"],
    }))
    with pytest.raises(auth.AuthorityError, match="scope.acquisitionMethods does not cover"):
        resolve(registry=registry)


@pytest.mark.parametrize("field", ["sourceIds", "candidateDocIds", "acquisitionMethods"])
def test_an_absent_scope_dimension_is_refused_rather_than_read_as_everything(field):
    scope = dict(basis()["scope"])
    del scope[field]
    with pytest.raises(auth.AuthorityError, match="never deliberately granted"):
        resolve(registry=basis_registry(basis(scope=scope)))


def test_two_records_sharing_a_reference_refuse_rather_than_pick_one():
    registry = basis_registry(basis(), basis(capabilities=["RETENTION"]))
    with pytest.raises(auth.AuthorityError, match="order is not a rule"):
        resolve(registry=registry)


def test_an_unknown_capability_is_refused():
    with pytest.raises(auth.AuthorityError, match="unknown capability"):
        resolve(capability="EVERYTHING")


def test_an_unknown_acquisition_method_is_refused():
    with pytest.raises(auth.AuthorityError, match="unknown acquisition method"):
        resolve(method="VIBES")


def test_an_empty_reference_is_refused():
    for value in ("", "   ", None, 7):
        with pytest.raises(auth.AuthorityError, match="basisRef must be"):
            resolve(ref=value)


# ==========================================================================
# STEP 4 -- origin normalization and authorization.
# ==========================================================================

def test_the_default_port_is_filled_in_from_the_scheme():
    assert auth.normalize_origin("https://h/x") == ("https", "h", 443)
    assert auth.normalize_origin("https://h:443/x") == ("https", "h", 443)
    assert auth.normalize_origin("http://h/x") == ("http", "h", 80)


def test_the_host_and_scheme_are_lowercased_and_an_explicit_port_is_kept():
    assert auth.normalize_origin("HTTPS://EXAMPLE.TEST:8443/x") == ("https", "example.test", 8443)


def test_an_unspoken_scheme_is_refused():
    for url in ("ftp://h/x", "file:///etc/passwd", "gopher://h"):
        with pytest.raises(auth.AuthorityError, match="not one this tool speaks"):
            auth.normalize_origin(url)


def test_a_url_with_no_host_is_refused():
    with pytest.raises(auth.AuthorityError, match="no host"):
        auth.normalize_origin("https:///x")


def test_an_unusable_port_is_reported_rather_than_crashing():
    with pytest.raises(auth.AuthorityError, match="unusable port"):
        auth.normalize_origin("https://h:notaport/x")


def test_a_matching_authorization_resolves():
    entry = auth.resolve_authorization(
        "https://127.0.0.1:8443/terms", TARGET, DOC, "AUTOMATED_FETCH",
        registry=auth_registry(), basis_registry=basis_registry(),
    )
    assert entry["state"] == "AUTO_FETCH_PERMITTED_BY_BASIS"


def test_an_alternate_port_does_not_inherit_its_siblings_authorization():
    """The reason the key carries a port.

    A key of (scheme, host) alone would let an authorization for the ordinary
    site cover an unrelated service on another port of the same machine.
    """
    with pytest.raises(auth.AuthorityError, match="no authorization for origin"):
        auth.resolve_authorization(
            "https://127.0.0.1:9999/terms", TARGET, DOC, "AUTOMATED_FETCH",
            registry=auth_registry(), basis_registry=basis_registry(),
        )


def test_the_default_port_and_the_explicit_default_port_are_one_origin():
    registry = auth_registry(authorization(port=443))
    for url in ("https://127.0.0.1/terms", "https://127.0.0.1:443/terms"):
        assert auth.resolve_authorization(
            url, TARGET, DOC, "AUTOMATED_FETCH",
            registry=registry, basis_registry=basis_registry(),
        )


def test_an_unauthorized_origin_refuses():
    with pytest.raises(auth.AuthorityError, match="no authorization for origin"):
        auth.resolve_authorization(
            "https://www.lifefitness.com/en-us/terms-of-use", TARGET, DOC, "AUTOMATED_FETCH",
            registry=auth_registry(), basis_registry=basis_registry(),
        )


def test_an_entry_in_a_non_permitting_state_refuses():
    registry = auth_registry(authorization(state="AUTO_FETCH_REFUSED"))
    with pytest.raises(auth.AuthorityError, match="not AUTO_FETCH_PERMITTED_BY_BASIS"):
        auth.resolve_authorization(
            "https://127.0.0.1:8443/terms", TARGET, DOC, "AUTOMATED_FETCH",
            registry=registry, basis_registry=basis_registry(),
        )


def test_an_authorization_whose_basis_does_not_resolve_refuses():
    """An authorization is only as good as the basis it points at."""
    registry = auth_registry(authorization(basisRef="nonexistent"))
    with pytest.raises(auth.AuthorityError, match="resolves to nothing"):
        auth.resolve_authorization(
            "https://127.0.0.1:8443/terms", TARGET, DOC, "AUTOMATED_FETCH",
            registry=registry, basis_registry=basis_registry(),
        )


def test_an_authorization_backed_by_a_retention_only_basis_refuses():
    """Separately provable from the test above: the basis EXISTS, it is the wrong kind."""
    registry = auth_registry()
    bases = basis_registry(basis(capabilities=["RETENTION"]))
    with pytest.raises(auth.AuthorityError, match="neither implies the other"):
        auth.resolve_authorization(
            "https://127.0.0.1:8443/terms", TARGET, DOC, "AUTOMATED_FETCH",
            registry=registry, basis_registry=bases,
        )


def test_two_overlapping_authorizations_refuse_rather_than_resolve_by_precedence():
    registry = auth_registry(authorization(), authorization(state="AUTO_FETCH_REFUSED"))
    with pytest.raises(auth.AuthorityError, match="rather than resolve by precedence"):
        auth.resolve_authorization(
            "https://127.0.0.1:8443/terms", TARGET, DOC, "AUTOMATED_FETCH",
            registry=registry, basis_registry=basis_registry(),
        )


def test_an_entry_narrowed_to_another_candidate_does_not_match():
    registry = auth_registry(authorization(candidateDocId="legal_terms_conditions"))
    with pytest.raises(auth.AuthorityError, match="no authorization for origin"):
        auth.resolve_authorization(
            "https://127.0.0.1:8443/terms", TARGET, DOC, "AUTOMATED_FETCH",
            registry=registry, basis_registry=basis_registry(),
        )


def test_an_entry_with_an_unusable_key_is_reported_rather_than_skipped():
    """A malformed row must not silently become 'no match'.

    Skipping it would turn a broken registry into a quiet refusal, which reads
    the same as a correct one and hides the fault.
    """
    registry = auth_registry({"scheme": "https", "host": "127.0.0.1", "state": "x"})
    with pytest.raises(auth.AuthorityError, match="no usable"):
        auth.resolve_authorization(
            "https://127.0.0.1:8443/terms", TARGET, DOC, "AUTOMATED_FETCH",
            registry=registry, basis_registry=basis_registry(),
        )


# ==========================================================================
# STEP 6 -- sourceId resolution.
# ==========================================================================

def test_each_b1_target_resolves_to_its_stored_string():
    for target in auth.B1_TARGET_SOURCE_IDS:
        assert auth.resolve_source_id(target) == target


def test_a_trailing_newline_is_a_different_string():
    """`rights.py::_SOURCE_ID_RE` ends in `$`, which accepts this. Nothing here does."""
    with pytest.raises(auth.AuthorityError, match="matches no record"):
        auth.resolve_source_id("technogym_product_catalog\n")


def test_a_nonexistent_source_is_refused():
    with pytest.raises(auth.AuthorityError, match="matches no record"):
        auth.resolve_source_id("acme_fitness_catalog")


def test_a_real_but_non_target_source_is_refused():
    """wger_project is a genuine registry record. It is not this gate's business."""
    with pytest.raises(auth.AuthorityError, match="not a B1 target"):
        auth.resolve_source_id("wger_project")


def test_a_case_variant_is_a_different_string():
    with pytest.raises(auth.AuthorityError, match="matches no record"):
        auth.resolve_source_id("Technogym_Product_Catalog")


def test_a_non_string_source_id_is_refused():
    for value in (None, 3, ["technogym_product_catalog"]):
        with pytest.raises(auth.AuthorityError, match="must be a string"):
            auth.resolve_source_id(value)


# ==========================================================================
# STEP 5 -- what the SHIPPED registries actually contain.
# ==========================================================================

def test_the_committed_basis_registry_is_empty():
    assert auth.load_bases()["bases"] == []


def test_the_committed_authorization_registry_is_empty():
    assert auth.load_authorizations()["authorizations"] == []


def test_no_committed_authority_exists_for_any_b1_target():
    """The claim B2 rests on, checked rather than asserted.

    A resolver that is perfectly correct still authorises exactly what B1 calls
    human-blocked if a permitting row is committed by accident.
    """
    summary = auth.shipped_authority_summary()
    assert summary["basisCount"] == 0
    assert summary["permittingAuthorizationCount"] == 0

    for target in auth.B1_TARGET_SOURCE_IDS:
        for capability in sorted(auth.CAPABILITIES):
            for method in sorted(auth.ACQUISITION_METHODS):
                with pytest.raises(auth.AuthorityError):
                    auth.resolve_basis("any-ref", capability, target, "terms_of_use", method)


def test_no_permitting_record_appears_in_any_committed_file():
    """Grepped from the repository, not asserted by intent.

    Every permitting fixture in this suite is injected as a parameter. If one
    ever leaks into a committed ledger, this catches it.
    """
    for path in (auth.BASES_PATH, auth.AUTHORIZATIONS_PATH):
        doc = json.loads(path.read_bytes().decode("utf-8"))
        blob = json.dumps(doc)
        assert "test-basis-001" not in blob, f"{path.name} carries a test fixture"
        rows = doc.get("bases", doc.get("authorizations", []))
        assert rows == [], f"{path.name} is not empty"


def test_the_registries_are_pure_lf():
    for path in (auth.BASES_PATH, auth.AUTHORIZATIONS_PATH):
        assert path.read_bytes().count(b"\r\n") == 0


def test_a_missing_registry_is_reported_rather_than_crashing(tmp_path):
    with pytest.raises(auth.AuthorityError, match="not found"):
        auth.load_bases(tmp_path / "absent.json")


def test_a_malformed_registry_is_reported_rather_than_crashing(tmp_path):
    broken = tmp_path / "broken.json"
    broken.write_bytes(b"[]")
    with pytest.raises(auth.AuthorityError, match="must be a JSON object"):
        auth.load_bases(broken)
