# AI Coach docs: verification round 3 sibling rows

Date: 2026-10-18. Documentation only; no code, no tests run.

GPT-PM focused verification round 3 on `d12d00e8` returned MODIFY: the three targeted findings V3-01, V3-02 and V3-03 were fixed in their primary rows, but three sibling rows still asserted superseded contracts. Each was checked in the file before editing.

- FT-2017 (voice record_set read-back): the persistence-failure branch named `PERSIST_FAILED` for record_set. Now the record_set branch is `VOLATILE` (FT-1025): no saved or recorded-success acknowledgement is spoken; `PERSIST_FAILED` stays for ordinary commands.
- FT-1190 (refused origins during a whole safety stop): a forged `ui_confirmed` source or capability field on an envelope from the model or replica lane is now `INVALID_ARGUMENT` (FT-1002), not the user-only refusal; the six structurally valid origins keep the user-only refusal. Counts updated from 7 sources to 6 origins plus a forged envelope.
- FT-1175 (account-deletion wipe): the sequence named DETECTED -> EXPORT_OFFERED -> WIPE_PENDING -> WIPED; it now names the successful-export branch DETECTED -> EXPORT_OFFERED -> EXPORT_DONE -> WIPE_PENDING with WIPED at the next app start, and points to FT-1176 for the dismissed, failed and expired branches.

Affected paths: `docs/ai-coach/04a_FUNCTIONAL_TEST_PLAN.md`, `docs/sdlc/STATE.md`, logs. A repository-wide grep for "of the 7", "7 sources" and "OFFERED -> WIPE_PENDING" found no other row of this contract (FT-4001 concerns CoachEvent, unrelated).

Verification: none run (documentation). Next: GPT-PM focused verification of FT-2017, FT-1190 and FT-1175 on the new head.
