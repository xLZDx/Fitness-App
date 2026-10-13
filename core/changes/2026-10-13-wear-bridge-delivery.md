# Change record: Wear bridge reports real delivery (NEW-WEAR)

**Problem.** The phone side of the Wear bridge lives in `mobile/android/.../MainActivity.kt`, not in `wear/`. `pushState` answered "success" before any message reached a watch. `connectedNodeIds` called `Tasks.await` on the main thread, where it throws `IllegalStateException`; a catch-all turned that into an empty list, so every lookup looked like "no watch connected".

**Change.**
- `MainActivity.kt`: `isPaired` and `pushState` work runs on a single-thread executor (shut down in `onDestroy`) and posts the result back on the UI thread. `pushState` waits for every `sendMessage` task and replies with `result.error("WEAR", ...)` on failure. `connectedNodeIds` logs and rethrows, so an empty list now means only "no connected watch".
- `wear_sync_service.dart`: `pushState` lets a `PlatformException` reach its caller; `MissingPluginException` still returns false. `isWatchPaired` still maps any error to false. Signature unchanged; no other callers of `pushState` were found.
- `wear_sync_service_test.dart`: two cases (native error is rethrown, native true is returned).

**Contracts touched.** Method-channel replies for the Wear bridge.

**Verification state.** Not compiled and not run; the test agents do that at sprint end. No on-device check. Nothing pushed.
