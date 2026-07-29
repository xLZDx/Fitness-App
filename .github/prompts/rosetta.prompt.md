---
description: Rosetta engineering workflow (Prepare -> Research -> Plan -> Act -> Validate), on-demand. Approval = GO/GO only.
---

# Rosetta workflow (on-demand)

Invoked explicitly; NOT always-on. Vendored + adapted to the operator's governance
(cherry-picked from Grid Dynamics Rosetta, Apache-2.0 — the plugin/hook is deliberately not used).

## Governance (non-negotiable; NEVER outranks the operator's CLAUDE.md / core/CONVENTIONS.md)
- Approval = ONLY literal `GO` / `ГО`. "yes" / "approved" / "looks good" do NOT release a gate.
- Push = a separate `push` GO. Forced articulation + AI-risk stamp before state-changing actions.
- No "SDLC-only / no personal chats" restriction. No priority ladder above the operator.

## Loop
1. Prepare  - classify + tier; read core/CODEMAP.md + core/CONVENTIONS.md (don't re-glob the layout).
2. Research - read the real files/call-sites, cite file:line, no guessing.
3. Plan     - reviewable plan, minimal scope; STOP for `GO` before any state change.
4. Act      - KISS/SOLID/DRY, minimal diff, no scope creep; Riverpod only; data/ stays Flutter-free;
              design for iOS; injury filter is a safety path.
5. Validate - run /fitness-verify (flutter analyze + flutter test + audit_doc_links); full restart
              before re-test; never cite a pass count not produced after the change.

## Review (opt-in)
Route to the operator's agents (flutter-reviewer, dart-build-resolver, security-reviewer,
silent-failure-hunter, ...); use /agent-consensus for architectural plans. Empiricism over poetry.

Full skill (Claude Code, already global): ~/.claude/skills/rosetta.
