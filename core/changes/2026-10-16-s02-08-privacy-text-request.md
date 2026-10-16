# S02-08 change record: privacy text change request

Date: 2026-10-16. Story: S02-08 (design 6 "Privacy text", 12.1 DQ-10; test id F42).

## What changed

New `docs/phase2/s02/S02_PRIVACY_TEXT_REQUEST.md`: the content the in-app and `public/privacy.html` text must carry before the cloud flag is turned on (GPS routes in the cloud with user-set expiry, heart rate on the phone only with the honest limit, deletion and the clean-up delay, soft-delete window, export, the Phase 1 telemetry content change, no dedup promise), the stale existing lines, and the operator decisions it needs.

## Why

Design 12.1: `ACTIVITY_CLOUD_STREAMS` stays OFF until the text is approved. Wording is an operator-approved publication; the code publishes none.

## Deviations

None. `public/privacy.html` is intentionally not edited: the design (DQ-10) assigns the edit to the S02 PR, but the task for S02-08 limits the story to a request document; the edit therefore remains a follow-up behind operator approval.

## Verification state

Documentation only; no checks were run. F42 will fail until the page is edited (by design: it guards the flag).
