# Change record: fixes for the valid MINOR findings of the sprint-end specialist reviews

**Problem.** Four specialist reviews (silent failures, reliability, Flutter, security) of the NEW-* tail fixes returned APPROVE_WITH_MINORS with no BLOCKER or MAJOR. The small, clearly valuable minors are closed here as one batch.

**Change.**
- `offline_video_cache.dart`: a failed partial-file sweep no longer stays cached as the shared sweep future, so the next download retries it.
- `MainActivity.kt`: the Wear `Tasks.await` calls (message send, connected nodes) are bounded by a 5 s timeout, so a stalled Play Services call cannot hold the executor thread.
- `backup_providers.dart`: the in-memory undo is assigned only after the store write succeeds (a failed restore neither offers an undo nor discards an earlier one); the held undo is dropped when the signed-in account changes or signs out.
- `backup_page.dart`, `app_en.arb`, `app_ru.arb`: a failed undo keeps the Undo button; the "Undone" text now says the phone is back to its state before the restore.
- `workout_session_providers.dart`: the swallowed streak-record failure is logged (exception type only).
- `local_data_wipe.dart`: `finishInterruptedWipe` is fully guarded (a marker read or clear failure returns false instead of throwing); a marker value that is empty, `.`, `..` or holds a path separator is cleared and never reaches the wipe; logs carry the exception type only.

**Not fixed (backlog, recorded in the tail registry).** Dio connect timeout; pre-existing Wear EventChannel handling; `SecurePhotoKeyStore.forget` swallow; a re-entrant restore call looks like success; empty temp-file rename in the video cache; health `currentAuthStatus` transient indistinguishable from revoke; health card retry button and raw error text; static policy checker blind to `isOrdinaryUser()`. The backup owner tag is a mismatch hint, not authentication, by design.

**Contracts touched.** Backup restore/undo, interrupted-deletion sweep, offline video cache, Wear bridge timeouts.

**Verification state.** Focused Flutter tests for the touched areas are run by a test agent after this commit; the Kotlin change cannot be compiled in this environment and is unverified. Nothing pushed.
