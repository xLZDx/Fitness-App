# Change record: pre-implementation gate round 4 (2026-10-23)

Base: 79cd1fb0 (branch docs/v1-pre-start-review-fixes). Trigger: GPT-PM gate round 4 returned NO-GO with 1 BLOCKER and 3 MAJOR.

## What changed and why
- `OFFLINE_COMMAND_PROTOCOL.md` 1.5.4: item 2 makes the `GAP` audit marker an explicit exception to the marker-first ordering (the trigger resolves the gap and writes the actual outcome in one transaction, compare-and-set per document); item 12 defines per-mutation audit extraction and its deploy check, a terminal `WRITE_NOOP` audit marker, a `WRITE_UNVERIFIED` gap kind (`lossProven` false) and non-assertive owner copy; S26 extended.
- `ACCEPTANCE.csv`: FU-AC-119 aligned.

## Affected contracts
Documentation only; no code, rules or deployment changed.

## Verification state
`validate_registers.py` OK (56/56/139/139). Nothing executed against an application; audit-log field coverage remains UNKNOWN and gates DRAIN.
