# Change record: finish a device wipe after an interrupted account deletion (NEW-DELETE-INTERRUPT)

**Problem.** Account deletion calls the server, then wipes the device, then signs out. The wipe needs the uid from the signed-in user. If the process died after the server confirmed, or a retry found no signed-in user, the uid was lost: the wipe was skipped and the health blob and photos stayed on the phone, while the account no longer existed. Nothing swept such leftovers at startup.

**Change.**
- `data/local_data_wipe.dart`: `PendingWipeMarker` (SharedPreferences implementation `PrefsPendingWipeMarker`, key `account_deletion.pending_wipe_uid`, plus an in-memory one) stores only a uid. `finishInterruptedWipe(...)` wipes the marked uid and clears the marker when it completes; it keeps the marker when the wipe fails, and leaves a marker alone when that account is still the signed-in one.
- `state/account_deletion_providers.dart`: the marker is written right AFTER the server confirms the deletion and before the wipe, cleared only when the wipe finishes without error. `interruptedWipeSweepProvider` runs the sweep once, as soon as the signed-in user is known after launch.
- `main.dart`: SharedPreferences marker override and the sweep provider watched from the app root.

**Design decision.** The marker is written after the server confirmation, not before the call. A marker that existed while the account was still alive could later erase the only copy of a live account's health answers (the device is their only home). The remaining gap is the instant between confirmation and the marker write.

**Contracts touched.** Account deletion flow, app startup (one auth read, then at most one background wipe).

**Known limits.** If the server response is lost after a successful deletion, the retry still reads the uid from the signed-in user, as before. A marker for an account that is still signed in is ignored, which is correct for a deletion that has not completed.

**Verification state.** Not run; the test agents write and run the focused tests at sprint end. Nothing pushed.
