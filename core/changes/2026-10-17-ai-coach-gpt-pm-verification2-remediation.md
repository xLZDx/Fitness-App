# AI Coach docs: GPT-PM verification round 2 remediation

Date: 2026-10-17. Base head reviewed: `db4b826a`. Documentation only.

GPT-PM returned MODIFY with three MAJOR test-wording items (V3-01..V3-03); R2-02 and MR-01..MR-05 were confirmed fixed.

- V3-01: FT-1133 now lists the per-command-type outcome of the same full-disk fault (VOLATILE for record/correct/void set, PERSIST_FAILED for ordinary commands, in-memory-first `rest_elapsed`, unconditional `safety_stop`).
- V3-02: FT-1020, FT-1104 and FT-1191 describe a `source=manual` envelope plus the separate local UI confirmation capability `ui_confirmed`; a `source=ui_confirmed` envelope or forged field is rejected (FT-1002).
- V3-03: FT-1176 and FT-1201 require EXPORT_OFFERED -> EXPORT_DONE -> WIPE_PENDING after a successful export, with the idempotent wipe at the next app start (WIPED).

Affected path: `docs/ai-coach/04a_FUNCTIONAL_TEST_PLAN.md`, logs, registry. Verification: none run (documentation); third focused GPT-PM verification of V3-01..V3-03 follows.
