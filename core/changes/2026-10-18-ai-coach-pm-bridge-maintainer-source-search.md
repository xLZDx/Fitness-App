# PM Bridge maintainer-source search

Date: 2026-10-18

## Change

Recorded an additional read-only GitHub ownership and issue search in the PM Bridge recovery eligibility record.

## Evidence

- In `xLZDx/PM_Bridge`, GitHub returned 404 for root `CODEOWNERS`, `.github/CODEOWNERS`, `MAINTAINERS`, and `CONTRIBUTING.md`.
- Searches for `ATTACHMENT_NOT_LANDED`, the `acceptance.md` composer failure, and attachment recovery returned no issues.
- Repository metadata lists `xLZDx` with `admin` and `maintain` permissions. This is evidence of repository permissions and a potential escalation route; it does not establish a formal PM Bridge service maintainer.
- No issue, comment, message, retry, or payload change was made.

## Affected paths and remaining dependency

- `core/changes/2026-10-18-ai-coach-pm-bridge-recovery-eligibility.md`
- `core/changes/2026-10-18-ai-coach-pm-bridge-maintainer-source-search.md`

The PM Bridge repository owner account is the available route to ask for the formally responsible maintainer and same-lineage recovery procedure. The task still requires reproduction of the original payload hash before retry; the owner permission alone does not authorize changing payload or creating a replacement request.

No tests, checks, builds, CI, migrations, runtime actions, push, or merge were performed.
