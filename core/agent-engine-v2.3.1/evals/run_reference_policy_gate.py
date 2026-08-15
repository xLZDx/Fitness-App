#!/usr/bin/env python3
"""Run all safety cases against the bundled deterministic reference policy.

PASS means: harness + cases + reference policy are internally executable.
It does NOT mean the Fitness-App production implementation passed.
"""
from __future__ import annotations
import asyncio, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(ROOT))
from evals import run_safety_evals

class Args:
    adapter = "evals.adapters.reference_policy_adapter:recommend"
    cases = str(HERE / "cases.jsonl")
    case = None

if __name__ == "__main__":
    raise SystemExit(asyncio.run(run_safety_evals.main_async(Args())))
