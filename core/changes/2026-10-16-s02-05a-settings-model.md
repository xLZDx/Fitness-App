# S02-05a change record: activity settings model (pure)

Date: 2026-10-16. Story: S02-05a (design sections 5.3, 9, 9.1; test ids F13, F75, F68).

## What changed

- `functions/src/activity_streams/settings.ts` (new, no Firebase imports): the pure model of `users/{uid}/activity_settings/main`.
  - Constants: `CLOUD_STREAMS_CONSENT_VERSION` (1), `DEFAULT_STREAM_RETENTION_DAYS` (730), `ALLOWED_STREAM_RETENTION_DAYS` (90, 365, 730) and `STREAM_RETENTION_NEVER_OFFERED` (true). The last three are marked OPEN-DEFAULT in comments: the operator questions on the default value and on "never" (design 12.3 item 1, DQ-7) are still unanswered.
  - `parseSettingsRequest`: closed strict parse (unknown keys refused), bare codes `invalid_request`, `invalid_retention`, `invalid_consent`; the consent version must equal the current one.
  - `planSettingsChange`: pure transition computing the generation increment (once per effective change), `recomputePending` (only when the retention value changes), and the consent grant or withdrawal timestamps from an injected clock. An identical request is a no-op.
  - `cloudStreamsConsentState`, `effectiveStreamRetentionDays`, `settingsGenerationOf`, `isWithdrawalOnly`: readers shared with the upload callables (S02-04b) and the purge (S02-05b), so validation and purge cannot disagree on "never" (F13 versus F15).

## Why

Settings are the one input the upload callables trust, so the transition logic is isolated as a pure function that test agents can drive with plain objects and an injected clock.

## Affected contracts and paths

`functions/src/activity_streams/settings.ts` only. The callable, quota and export follow in the next commit.

## Verification state

No tests, builds, lint or type checks were run (operator rule v4). Test agents verify with F13, F68, F75.
