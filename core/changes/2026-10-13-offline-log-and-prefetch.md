# Change record: offline "Mark complete" and concurrent prefetch (NEW-OFFLINE-LOG, NEW-PREFETCH-CONCURRENT)

Authored by a second Claude session (`fitness-app-93`) working the same tail list; it stopped before committing. The three files were read in full by the committing session before this commit and are committed unchanged.

**NEW-OFFLINE-LOG — problem.** A Firestore write future completes only on server acknowledgement, so "Mark complete" spun until the network returned, and a second tap could start a second write.
**Change.**
- `firestore_workout_session_repository.dart`: the session `set()` is bounded to 4 seconds. The write is already in the local cache and will sync; the document id is the session id, so a retry upserts the same document. A genuine server rejection after the timeout is not reported to that caller.
- `workout_session_providers.dart`: a re-entrancy guard (`state.isLoading` returns early) and a 4-second bound on the streak write, which is a transaction and cannot complete offline.

**NEW-PREFETCH-CONCURRENT — problem.** Two callers asking for the same clip wrote the same `.part` file, and the failure cleanup of one deleted it under the other.
**Change.** `offline_video_cache.dart`: downloads in flight are shared per url (`_inFlight`); the second caller's `onProgress` is not called. An empty cached file is treated as a miss and fetched again instead of being served forever.

**Contracts touched.** Workout completion latency and its failure reporting; the offline video cache's download path.

**Known limits.** After the 4-second bound a rejected write is invisible to the user. Whether the SDK really leaves offline writes un-acknowledged is the original finding's own hypothesis and was not measured.

**Verification state.** Not run; the test agents write and run focused tests at sprint end. Nothing pushed.
