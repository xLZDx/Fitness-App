# PM Bridge durable ledger payload audit

Date: 2026-10-18

## Change

Added direct read-only SQLite schema evidence to `core/changes/2026-10-18-ai-coach-pm-bridge-recovery-eligibility.md` to determine whether the original failed request can be recovered locally.

## Evidence

- Opened `D:\Repo\pm-bridge\state\pm-bridge.sqlite` with SQLite URI `mode=ro`; no database mutation was performed.
- The `jobs` table has `payload_hash`, lifecycle/send fields, `send_snapshot_json`, and identity fields, but no payload bytes or attachment-content field.
- The target request `26649707-679f-4962-8d26-e3b2a2ff36b2` is `failed` at `send_phase=not-started`, with `ATTACHMENT_NOT_LANDED`, `generation_lease=NULL`, and no send snapshot. Its durable event record cannot reproduce the source payload.
- `reserveJob` may reopen this failed pre-send job only with the same request/idempotency identity and a matching recomputed payload signature. The exact source bytes are therefore required before a retry.

## Disposition and affected paths

No retry, new request, payload change, cancellation, lease release, or runtime operation was made. The remaining dependency is a supported recovery of the original immutable payload or equivalent exact source data from the PM Bridge maintainer. The formal maintainer is not identified; `xLZDx` has repository admin/maintain permissions but was not promoted to service-owner status.

- `core/changes/2026-10-18-ai-coach-pm-bridge-recovery-eligibility.md`
- `core/changes/2026-10-18-ai-coach-pm-bridge-ledger-payload-audit.md`

No tests, checks, builds, CI, migrations, runtime actions, push, or merge were performed.
