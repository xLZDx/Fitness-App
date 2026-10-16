# S02 remediation H-A, item H2: uploader requires consent of its own account

Date: 2026-10-16. Area: mobile production code (stream uploader). Nothing was compiled or run by the author.

## Why

After H1 the consent view says which uid its state belongs to; the uploader must use it. Round-12 sweeps also found
that an account deletion in progress did not stop an in-flight upload (create/PUT/commit could re-create cloud data
after the server deleted the account) and that an A to B to A switch within one upload could mark the wrong journal's
entry.

## What changed

`mobile/lib/features/activity/repository/activity_stream_uploader.dart` only:

- `_mayUpload` became `_mayUpload(String? bound)`: besides flag, not cancelled and `isGranted`, an uploader with a uid
  supplier requires `_consent.consentUid == bound`. Consent of another or an unknown uid means no upload. An uploader
  without a supplier (unbound) keeps the old behaviour.
- New optional constructor parameter `String? Function()? accountBeingDeleted`; `_uidOk` is false when it returns
  the run's uid, so the run stops before the next create/PUT/commit.
- `markStreamUploaded` and the `uploadFailed` update are guarded by the run's uid, the uploader epoch and, for an
  account-scoped journal, `AccountScopedJournal.boundUid == bound` right before the call (new private
  `_journalBoundTo`). `cancelQueued`/`resume` semantics are unchanged.

## Affected contracts

`ActivityStreamUploader` constructor gains `accountBeingDeleted` (optional). `CloudStreamsConsentView.consentUid`
(added in H1) is now read. Behaviour change: a `cancelQueued` between commit and the journal mark now leaves the
entry unmarked (it is re-uploaded next start and the server answers already_stored).

## Verification state

Not compiled, not run. Oracles: `docs/phase2/s02/S02_REMEDIATION_H_TEST_NOTES.md` heading H-A (item H4).
