# Change record: pre-implementation review fixes (2026-10-22)

Commit: docs(v1): close pre-implementation review findings. Source: independent review of master 03ea66e1 (verdict NO-GO for the full implementation as specified; 2 BLOCKER, 11 MAJOR; the reviewer saw only the supplied documents).

## What changed
- `docs/v1/design/OFFLINE_COMMAND_PROTOCOL.md` (version 1.5.0): 8.3 item 12 (no silent loss with retries, watchdog, gap records, recovery window, residual risk O-R2); 8.7 deletion fence `deleted_accounts/{uid}` checked by rules and server writers; 5.3 rules as a deploy prerequisite and the new collection in the carve-out list; 2.2/2.3/4.2 origin install hashed, envelope copy removed, bounded `acceptedEpoch`; 4.2 step 2 exact in-transaction rate limit; 2.2 `titleKey` instead of free text; FU-AC-125 and FU-AC-119 text (scenario 21 two runs, S25, S26, scenario manifest).
- `docs/v1/design/PRE_IMPLEMENTATION_CONDITIONS_2026-10-22.md` (new): closure table, order of work, release-scope gate, ML baseline, runtime conditions, first vertical slice V0, open operator decisions.
- `docs/v1/design/SOURCE_RUNTIME_MANIFEST_2026-10-22.md`: section 6 records the master deployment of the same day.
- `docs/v1/design/MODULE_ROUTE_ACTION_MATRIX.md`: release gate note.
- `docs/v1/package-amendments/reissued/ACCEPTANCE.csv`: FU-AC-119 and FU-AC-125 aligned (notes record the change).

## Verification state
Documentation only. `validate_registers.py` OK (56/56/139/139, 48 new rows NOT_RUN). Nothing was executed against an application. Several facts the new design leans on are marked UNKNOWN and listed for verification in the conditions document (section 2 item 4).
