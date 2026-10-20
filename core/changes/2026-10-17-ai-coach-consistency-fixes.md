# AI Coach documentation: cross-document consistency fixes

Date: 2026-10-17. Kind: documentation only.

## What changed
Seven contradictions found by a read-only consistency check were fixed: backlog acceptance criterion counts (19 E2E scenarios, 126 P0), design 6.2 recovery independent of the flag and build define, E2E plan and FT-1007 exempting internal timer commands from rollback, ADR count 13 in requirements and UI spec, ADR-009 offline command set, the safetyLock field name in the test plan.

## Why
Last step before the GPT-PM documentation gate.

## Affected contracts and paths
Documents under docs/ai-coach/ only.

## Verification state
Documentation only. Consistency check coverage was partial (FT, ACS and AC-LC numbering and the UI action table versus the command enum were not cross-checked). No tests run.
