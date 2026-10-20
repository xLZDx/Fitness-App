# S02 test epic 14a: stale fakes and older assertions for remediation H-A

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`. Head under test: 4f66324d.

## What changed
- `mobile/test/support/stream_upload_world.dart`: `FakeConsent` implements the new `CloudStreamsConsentView.consentUid` (fixed value, default `uid`, or a `followUid` supplier for tests that flip the uploader's uid).
- Five `_Settings` fakes (`activity_journal_wipe_wiring_test`, `activity_wiring_account_switch_test`, `activity_republish_wiring_test`, `activity_tombstone_continuation_test`, `activity_wiring_flag_matrix_test`) gain `reset()`; the wiring now calls it on an account change and a `Fake` threw `UnimplementedError`.
- `activity_wiring_account_switch_test`: the resume-throws test now expects the `start stream upload failed` log (resume runs inside the upload step) and the summary sync that now runs before it (`listTombstoneIds`).
- `activity_stream_upload_test`: a store write before sign-in now throws `StateError` (was: silently dropped).
- `activity_stream_upload_account_binding_test`, `activity_stream_uploader_account_switch_test`: consent follows the flipped uid (the uploader now needs `consentUid == currentUid()`).

## Why
Remediation H changed the consent and uploader contracts without compiling. These tests asserted the older contract.

## Affected contracts and paths
Test code only. No production code changed in this commit.

## Verification state
The tree compiled unchanged. Per file: wiring_account_switch `+26`, stream_upload `+29`, account_binding `+20`, uploader_account_switch `+7`, wipe_wiring `+16`, republish `+21`, flag_matrix `+23`, consent_withdrawal `+12`, retry `+22`. The tombstone continuation file was run and printed passing progress only (its final summary line was cut by the filter and is re-run in the final whole-directory run).
