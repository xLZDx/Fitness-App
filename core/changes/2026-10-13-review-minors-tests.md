# Change record: tests for the review-minor fixes

**Change (tests only, no `lib/` change).**
- `backup_transfer_test.dart` (+6): a failed store write leaves `canUndo` false and keeps an earlier undo working; the same uid re-emitted keeps the undo; a uid change and a sign-out clear it.
- `interrupted_wipe_test.dart` (+8): markers `''`, `.`, `..`, `a/b`, `a\b` are cleared and never wiped; a throwing `marker.read` or `marker.clear` returns false instead of throwing.
- `file_offline_video_cache_test.dart` (+1): a failed first partial sweep does not fail the next download.
- `backup_page_test.dart`: fixed sleeps replaced by waiting for the restore action to leave loading; auth override is a synchronous `StreamController` (the restore notifier now subscribes to auth while the page builds inside the fake-async zone, where `Stream.value` never delivered); the new "Undone" wording is asserted.

**Verification state.** Run by the test agent on the committed code: backup_envelope 16, backup_transfer 22, interrupted_wipe 23, local_data_wipe 16, wear_sync_service 8, log_session_action 5, file_offline_video_cache 16 (one run of the overlapping-fetch test failed once, three reruns passed; treated as a flake, not quarantined), backup_page 2/2 on three consecutive runs. After an `.arb` change, `flutter gen-l10n` is needed when tests run with `--no-pub`. The Kotlin timeout change cannot be compiled here and is unverified. Nothing pushed.
