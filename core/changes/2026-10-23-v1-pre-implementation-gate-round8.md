# Change record: pre-implementation gate round 8 (2026-10-23)

Base: ebc15773 (branch docs/v1-pre-start-review-fixes). Trigger: GPT-PM gate round 8 returned NO-GO with 0 BLOCKER and 1 MAJOR.

## What changed and why
- `OFFLINE_COMMAND_PROTOCOL.md` 1.5.8: status validation for audit records (present, parseable, index-aligned); explicit OK, explicit non-OK and UNKNOWN; only explicit non-OK is skipped; UNKNOWN is accounted as an unverified gap (`statusUnknown`, nullable session for a record-level gap), with the alert, the flag and a refused cutover, and refuses DRAIN admission when found in the deploy sample; S26 (xvi) added.
- `ACCEPTANCE.csv`: FU-AC-119 aligned.

## Affected contracts
Documentation only; no code, rules or deployment changed.

## Verification state
`validate_registers.py` OK (56/56/139/139). Nothing executed against an application.
