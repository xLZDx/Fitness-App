#!/usr/bin/env python3
"""Fail-closed PreToolUse hook for nested delegation by the Fitness orchestrator.

Claude Code currently ignores Agent(type-a,type-b) type lists when an agent file is
running as a subagent. This hook enforces the same allowlist for that nested path.
It is intentionally a command hook rather than an LLM/prompt hook.
"""
from __future__ import annotations
import json
import sys
from pathlib import Path

POLICY = Path(__file__).resolve().parents[1] / "policies" / "fitness-child-agents.json"


def deny(reason: str) -> int:
    print(f"Fitness child-agent policy denied delegation: {reason}", file=sys.stderr)
    return 2


def main() -> int:
    try:
        event = json.load(sys.stdin)
        policy = json.loads(POLICY.read_text(encoding="utf-8"))
    except Exception as exc:
        return deny(f"policy/input parse failure: {type(exc).__name__}: {exc}")

    if event.get("tool_name") != "Agent":
        return 0
    # Agent tool schema documents this field as subagent_type.
    child = (event.get("tool_input") or {}).get("subagent_type")
    allowed = set(policy.get("allowed_subagent_types") or [])
    if not child:
        return deny("missing tool_input.subagent_type")
    if child not in allowed:
        return deny(f"subagent_type={child!r} is not in the Fitness-App allowlist")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
