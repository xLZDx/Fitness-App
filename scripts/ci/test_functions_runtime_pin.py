# -*- coding: utf-8 -*-
"""Regression guard: Cloud Functions runtime pin (Node.js 22).

    C:\Python314\python.exe -m pytest scripts/ci/test_functions_runtime_pin.py -q

Fails if firebase.json lists a functions codebase whose runtime is not
nodejs22, if a functions package.json engines.node is not "22", or if the
package.json files disagree with each other. The checker functions are also
exercised on synthetic bad inputs so the guard itself is proven able to fail.
"""
from __future__ import annotations

import json
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
EXPECTED_RUNTIME = "nodejs22"
EXPECTED_ENGINE = "22"


def runtime_violations(firebase: dict) -> list[str]:
    fns = firebase.get("functions")
    if isinstance(fns, dict):
        fns = [fns]
    if not fns:
        return ["firebase.json has no functions section"]
    out = []
    for i, entry in enumerate(fns):
        name = entry.get("codebase", f"#{i}")
        if entry.get("runtime") != EXPECTED_RUNTIME:
            out.append(f"codebase {name}: runtime {entry.get('runtime')!r} != {EXPECTED_RUNTIME!r}")
    return out


def engine_violations(packages: dict[str, dict]) -> list[str]:
    out = []
    seen = set()
    for name, pkg in packages.items():
        node = (pkg.get("engines") or {}).get("node")
        seen.add(node)
        if node != EXPECTED_ENGINE:
            out.append(f"{name}: engines.node {node!r} != {EXPECTED_ENGINE!r}")
    if len(seen) > 1:
        out.append(f"package.json files disagree on engines.node: {sorted(map(str, seen))}")
    return out


def _load(rel: str) -> dict:
    return json.loads((ROOT / rel).read_text(encoding="utf-8"))


def _source_dirs(firebase: dict) -> list[str]:
    fns = firebase["functions"]
    if isinstance(fns, dict):
        fns = [fns]
    return [e["source"] for e in fns]


def test_firebase_json_every_functions_codebase_is_nodejs22():
    fb = _load("firebase.json")
    assert len(fb["functions"]) >= 2
    assert runtime_violations(fb) == []


def test_every_functions_package_engines_node_is_22_and_consistent():
    fb = _load("firebase.json")
    sources = _source_dirs(fb)
    assert "functions" in sources and "functions-equipment-identity" in sources
    pkgs = {s: _load(f"{s}/package.json") for s in sources}
    assert engine_violations(pkgs) == []


def test_lockfile_root_engines_match_package_json():
    for s in ("functions", "functions-equipment-identity"):
        lock = _load(f"{s}/package-lock.json")
        assert lock["packages"][""]["engines"]["node"] == EXPECTED_ENGINE, s


@pytest.mark.parametrize(
    "fb",
    [
        {"functions": [{"codebase": "a", "runtime": "nodejs22"}, {"codebase": "b", "runtime": "nodejs20"}]},
        {"functions": [{"codebase": "a"}]},
        {"functions": {"codebase": "a", "runtime": "nodejs24"}},
        {},
    ],
    ids=["one-stale", "missing-runtime", "other-version", "no-section"],
)
def test_runtime_checker_rejects_bad_firebase_json(fb):
    assert runtime_violations(fb)


@pytest.mark.parametrize(
    "pkgs",
    [
        {"a": {"engines": {"node": "22"}}, "b": {"engines": {"node": "20"}}},
        {"a": {"engines": {"node": "20"}}, "b": {"engines": {"node": "20"}}},
        {"a": {"engines": {"node": "22"}}, "b": {}},
        {"a": {"engines": {"node": ">=22"}}, "b": {"engines": {"node": "22"}}},
    ],
    ids=["disagree", "both-stale", "missing-engines", "range-not-exact"],
)
def test_engine_checker_rejects_bad_packages(pkgs):
    assert engine_violations(pkgs)
