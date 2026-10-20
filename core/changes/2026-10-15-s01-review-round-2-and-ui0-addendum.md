# S01: contract review round 2 and UI-0 addendum

Date: 2026-10-15. Branch: `phase2/s01-contracts`.

## What changed
- `docs/phase2/s01/GPS_LOCATION_PRIVACY_CONTRACT.md` and `DATA_LIFECYCLE_MATRIX.md`: round 2 fixes after the security re-review of `fad4dd5d` (3 MAJOR, 4 MINOR). Now 98 requirements (new 095..098): client-writable location subcollections that need a key allowlist are excluded from both owner-wildcard clauses and get their own shape-checked block (071); privacy zones become data class C11 with a matrix row, a consent-gated exemption from the D-16 stream retention, shape-checked rules and a sweep-map row (095); friends visibility follows D-17 with "known adult", "known minor" and "unknown age" defined (040, 088); reconciliations of 031/064/072/093/054; viewer position not retained server-side (096); owner link list through a callable (097); rules-side bound on `debug_sessions` event keys (098). D-16 and D-17 stay open.
- `docs/phase2/s01/UI0_BASELINE_AUDIT_ADDENDUM.md` (new): closes the gaps the product-ux and accessibility review found: keyboard and focus, computed contrast on the live token layer, text scaling at 200 percent, touch targets, state matrix for the shell and S03-D screens, notification and resume inputs, screen-reader semantics, reduce motion, colour-layer counts, localisation and layout, corrections to the first report. Contrast values are computed by hand from hex and labelled so.
- `docs/phase2/s01/UI0_BASELINE_AUDIT.md`: provenance header corrected (the audited `mobile/` tree is the one at `6616d2f8`, based on `42d1b849`; it does not contain the code merged by PR #5).
- `core/DECISION_LOG.md`: one entry.

## Why
Operator-approved sprint S01 (documentation only). The internal reviewers (security, product-ux and accessibility) returned MAJOR findings that block GPT-PM submission.

## Affected contracts and paths
Documentation only. No code, rules or flags changed.

## Verification state
No tests or checks run. Contract text is PROPOSED. The addendum is a read-only agent report: contrast values are hand-computed (about +-0.1), nothing was rendered or run, and the "NOT VERIFIED" items listed at its end remain open. Not verifiable from the repository: cloud backup, soft-delete, CDN and log retention settings. A third security verification pass, GPT-PM review and operator approval are pending.
