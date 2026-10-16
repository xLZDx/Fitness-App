# S02 remediation J2: client calls bound to the initiating account

Date: 2026-10-16. Kind: production change (Dart client half) plus design and test notes.

## What changed
- mobile/lib/features/activity/repository/activity_cloud_settings_client.dart: `ActivityCloudSettingsClient` takes a required live-uid supplier `currentUid`; new getter `authMatchesAccount`; `grant`, `withdraw` and `ActivityConsentWithdrawal.deleteCloudStreamsNow` refuse unless the store uid is non-null and equals the live uid (start, immediately before the call, after the call); the request carries `expectedUid`; `cloudFunctionsSettingsCall` maps `failed-precondition` / `account_changed` to `ConsentAccountChangedException`; new helper `isAccountChangedRefusal`.
- mobile/lib/features/activity/repository/activity_stream_uploader.dart: `ActivityStreamCallableClient.create/commit` take a required `String? expectedUid`; the real client sends it, throws on null before any network call and maps the server pair; the uploader passes its pass uid and treats the account-changed outcome as a cancelled pass.
- mobile/lib/features/activity/repository/activity_sync_repository.dart and cloud_functions_activity_tombstone_pusher.dart: `ActivityTombstonePusher` takes `(activityId, expectedUid)`; the repository passes `pass.authUid`; the real pusher sends it, throws on null and maps the server pair; the repository stops the pass without failure bookkeeping on that outcome.
- mobile/lib/core/wiring/activity_wiring.dart: settings client gets `currentUid: () => FirebaseAuth.instance.currentUser?.uid`.
- docs/phase2/s02/S02_REMEDIATION_J_TEST_NOTES.md: CLIENT section (signatures, files to fix, behaviors to test, accepted limits). docs/phase2/s02/S02_DESIGN.md: client half appended to section 17 item 25.
- core/DECISION_LOG.md, core/LESSONS_LOG.md, document registry.

## Why
GPT-PM round 13 (MAJOR): a sign-in flip between the local uid check and the callable token read would apply account A's consent or data action to account B. J1 made the server verify `expectedUid`; J2 makes every client call send it and refuses to send when the live account differs.

## Affected contracts and paths
- Public Dart signatures changed (see the test notes): settings client constructor, `ActivityStreamCallableClient`, `ActivityTombstonePusher`, `CloudFunctionsActivityTombstonePusher.push`. Existing fakes and constructors in mobile/test do not compile until updated (listed in the notes).
- Not changed: server, rules, indexes, Firestore summary backend (path uid plus rules enforce the account), mobile/test.

## Verification state
NOT RUN. No test, analyze, lint or build was executed. Test agent pending: first restore compilation of mobile/test, then write and run the new tests listed in the notes.
