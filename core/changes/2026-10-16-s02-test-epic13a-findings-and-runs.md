# S02 test epic 13a: complete runs, flaky ciphertext assertion, findings

Date: 2026-10-16. Area: tests and documentation.

## What changed

- `file_activity_journal_encryption_test.dart` (I07): the assertion that the random ciphertext contains no `1F 8B`
  anywhere was flaky (about n/65536 per run, it failed once in a complete run). It now checks that the stream does not
  START with a gzip header. All other plaintext-absence assertions are unchanged.
- `docs/phase2/s02/S02_TEST_FINDINGS_EPIC13.md`: section Epic 13a with files, defects and layers, commands and summary lines.

## Verification state

Complete directory run `flutter test --timeout 60s test/features/activity`: `03:25 +1304: All tests passed!`.
Guards: `00:09 +120: All tests passed!`.
