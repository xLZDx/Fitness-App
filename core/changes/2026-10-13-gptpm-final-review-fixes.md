# Change record: fixes for the final GPT-PM review (round 1, REJECT with 3 MAJOR)

Review range 3da7737..bcf7322. Each finding was checked against the source before acting.

**F-01 — interrupted wipe never retried after sign-out.** The startup sweep ran once and skipped a marker for the still-signed-in uid, so the later sign-out never triggered it again. `interruptedWipeSweepProvider` now runs on every resolved auth value, chained so two runs never overlap.

**F-02 — a second deletion overwrote the first pending marker.** `PendingWipeMarker` is now a set (`read/add/remove`, key `account_deletion.pending_wipe_uids`, a string list). `finishInterruptedWipe` handles every pending uid independently: it skips the signed-in uid, drops garbage values, keeps only the uids whose wipe failed, and returns true when at least one wipe completed. The old single-uid key never shipped (nothing pushed), so there is no migration.

**F-03 — export byte ceiling not guaranteed for non-array sections.** Firestore documents are capped at 1 MiB, so this needed many near-limit single documents, but the guard was still incomplete. The final response (notes included) is now measured against `HARD_RESPONSE_BYTES` (9.5 MiB, under the 10 MiB callable limit); above it the callable throws `resource-exhausted` instead of returning an oversized success.

**Tests (written and run by the test agent).** account_deletion directory 63 passed; functions account_export + delete_account 43 passed. New cases: marker {u1} with auth u1 then null; non-overlapping runs; failed first deletion followed by a second one keeps both uids; Prefs and in-memory set semantics; oversized non-array section rejects; an 8.5 MiB response still succeeds.

**Verification state.** Focused tests only; no full suites, lint or CI by policy. Nothing pushed. A second GPT-PM round checks these three fixes and direct regressions.
