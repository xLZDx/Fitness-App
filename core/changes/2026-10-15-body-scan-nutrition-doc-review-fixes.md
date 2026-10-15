# Change record: Body Scan + Nutrition Coach, one-time documentation review fixes

## What changed
Documentation only, no code, no tests, no builds:
- `core/plans/BODY_SCAN_NUTRITION_TECH_DESIGN_2026-10-15.md` (v1.1): data model (5.1-5.11), rules (6.1-6.4), callables (7.1-7.9 incl. new `manageBodyScanData` and shared outbound/sanitising/logging rules), on-device provisional estimator (8), post-blur face-check gate (9), state machine and resume (10), capture gating and accessibility (11), result presentation rules (12), weight source (13.1), eligibility persistence and scan-surface mode (14), atomic weekly review (15), onboarding order and exact EN/RU safety-question copy (16), food abuse controls and diary states (17), privacy/export (20), routes and names (21), accessibility (24), risks R13-R18, decisions D-52..D-85 (27), seeds (28). The s12.1 fat/lean tile label (smoothed trend, labelled) and the s29 example range (29.2-32.4) are fixed.
- `core/plans/BODY_SCAN_NUTRITION_SPRINT_PLAN_2026-10-15.md` (v1.1): citations D-1..D-45 + D-52..D-85, SD-9 revised, SD-11..SD-15 added, commit rows C01-C03, C05-C07, C10, C12-C20, C21, C23, C25, C26 extended; still one PR and 27 commits.
- `core/plans/BODY_SCAN_NUTRITION_TEST_COVERAGE_MAP_2026-10-15.md`: new section 12 "Review-fix additions" (new ids, tests, counts); existing rows untouched except a pointer.
- `core/DECISION_LOG.md`: two entries (D-37..D-45 itemised; D-52..D-85). D-46..D-51 are reserved by the Phase 2 reconciliation document.
Not touched: `PRODUCT_PHASE2_EXPANSION_RECONCILIATION_2026-10-15.md`, `PHASE2_MULTISPORT_DEVICES_BACKLOG_2026-10-15.md`.

## Why
DEVELOPMENT RULES v4 step 1: one review pass by actual reviewer agents, then one fix batch. Five digests (architect A1-A12, security F1-F14, database D1-D14, product-ux 1-12, accessibility Y-F1..Y-F16 [the a11y digest uses F1..F16 too; written `Y-Fn` here]).

## Verified against the real files before applying
`release_guard.ts` 254-260 and 429-443 (hard-coded 4 AI callables, extra `fn-ai-runtime` function fails); `scaling.ts` (`RUNTIME_SA`, `AI_METERED` 15 x 10); `index.ts` 2372-2392, 2493, 2604-2690, 2744 (`sweepAccountData` runs as `fn-account-delete` in `deleteAccount` and the reconciler); `account_export.ts` 52-55, 101-109 (`MAX_ROWS` 2000, `limit(MAX_ROWS + 1)` with no `orderBy`; export runs as `fn-data`); `abuse_guard.ts` 111 (quota log carries uid); `health_flags.dart` `toJson` (null-valued keys) with `firestore.rules` 185-193 (five-key `hasOnly`); `scan_ports.dart` (`ScanCamera`, `MlKitScanCamera`), `scan_fakes.dart`; `scan_capture_screen.dart` 188, 203-204, 250-257, 590-606, 672-682, 883-890; `scan_viewfinder.dart` 155; `app_ru.arb` 1128 (plural without `many`); `step_answered.dart` `kOnboardingOrder`; `healthStepProfessionalGuidance` EN/RU text; `form_check_providers.dart` 1107. All cited facts held. Documents only: nothing was executed.

## Per-finding disposition
Rejected or modified:
- A12 "D-37..D-45 may be missing from DECISION_LOG": partly right (only a summary line existed); itemised now. The "four places" citations were fixed.
- Security F14 optional "short bucket lifecycle for pending objects" (also A10/F7 option): REJECTED, lifecycle rules match age and prefix, not Firestore state, and would delete retained photos; replaced by tombstone plus unmatched-object sweep (D-59).
- UX 3 "plan decision always hold under provisional": MODIFIED. The weekly review is weight-based and legitimate; only the scan-result decision CARD is replaced by a "See your plan" action (D-73).
- UX 10 "consider higher body-fat floor": DEFERRED (published clamp; needs operator and wording review); ETA gating below goal BMI 20, neutral copy and pause applied (D-77).
- UX 2 "reconsider the Supporter gate while provisional": kept per operator default Q-2, flagged to the operator.
- Security F4 age gate: APPLIED with the stated limit that `birthYear` is client-writable.
- Security F13 post-blur face check: PARTLY DEFERRED. The fail-closed port ships now; the real detector (new package) is a go-live gate for `BODY_SCAN_CLOUD` (D-69).
- Architect A11/Database D5 "signed JSON file" option: not taken; ordered paging chosen (D-61).
- Architect A9 migrating all seven `weightCurrentKg` readers: DEFERRED; only new features migrate, staleness documented (D-72).
- Security F14 other items: kill switch on body-scan callables, 1 h export links, ODbL re-check note applied or recorded; deploying deny-all `storage.rules` gets an explicit VERIFY.

## Affected contracts and paths
Documents only. Contracts changed in the documents (implementation not started): no stored `isBaseline`; no `referProfessional` value in any stored enum; `body_scan_settings` consent rule; `planVersion`/`reviewUndo`/`basePlanVersion`; `HealthFlags.toJson` omit-empty; new identity `fn-bodyscan`; new callable `manageBodyScanData`; `AI_CALLABLES` 4 -> 6 (in C20); export ordering/paging; `kOnboardingOrder` puts `nutrition` after `healthFlags`; `ScanCamera.luminance` default getter.

## Verification state
Not run, per DEVELOPMENT RULES v4 (documentation phase). Not verified: every `VERIFY` item, all runtime behaviour, emulator behaviour of the new rules, real IAM, real Firestore transaction semantics. Needs the operator: Q-1/Q-4/Q-5/Q-6/Q-10 remain blocked (flags off); Supporter gate while provisional; go-live gates in sprint plan SD-15.
