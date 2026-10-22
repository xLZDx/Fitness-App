# Change record: v1 design documents, reissued registers and runtime manifest (2026-10-22)

## What changed
- `docs/v1/design/OFFLINE_COMMAND_PROTOCOL.md` (v1.2), `QUEUE_LIFECYCLE_DATA_PRIVACY.md`, `MODULE_ROUTE_ACTION_MATRIX.md`: revised after an internal reliability review (1 BLOCKER, 8 MAJOR, then 5 MAJOR regressions) and a security review (6 MAJOR on the lifecycle document, 2 stale rows in the matrix); the 30-day migration period is the operator's decision of 2026-10-22.
- `docs/v1/design/SOURCE_RUNTIME_MANIFEST_2026-10-22.md`: current source head, deployed function state, how the Node 22 migration was done, one incident and its correction, findings.
- `docs/v1/package-amendments/reissued/`: the four package registers reissued with the amendments applied (138 acceptance rows, 47 new, all NOT_RUN), `AMENDMENT_LOG.md` and `validate_registers.py`.

## Why
The independent package review (verdict MODIFY, 3 BLOCKER, 7 MAJOR) required a frozen offline command protocol, the queue lifecycle in the data and privacy contracts, a module reachability matrix, reissued registers and a current source and runtime manifest before implementation of the queue.

## Production action recorded here
All 23 Cloud Functions were moved from nodejs20 to nodejs22 on 2026-10-22 by redeploying each function's own deployed source with only the runtime changed; no master code was deployed. Details, the corrected incident and the rollback path are in the manifest.

## Affected contracts and paths
Documentation and registers only in the repository. No source, test, build or rules file changes. The production runtime change is outside git and is described in the manifest.

## Verification state
Documents were reviewed by two internal reviewer agents; the registers pass `validate_registers.py` (agent-run: acceptance=138, traceability=138). Nothing in the protocol is implemented. GPT-PM documentation gate pending for this commit.
