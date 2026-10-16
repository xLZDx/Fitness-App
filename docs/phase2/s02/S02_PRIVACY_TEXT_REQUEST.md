# S02 privacy text change request

Status: REQUEST. Operator approval is REQUIRED before any wording is published. No code in S02 publishes or edits privacy wording: `public/privacy.html` and the in-app text are unchanged by this sprint. Date: 2026-10-16. Design: `docs/phase2/s02/S02_DESIGN.md` sections 6, 12.1 (DQ-10); contract: `docs/phase2/s01/GPS_LOCATION_PRIVACY_CONTRACT.md` (D-16 row, GPS-PRIV-010).

## When this must be done

Before the client flag `ACTIVITY_CLOUD_STREAMS` is turned on and before `ACTIVITY_STREAM_BUCKET` is set in any real project. Both stay OFF until this text is approved and published (`public/privacy.html` and the in-app screen). Test F42 (`privacy_text.test.ts`) checks that the published page contains statements 1 to 3 below.

## Statements the text must make (content, not wording)

1. GPS in the cloud. When the user turns on cloud storage of routes (a separate, revocable consent), the GPS route of a recorded or synced activity, with altitude and speed, is uploaded and stored in a private store only the user's account can have links to. It is not shown to anyone else and is never used for friends, public or published routes in this release.
2. User-set expiry. The user chooses how long routes are kept, counted from the activity date. Offered options: 90 days, 1 year, 2 years (proposed default), and possibly "never" (OPEN operator decision, design 12.3: whether "never" exists and the default value). Shortening applies to older routes at the next daily clean-up; lengthening does not bring back routes already deleted for expiry. The summary of an activity (distance, duration and similar numbers) stays after its route expires.
3. Heart rate stays on the phone. Heart-rate series are kept on the device only and are never uploaded; the cloud summary does not contain heart-rate values. HONEST LIMIT to state (design 5.1a): the server checks the structure of uploaded routes but cannot detect heart-rate values deliberately disguised as another kind of number by a modified app, so the text must not promise a guarantee against a modified client.
4. Deletion. The user can delete one activity (the route, its index and the activity itself) and can delete all stored routes at once while keeping the activity summaries (offered when withdrawing consent). Deleting the account removes the routes and activity records; a short clean-up job finishes within about 15 minutes and a security record of the deletion lives up to about 70 minutes after the Auth deletion. Deleted-activity markers (id and date only) are kept up to 400 days so another device does not restore a deleted activity (TTL value proposed, OPEN).
5. Backup window. Deleted or expired route objects can remain recoverable inside the storage provider for the soft-delete window chosen by the operator (runbook section 1, GPS-PRIV-078). The text must state that window once chosen. Firestore backup and log retention windows (GPS-PRIV-079) are likewise OPEN and must be stated if they apply.
6. Export. The data export contains the activity summaries and the list of stored routes (state, size, expiry); the route files themselves are delivered as short-lived download links (valid 15 minutes), and routes can be exported as GPX and FIT files from the app. Heart-rate series on the phone can be exported from the phone only and are not part of the account export.
7. Phase 1 telemetry content change. Debug-build diagnostics (`debug_sessions`) no longer carry free-text log messages or the free-form build identity; they carry a fixed set of event types, levels and counters only, validated on the server. This is a reduction of collected data and may need a sentence in the diagnostics paragraph; if privacy text says that debug logs include messages or build details, it is now inaccurate.
8. No deduplication promise. The text and the app copy must not claim that activities from several sources (phone recording, health platform, sensors, vendor clouds) are matched or de-duplicated, except that re-syncing the same recording does not create a copy (design 9).

9. Summary sync (remediation A9, wording PENDING operator approval). When summary sync is on, scalar activity summaries (sport, times, duration, distance, power, cadence, steps and calories, including steps and active calories sourced from Health Connect or Apple Health) sync to the account, with no separate toggle. The existing Health Connect paragraph must therefore not say the readings never leave the phone without this exception. A draft paragraph "Activity summaries in your account" and the amended exception sentence are in `public/privacy.html`; they are DRAFT text that remains PENDING operator approval, are not final wording, and have no Russian counterpart yet (the page's Russian section must be updated when the wording is approved). The existing privacy-text test expectations (F42) must be updated by the test agent.

## Existing lines found stale (not changed by S02 code)

`public/privacy.html` lines 77, 91, 95 and 100 (matrix section 4): no mention of location or GPS; Cloud Storage named only for scan photos; "kept while the account exists" and "every document is erased" statements that do not mention stream objects, expiry or the late clean-up. These need the edit above when the flag is enabled.

## Operator decisions needed with this request

- Approve the wording (to be drafted from statements 1-8 and reviewed by GPT-PM) and the languages it must appear in.
- Default expiry and whether "never" is offered (design 12.3 items 1 and 9).
- Soft-delete window (runbook section 1).
- Tombstone retention (400 days proposed).
- Approve statement 9 (summary sync disclosure; open until approved).
- Soft-delete window disclosure (SEC3, operator-owned; accepted as open item, see design section 17).

Until these are answered the cloud flag stays OFF; device-only behaviour needs no new text.
