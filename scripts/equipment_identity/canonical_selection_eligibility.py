# -*- coding: utf-8 -*-
"""Pre-P1.G5 direct-corroboration eligibility pass (GPT-PM spec, 2026-08-22).

    python -m pytest scripts/equipment_identity/test_canonical_selection_eligibility.py -q
    python scripts/equipment_identity/canonical_selection_eligibility.py   # regenerates the artifact

Purpose: NOT a new gate -- GPT-PM's own framing after accepting P1.G4 as
CLOSED was "pre-G5 evidence remediation/corroboration pass under the
already-issued GO." Computes, per real candidate in the P1.G2/G3 combined
pool (`core/equipment_identity/p1/candidates/p0_brand_candidates.json`,
74 real candidates across 7 brands), whether it is eligible for canonical-50
pilot SELECTION in the future P1.G5 gate -- never assigns `primaryTypeId`/
`modelId` and never resolves a conflict itself; both stay P1.G5
reconciliation's own job, exactly as GPT-PM's scope boundary requires.

## The exact GPT-PM precondition this enforces (carried forward from the
## two prior DECISION_LOG entries, not re-litigated here)

Before P1.G5 pilot selection may start: each of Technogym/Matrix/Panatta
must independently reach >=4 directly-corroborated (DIRECT_FETCH-class)
official models, AND the total directly-corroborated pool across all
brands must reach >=50. SEARCH_INDEX_SNIPPET evidence alone can never
satisfy either floor -- it may exist as supplementary provenance but is
never retroactively reclassified as DIRECT_FETCH.

## Two-factor eligibility (`canonicalSelectionEligible`), not one

A candidate needs BOTH factors true to be marked eligible:

1. **Its own evidence is direct** -- either its *original* P1.G2/G3 adapter
   provenance already carries `retrievalMethod: DIRECT_FETCH` (true for
   every Life Fitness/Hammer Strength/Nautilus/Precor candidate -- 36 of
   them), OR this pass found independent, additional direct corroboration
   for it (see `matrix_johnsonfit_pdf_corroboration.json` -- 4 Matrix
   candidates: G7-S70, G7-S13, G7-S33, G3-S70, corroborated against a real,
   downloaded, pypdf-parsed Matrix Fitness/Johnson Health Tech PDF, the
   same method P1.G3 used for Precor's spec-table PDF).
2. **The overall pool clears both floors** -- per-brand >=4 for Technogym/
   Matrix/Panatta AND total direct pool >=50, computed fresh from the real
   data every time this runs, never hardcoded.

This is deliberately fail-closed: even a candidate with genuinely real,
independently-verified direct corroboration is NOT marked eligible while
the pool-level preconditions remain unmet -- a well-corroborated Matrix
candidate does not unlock canonical selection on its own if Technogym and
Panatta still have zero directly-corroborated models between them. This
matches GPT-PM's own test scenario list almost verbatim: "direct official
corroboration -> may become true, ASSUMING remaining G5 conditions pass."

## What this pass found (2026-08-22) -- and what it honestly could not find

**Matrix: floor MET (4/4).** `us.matrixfitness.com`'s product pages return
HTTP 200 but only an empty client-side-JS-rendered shell (already
documented in the P0 registry's `matrix_fitness_product_catalog` entry) --
but `content.johnsonfit.com` (Matrix Fitness is a brand of Johnson Health
Tech Co.) is a genuinely reachable, first-party document CDN. This pass
downloaded a real 187-page G7 Strength Service Manual PDF (48,735,275
bytes, sha256 recorded in the fixture) and a real G3-S70 sell-sheet PDF
(339,451 bytes) and parsed both with `pypdf`, extracting real printed
technical-specification tables for 4 candidates already in the pool.

**Technogym: floor NOT MET (0/4) after genuine, repeated attempts.**
`www.technogym.com` returns a blanket HTTP 403 from CloudFront across
every path tested in this pass: the main site root, `en-US`/`en-INT`
product pages (the same page multiple search results pointed at, complete
with the real model code `MNAP` in the URL), and TWO separate PDF paths
(`marketing-support/services/DirectFileDownload.php` and
`media/pdf-catalogues/...`). `corporate.technogym.com` (investor
relations) IS reachable but carries no product specification content.
Third-party dealer mirrors of Technogym-authored documents were found
(`innovativefit.com`, `keystonefitness.ca`) but deliberately NOT counted --
GPT-PM's own contract requires a "directly-retrieved FIRST-PARTY document",
and a dealer's re-hosted copy is not first-party retrieval even when the
underlying content originates from the manufacturer.

**Panatta: floor NOT MET (0/4) after genuine, repeated attempts.**
`panattasport.com` returns a blanket HTTP 403 on every path (already
documented in P1.G3; reconfirmed in this pass). `panattafitness.com` (a
plausible alternate first-party domain, by analogy with Matrix's
`johnsonfit.com`) redirects to a dead page (404) rather than real content.

**Total direct pool: 40 (was 36, +4 from Matrix), still short of 50.**

## The honest, correct conclusion (GPT-PM's own stated fallback)

Per GPT-PM's own explicit instruction: "If after a genuine search for
official sources, the pool or any brand's floor cannot be met, the correct
state is P1.G5 BLOCKED_ON_SOURCE_EVIDENCE -- never a lowered provenance
threshold just to reach the number 50." Both the Technogym/Panatta
per-brand floors and the total-pool floor remain unmet after this pass's
genuine attempts. `overall_preconditions_met()` therefore returns `False`,
and EVERY candidate's `canonicalSelectionEligible` is `False` today --
including Matrix's 4 newly-corroborated ones and the 36 pre-existing direct
candidates. This is the artifact computing and recording
BLOCKED_ON_SOURCE_EVIDENCE as data, not a separate narrative claim layered
on top of a more permissive number.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[2]
P1_CANDIDATES_DIR = REPO / "core" / "equipment_identity" / "p1" / "candidates"
COMBINED_POOL_PATH = P1_CANDIDATES_DIR / "p0_brand_candidates.json"
DIRECT_CORROBORATION_DIR = REPO / "core" / "equipment_identity" / "p1" / "direct_corroboration"
MATRIX_PDF_CORROBORATION_PATH = DIRECT_CORROBORATION_DIR / "matrix_johnsonfit_pdf_corroboration.json"
ELIGIBILITY_ARTIFACT_PATH = P1_CANDIDATES_DIR / "canonical_selection_eligibility.json"

sys.path.insert(0, str(Path(__file__).resolve().parent))
import canonical_json  # noqa: E402
import rights  # noqa: E402

#: The three brands GPT-PM's precondition names explicitly. Every other
#: brand in the pool (Life Fitness, Hammer Strength, Nautilus, Precor) was
#: already 100% DIRECT_FETCH as of P1.G2/G3 and carries no per-brand floor
#: of its own here.
BRAND_FLOOR_MINIMUM = 4
BRANDS_WITH_A_FLOOR: tuple[str, ...] = ("technogym", "matrix", "panatta")
TOTAL_POOL_MINIMUM = 50


class EligibilityError(RuntimeError):
    """Real pool/fixture data that cannot support the eligibility claims
    this module would compute from it."""


def _load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def load_combined_pool() -> list[dict[str, Any]]:
    return _load_json(COMBINED_POOL_PATH)["candidates"]


def _assert_registered_official_manufacturer_source(source_id: str) -> None:
    """Mechanically enforces first-party status against the real, tracked
    `source_registry.json` -- reviewer-found gap (GPT-PM devil's-advocate
    review, 2026-08-22): a corroboration fixture previously only ASSERTED
    first-party status in prose (a note field), with nothing actually
    checking that against the same registry every P1.G2/G3 adapter source
    is required to go through (`registry_check.ts`'s
    `assertRegisteredOfficialManufacturerSource` on the TypeScript side).
    Mirrors that check here on the Python side, reusing `rights.py`'s own
    `load_registry()` rather than re-reading/re-validating the registry a
    second way."""
    registry = rights.load_registry()
    matches = [r for r in registry if r["sourceId"] == source_id]
    if not matches:
        raise EligibilityError(
            f"sourceId={source_id!r} is not a registered source in "
            "core/equipment_identity/p0/source_registry.json -- a corroboration source must be "
            "registered before it can back any candidate's eligibility"
        )
    source_class = matches[0]["sourceClass"]
    if source_class != "OFFICIAL_MANUFACTURER":
        raise EligibilityError(
            f"sourceId={source_id!r} is registered but as sourceClass={source_class!r}, not "
            "OFFICIAL_MANUFACTURER -- only an official-manufacturer-class source may back "
            "DIRECT_FETCH corroboration for canonical selection"
        )


def load_matrix_pdf_corroboration() -> dict[tuple[str, str | None], dict[str, Any]]:
    """Keyed by (brandId, modelCode) -> the corroboration record, so lookup
    against a candidate is a single dict access, not a linear scan.

    A fixture entry with a falsy/None modelCode is refused outright (never
    silently accepted as a wildcard key) -- reviewer-found gap (silent-
    failure-hunter, 2026-08-22): a real candidate that itself has no
    modelCode would build the identical (brandId, None) lookup key, and a
    None-keyed fixture entry would then silently misattribute its PDF
    corroboration to every such candidate rather than to the one real model
    it was actually captured for.

    The fixture's own top-level `sourceId` must be a real, registered
    OFFICIAL_MANUFACTURER-class source (see
    `_assert_registered_official_manufacturer_source`) -- checked once,
    covering every entry in the fixture, since they all share one source."""
    raw = _load_json(MATRIX_PDF_CORROBORATION_PATH)
    _assert_registered_official_manufacturer_source(raw["sourceId"])
    by_key: dict[tuple[str, str | None], dict[str, Any]] = {}
    for entry in raw["corroborations"]:
        if not entry.get("modelCode"):
            raise EligibilityError(
                f"corroboration fixture entry for brandId={entry.get('brandId')!r} has no "
                "modelCode -- every entry must name the one real model it corroborates"
            )
        key = (entry["brandId"], entry["modelCode"])
        if key in by_key:
            raise EligibilityError(f"duplicate corroboration entry for {key}")
        by_key[key] = {**entry, "fixtureSourceId": raw["sourceId"]}
    return by_key


def _original_direct_fetch_provenance(candidate: dict[str, Any]) -> dict[str, Any] | None:
    """The candidate's own original adapter-generated DIRECT_FETCH provenance
    record, or None if it has none. Refuses (rather than silently picking
    the first) if a candidate somehow carries more than one DIRECT_FETCH
    record -- reviewer-found gap (python-reviewer, 2026-08-22): no real
    candidate has ever had more than one provenance entry, but a future
    re-fetch pass appending a second, possibly-conflicting record must not
    be silently resolved by picking whichever happens to come first."""
    direct = [p for p in candidate.get("provenance", []) if p.get("retrievalMethod") == "DIRECT_FETCH"]
    if len(direct) > 1:
        raise EligibilityError(
            f"candidateId={candidate.get('candidateId')!r} carries {len(direct)} DIRECT_FETCH "
            "provenance records -- this function has no policy for choosing between them and "
            "must not silently pick the first"
        )
    return direct[0] if direct else None


def direct_corroboration_for(
    candidate: dict[str, Any], matrix_pdf_corroboration: dict[tuple[str, str | None], dict[str, Any]]
) -> dict[str, Any] | None:
    """The real evidence backing this candidate's eligibility, or None if it
    has no direct-corroboration evidence at all yet (SEARCH_INDEX_SNIPPET-only).
    Never fabricates a value -- returns exactly what the real provenance
    array or the real PDF-corroboration fixture actually contains."""
    original = _original_direct_fetch_provenance(candidate)
    if original is not None:
        return {
            "sourceId": original["sourceId"],
            "sourceUrl": original["sourceUrl"],
            "retrievalMethod": original["retrievalMethod"],
            "evidenceType": "ORIGINAL_ADAPTER_PROVENANCE",
            "sourceContentSha256": original.get("fixtureSha256"),
            "locator": None,
        }
    key = (candidate["brandId"], candidate.get("modelCode"))
    extra = matrix_pdf_corroboration.get(key)
    if extra is not None:
        return {
            # The fixture's own stable top-level sourceId -- NOT the
            # per-entry sourceUrl. Reviewer-found bug (GPT-PM devil's-
            # advocate review, 2026-08-22): this previously reused
            # extra["sourceUrl"] as sourceId, which meant sourceId was not
            # actually a stable identifier (it moved whenever a URL did)
            # and could never be told apart from sourceUrl by a downstream
            # consumer trying to join against the source registry.
            "sourceId": extra["fixtureSourceId"],
            "sourceUrl": extra["sourceUrl"],
            "retrievalMethod": "DIRECT_FETCH",
            "evidenceType": "PRE_G5_CORROBORATION_PASS_PDF",
            "sourceContentSha256": extra["documentSha256"],
            "locator": extra["locator"],
        }
    return None


def direct_corroboration_counts_by_brand(
    candidates: list[dict[str, Any]], matrix_pdf_corroboration: dict[tuple[str, str | None], dict[str, Any]]
) -> dict[str, int]:
    """Counts DISTINCT (brandId, modelCode) model keys with real direct
    corroboration, never raw candidate rows -- reviewer-found gap (GPT-PM
    devil's-advocate review, 2026-08-22): the precondition is specified in
    directly-corroborated MODELS; counting candidate rows instead would let
    a future duplicate candidate (two rows describing the same real model,
    e.g. from a later ingestion pass that doesn't dedupe against this pool)
    silently inflate a brand's floor or the total past 50 without a
    corresponding increase in genuinely distinct corroborated models.
    Raises loudly rather than silently double-counting if that ever
    happens -- today's real pool has zero such duplicates (verified: 74
    candidates, 74 distinct (brandId, modelCode) pairs)."""
    seen_keys: dict[tuple[str, str | None], str] = {}
    counts: dict[str, int] = {}
    for c in candidates:
        if direct_corroboration_for(c, matrix_pdf_corroboration) is None:
            continue
        key = (c["brandId"], c.get("modelCode"))
        if key in seen_keys:
            raise EligibilityError(
                f"duplicate (brandId, modelCode) {key} across candidateId={seen_keys[key]!r} and "
                f"candidateId={c['candidateId']!r} -- the direct-corroboration floor counts "
                "distinct models, not candidate rows, and cannot silently double-count one model"
            )
        seen_keys[key] = c["candidateId"]
        counts[c["brandId"]] = counts.get(c["brandId"], 0) + 1
    return counts


def overall_preconditions_met(counts_by_brand: dict[str, int]) -> tuple[bool, list[str]]:
    """Returns (met, reasons) -- reasons is always populated when not met,
    so the aggregate report can state exactly which floor failed and by how
    much, never just a bare False."""
    reasons = []
    for brand in BRANDS_WITH_A_FLOOR:
        count = counts_by_brand.get(brand, 0)
        if count < BRAND_FLOOR_MINIMUM:
            reasons.append(f"{brand} direct count {count} < {BRAND_FLOOR_MINIMUM}")
    total = sum(counts_by_brand.values())
    if total < TOTAL_POOL_MINIMUM:
        reasons.append(f"total direct pool {total} < {TOTAL_POOL_MINIMUM}")
    return (len(reasons) == 0, reasons)


def _assert_every_fixture_entry_matched_a_real_candidate(
    candidates: list[dict[str, Any]], matrix_pdf_corroboration: dict[tuple[str, str | None], dict[str, Any]]
) -> None:
    """Reviewer-found gap (silent-failure-hunter, 2026-08-22): a typo'd
    modelCode in the hand-captured PDF-corroboration fixture (or the pool's
    real modelCode changing upstream) previously failed silently -- the
    mismatched entry just never matched anything, the brand's direct count
    quietly dropped below what was actually captured, and nothing surfaced
    which fixture entry was orphaned. This turns that into a loud, named
    failure instead."""
    real_keys = {(c["brandId"], c.get("modelCode")) for c in candidates}
    unmatched = [key for key in matrix_pdf_corroboration if key not in real_keys]
    if unmatched:
        raise EligibilityError(
            f"matrix_johnsonfit_pdf_corroboration.json has {len(unmatched)} entry/entries that "
            f"match no real candidate in the combined pool: {unmatched} -- a typo'd modelCode or "
            "a candidate that no longer exists must be fixed, not silently dropped"
        )


def build_eligibility_artifact() -> dict[str, Any]:
    candidates = load_combined_pool()
    matrix_pdf_corroboration = load_matrix_pdf_corroboration()
    _assert_every_fixture_entry_matched_a_real_candidate(candidates, matrix_pdf_corroboration)
    counts_by_brand = direct_corroboration_counts_by_brand(candidates, matrix_pdf_corroboration)
    preconditions_met, precondition_failure_reasons = overall_preconditions_met(counts_by_brand)

    entries = []
    for c in candidates:
        corroboration = direct_corroboration_for(c, matrix_pdf_corroboration)
        has_direct = corroboration is not None
        eligible = has_direct and preconditions_met
        rejection_reasons: list[str] = []
        if not has_direct:
            rejection_reasons.append("NO_DIRECT_FETCH_CORROBORATION")
        if has_direct and not preconditions_met:
            rejection_reasons.extend(f"POOL_PRECONDITION_NOT_MET: {r}" for r in precondition_failure_reasons)
        entries.append(
            {
                "candidateId": c["candidateId"],
                "brandId": c["brandId"],
                "modelCode": c.get("modelCode"),
                "canonicalSelectionEligible": eligible,
                "directCorroboration": corroboration,
                "rejectionReasons": rejection_reasons,
            }
        )

    return {
        "gate": "PRE_P1.G5_CORROBORATION_PASS",
        "assignsPrimaryTypeIdOrModelId": False,
        "resolvesConflicts": False,
        "directCorroborationCountsByBrand": counts_by_brand,
        "totalDirectCorroboratedCount": sum(counts_by_brand.values()),
        "brandFloorMinimum": BRAND_FLOOR_MINIMUM,
        "brandsWithAFloor": list(BRANDS_WITH_A_FLOOR),
        "totalPoolMinimum": TOTAL_POOL_MINIMUM,
        "overallPreconditionsMet": preconditions_met,
        "precondition_failure_reasons": precondition_failure_reasons,
        "p1G5Status": "READY" if preconditions_met else "BLOCKED_ON_SOURCE_EVIDENCE",
        "entries": entries,
    }


def main() -> int:
    artifact = build_eligibility_artifact()
    ELIGIBILITY_ARTIFACT_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = ELIGIBILITY_ARTIFACT_PATH.with_suffix(f"{ELIGIBILITY_ARTIFACT_PATH.suffix}.{os.getpid()}.tmp")
    tmp.write_text(canonical_json.dump_pretty(artifact), encoding="utf-8")
    tmp.replace(ELIGIBILITY_ARTIFACT_PATH)
    print(f"wrote {ELIGIBILITY_ARTIFACT_PATH.relative_to(REPO)}")
    print(f"p1G5Status: {artifact['p1G5Status']}")
    print(f"directCorroborationCountsByBrand: {artifact['directCorroborationCountsByBrand']}")
    print(f"totalDirectCorroboratedCount: {artifact['totalDirectCorroboratedCount']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
