# Change record: pre-implementation gate round 6 (2026-10-23)

Base: 95ff39c7 (branch docs/v1-pre-start-review-fixes). Trigger: GPT-PM gate round 6 returned NO-GO with 0 BLOCKER and 2 MAJOR.

## What changed and why
- `OFFLINE_COMMAND_PROTOCOL.md` 1.5.6: BatchWrite is unsupported for updates and deletes (the update time of a no-op write result is the previous one); unsupported audit items become immediate unverified gaps keyed by the log insert id with a null commit time (`keySource` field), with no waiting and no correlation; before DRAIN they refuse admission, after DRAIN the phase never regresses and the flag `unsupportedAuditShapeSeen` refuses the cutover to SERVER_ONLY; S26 (xiv) extended with the no-op batch update collision assertion and the post-DRAIN encounter.
- `ACCEPTANCE.csv`: FU-AC-119 aligned.

## Affected contracts
Documentation only; no code, rules or deployment changed.

## Verification state
`validate_registers.py` OK (56/56/139/139). Nothing executed against an application; audit-log shapes remain UNKNOWN and gate DRAIN.
