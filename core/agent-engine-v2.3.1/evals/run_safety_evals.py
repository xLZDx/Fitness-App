#!/usr/bin/env python3
"""Adapter-based safety/recommendation behavior gate.

A REAL app release claim requires an adapter that invokes the Fitness-App implementation.
The bundled reference adapter is only a harness/policy self-test.

Adapter contract:
    def recommend(case_input: dict) -> dict

Run:
    python3 evals/run_safety_evals.py --adapter mymodule:recommend

Reference harness/policy gate:
    python3 evals/run_reference_policy_gate.py

Exit code 0 only when every selected case passes.
"""
from __future__ import annotations
import argparse, asyncio, importlib, inspect, json, re, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
# Allow bundled adapters to be addressed as evals.adapters.<name>:recommend from direct CLI runs.
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))


def load_adapter(spec: str):
    module_name, func_name = spec.split(":", 1)
    mod = importlib.import_module(module_name)
    return getattr(mod, func_name)


def flatten_text(value) -> str:
    if isinstance(value, dict):
        return "\n".join(f"{k}: {flatten_text(v)}" for k, v in value.items())
    if isinstance(value, list):
        return "\n".join(flatten_text(v) for v in value)
    return "" if value is None else str(value)


def flags_of(result: dict) -> set[str]:
    flags = result.get("flags", [])
    out = set()
    for f in flags:
        if isinstance(f, str): out.add(f)
        elif isinstance(f, dict) and "code" in f: out.add(str(f["code"]))
    return out


def check(case: dict, result: dict) -> list[str]:
    e = case.get("expect", {})
    errors = []
    flags = flags_of(result)
    text = flatten_text(result)

    if "status_in" in e and result.get("status") not in e["status_in"]:
        errors.append(f"status={result.get('status')!r} not in {e['status_in']}")
    if "safety_state_in" in e and result.get("safety_state") not in e["safety_state_in"]:
        errors.append(f"safety_state={result.get('safety_state')!r} not in {e['safety_state_in']}")
    for f in e.get("flags_all", []):
        if f not in flags: errors.append(f"missing flag {f}")
    if e.get("flags_any") and not flags.intersection(e["flags_any"]):
        errors.append(f"needs any flag from {e['flags_any']}")
    for f in e.get("flags_none", []):
        if f in flags: errors.append(f"forbidden flag {f}")
    for pat in e.get("forbidden_text_patterns", []):
        if re.search(pat, text, re.I | re.S): errors.append(f"forbidden text pattern matched: {pat}")
    required = e.get("required_text_patterns_any", [])
    if required and not any(re.search(p, text, re.I | re.S) for p in required):
        errors.append(f"none of required text patterns matched: {required}")
    rec = result.get("recommendation")
    if e.get("require_empty_recommendation") and rec not in (None, [], ""):
        errors.append("recommendation must be empty")
    if e.get("require_nonempty_recommendation") and rec in (None, [], ""):
        errors.append("recommendation must be non-empty")
    return errors


async def call_adapter(fn, payload):
    value = fn(payload)
    if inspect.isawaitable(value):
        value = await value
    if not isinstance(value, dict):
        raise TypeError(f"adapter must return dict, got {type(value).__name__}")
    return value


async def main_async(args) -> int:
    cases = [json.loads(line) for line in Path(args.cases).read_text().splitlines() if line.strip()]
    if args.case:
        wanted = set(args.case)
        cases = [c for c in cases if c["id"] in wanted]
    fn = load_adapter(args.adapter)
    failures = 0
    for c in cases:
        try:
            result = await call_adapter(fn, c["input"])
            errors = check(c, result)
        except Exception as exc:
            errors = [f"adapter exception: {type(exc).__name__}: {exc}"]
        if errors:
            failures += 1
            print(f"FAIL {c['id']}")
            for err in errors: print(f"  - {err}")
        else:
            print(f"PASS {c['id']}")
    print(f"\nRESULT: {len(cases)-failures}/{len(cases)} passed")
    return 1 if failures else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--adapter", required=True, help="Python callable as module:function")
    ap.add_argument("--cases", default=str(HERE / "cases.jsonl"))
    ap.add_argument("--case", action="append", help="Run only case ID; may be repeated")
    args = ap.parse_args()
    raise SystemExit(asyncio.run(main_async(args)))

if __name__ == "__main__":
    main()
