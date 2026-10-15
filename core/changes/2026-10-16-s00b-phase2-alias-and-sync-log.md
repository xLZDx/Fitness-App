# S00b: `phase2` Firebase alias and the sync log entry

Date: 2026-10-16. Branch: `phase2/s00b-sync-alias`, on top of the sync merge commit `39dc95cd` (record `core/changes/2026-10-16-s00b-sync-merge.md`).

## What changed
- `.firebaserc`: alias `phase2` -> `fitness-app-phase2-korostelev` (Firebase project created 2026-10-15 on the Spark plan; project number 254096452830; production is `fitness-app-korostelev`, number 988522745882). This lifts `phase2-alias-missing` for the deploy-line guard; the guard still rejects any `phase2/*` deploy to another project and any deploy whose effective project cannot be determined.
- `docs/SYNC_LOG.md`: the first sync entry, naming the merge commit `39dc95cd` (parents `db01888f` and `0eee9ca2`).
- `docs/phase2/README.md`: current state updated. `docs/DOCUMENT_REGISTRY.md`: regenerated. `core/DECISION_LOG.md`: one entry.

## Why
Backend separation exit: Phase 2 gets its own deploy target; sync protocol requires exact before and after SHAs. No Phase 2 cloud write is allowed yet: the open items before the first cloud deploy stay recorded in `docs/phase2/split/BACKEND_SEPARATION.md` (production project number hardcoded in the kill-switch secret path, candidate dotenv check, separate production credentials or protected CI, Blaze billing).

## Affected contracts and paths
`.firebaserc`, `docs/SYNC_LOG.md`, documents. No product code, rules or indexes.

## Verification state
No tests run. The guard tests use synthetic `.firebaserc` fixtures and none reads the real file (grep verified); the alias value was checked with `gcloud projects describe`. GPT-PM round 1 on the first form of this gate (`b804139d`): alias PASS, sync content PASS, MAJOR-01 the log lacked the exact merge SHA; fixed here.
