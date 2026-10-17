# S04 release checklist (story S04-38)

Status: DRAFT, 2026-10-17, branch `phase2/s04`. Documentation only; nothing was submitted, drafted for submission or checked against a built manifest. Paths are relative to the repository root.

Sources read: `docs/phase2/s04/S04_STORIES.md` (S04-38, section 5 Definition of Ready item 7, section 6 items 13 to 16), `S04_ANDROID_PLATFORM_STUDY.md` section 4 (Play policy), `S04_DESIGN.md` (minors statement, section 8 D-16).

Owners (PROPOSED in S04-38; open until the operator confirms): the operator owns every Play Console step; the product-owner drafts the texts and records status; the security-reviewer checks the texts against the shipped manifest. Allowed statuses: DRAFT, READY, NOT_RUN. No row is READY until its owner has confirmed it against an artifact.

Rule (S04-38 AC-4): the sprint can be accepted for code while any row is not READY, but the release is then recorded as BLOCKED, never as ready.

## 1. Required rows (S04-38 AC-1)

| # | Item | What it must contain | Drafted by | Checked by | Console owner | Status | Evidence |
|---|---|---|---|---|---|---|---|
| 1 | Privacy policy | location recordings are private to the account on the device; no sharing; no upload; deletion path; active non-PDF URL linked in the app and in the listing (Study 4.5) | product-owner | security-reviewer | operator (listing URL) | NOT_RUN | none |
| 2 | Play Console data-safety form | answers match the manifest and S04-28: no upload, no sharing, no heart rate | product-owner | security-reviewer | operator (Play Console) | NOT_RUN | none |
| 3 | Play Console foreground-service declaration (type `location`) | functionality, user impact if interrupted, use-case, video of the user starting the recording (Study 4.8) with the location use justification | product-owner | security-reviewer | operator (Play Console, App content) | NOT_RUN | none |
| 4 | In-app disclosure text | the word "location", what is collected, that it stays on the phone; strings marked DRAFT; text version equals the consent record (S04-21 AC-3) | product-owner | security-reviewer | operator (approves wording) | DRAFT | strings are DRAFT in the string file once S04-21 lands; not verified here |

## 2. Additional rows

| # | Item | Why | Owner | Status | Evidence |
|---|---|---|---|---|---|
| 5 | Minors statement (S04-38 AC-2) | states recordings are private only, no sharing, no upload; age gate stays with the product-owner (UNKNOWN: not in sources read) | product-owner | NOT_RUN | none |
| 6 | Background-location declaration, video and prominent disclosure dialog (Study 4.3 to 4.6) | needed only if story S04-18 takes branch B (background location requested); default branch: not requested, so the row reads not applicable | operator (console), product-owner (texts) | NOT_RUN (conditional) | none |
| 7 | Play question: is a `location` foreground service started while the app is visible treated as background location (Study 4.11) | UNKNOWN; answer needs Play support or a pre-launch submission | operator | NOT_RUN | none |
| 8 | Declared permissions equal used permissions; merged manifest checked in both flag states (S04-04 AC-1; DL-11) | data-safety and declaration must match the shipped build | security-reviewer | NOT_RUN | none |
| 9 | Data-safety answers compared with the manifest and S04-28 (S04-38 AC-3) | no upload, no sharing, no heart rate | security-reviewer | NOT_RUN | none |
| 10 | Server enforcement of GPS-PRIV-050 and GPS-PRIV-098 (Definition of Ready item 7) | precondition to build the recorder lanes and a release gate, unless the operator records a dated exception | operator, architect | NOT_RUN (UNKNOWN: not confirmed) | none |
| 11 | No battery-optimisation exemption request (design D-16; Study 5.7) | Play policy risk; scan DT-29-11 | security-reviewer | NOT_RUN | none |
| 12 | Device-lab record complete or its gaps stated (`S04_DEVICE_LAB_RECORD.md`) | release notes must not claim measured battery or tolerance without it | product-owner | NOT_RUN | none |
| 13 | Release notes: Android only, no iOS claim (S04-28 AC-4); limits stated (recovery after kill, not continued recording) | honest claims | product-owner | NOT_RUN | none |
| 14 | Export absent: scan finds no export entry point (Definition of Done item 16) | policy text must not mention export | security-reviewer | NOT_RUN | none |

## 3. Accepted risks to write down (S04-38 AC-5)

Each is to be recorded in the design or in this checklist before release. Status of each: NOT_RUN (not yet reviewed).

1. A rooted or debuggable build can read the key and memory.
2. A second app holding location permission sees the same fixes.
3. Notification-listener apps can read the notification.
4. File sizes and modification times reveal recording duration.
5. No AAD binding of frames; integrity only.

## 4. Release state

Current state: BLOCKED. Rows 1 to 3 and 5 to 14 are NOT_RUN and row 4 is DRAFT; the operator-owned Play Console rows (1 listing URL, 2, 3, 6, 7) have not been started. No statement in this file claims a submission.

## 5. Changes to this file

Statuses change only with an evidence reference in the Evidence column and the name of the person who confirmed it. Do not mark a Play Console row READY on the strength of a draft text alone.
