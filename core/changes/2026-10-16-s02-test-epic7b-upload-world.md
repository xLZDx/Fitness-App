# S02 test epic 7b: shared fakes for the client upload tests

## What
`mobile/test/support/stream_upload_world.dart`: a fake stream server (create, PUT, commit; refuses a commit without a complete PUT of that upload id with the announced hash; answers `already_stored`), a fake settings server, a fake consent view, kill hooks and a world that wires the real file journal, the real summary sync and an uploader with an injected clock.

## Why
The upload, retry and withdrawal tests need a server that fails on a wrong client sequence.

## Affected paths
- `mobile/test/support/stream_upload_world.dart`

## Verification state
Exercised by the three epic 7b test files; see `docs/phase2/s02/S02_TEST_FINDINGS_EPIC7.md`.
