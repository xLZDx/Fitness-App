# G4 Step 7 — product-level real-device E2E (S8)

## DoD (from the gate's own binding exit criteria)

"functional real-device product E2E on the S8 debug build" — a real user, driving the real app
UI (not curl, not a unit test), triggering a real AI Gateway call and seeing a real answer render
on screen.

## Why this needed its own probe

The app supports only Anonymous and Google sign-in (confirmed via an existing code comment in
`firebase_auth_repository.dart` stating email/password was checked for and does not exist). AI
features require a non-anonymous account (`abuse_guard.ts`'s `AI_ALLOW_ANONYMOUS` defaults to
false), and Google sign-in cannot be scripted through `adb` (it hands off to a real Google
account-chooser activity outside the app's own control). A temporary, `kDebugMode`-gated debug
sign-in button was added to `login_page.dart`, calling
`FirebaseAuth.instance.signInWithCustomToken()` with a token minted server-side via IAM `signBlob`
impersonation (same mechanism used for every prior step's test tokens this gate) — same lifecycle
as every other probe this gate has used: added, used once, then deleted in the same session.

## What was proven, on the real S8 device, through real app navigation

1. **Real non-anonymous sign-in** via the custom token — the app navigated into the onboarding
   flow (10 steps) as a brand-new account (`g4-step7-product-e2e-probe`), confirming the token was
   accepted and a real Firebase Auth session was established (not anonymous — anonymous accounts
   skip straight to `/home` with no onboarding).
2. **Real `aiEquipmentRecognition` call**, through the actual Scan tab UI (`Незнакомый тренажёр? →
   Распознать тренажёр → gallery picker`), on a real photo (the same gym photo used for Step 5's
   Vertex-reachability proof, pushed to the device's own gallery via `adb push` +
   `MEDIA_SCANNER_SCAN_FILE`, picked through the OS's own gallery picker — not fed to the app
   directly). Result rendered on screen: **"Блочный тренажёр (кроссовер)" at 98% confidence**,
   correctly identifying the cable-crossover machine in the photo. The result card sits below the
   fold of the scan screen's draggable sheet — required scrolling to see, which is also why an
   earlier screenshot before scrolling looked like nothing had happened.
3. **Real `aiCoachAdvice` call**, through the "AI-тренер" card's real UI, which appeared directly
   under the recognition result. The sheet showed a live "Думаю..." (thinking) state, then
   rendered a real, contextually correct coaching tip: *"Отрегулируйте высоту блоков под нужное
   упражнение и выберите легкий вес"* — genuinely specific to a cable-crossover machine, not a
   generic placeholder.
4. **A second, independent `aiEquipmentRecognition` call** on a different real gym photo
   (elliptical trainers) — confirms the recognition path is not a one-off: **"Эллиптический
   тренажёр" at 98% confidence**.
5. **Real `aiMachineDescription` call**, reached the same way a real user would trigger it: a
   genuinely non-gym photo (a fresh photo taken with the device's own stock camera app — a
   ceiling/doorframe) picked via the same gallery flow. The classifier found no catalogue match
   (`ScanOutcome.noEquipment`), which `VisualEquipmentController.classifyFilePath` always follows
   with `_describeInstead()` — the real describer callable. The model correctly judged the photo
   `isGymEquipment: false`, so `GeminiMachineDescriber.parseDescription` returned `null` and no
   card rendered; the client correctly showed the "Не удалось понять, что это" hint instead of
   crashing, hanging, or silently doing nothing. This proves request wiring, App Check propagation
   and state handling for the describer's "not nameable" branch — the exact class of mobile-specific
   failure the round-1 review below was concerned Steps 4-6's API-level proof couldn't catch.

## Server-side confirmation

Queried the same structured `callable-request-verification` log used for Step 4's App-Check-vs-Auth
isolation proof, for the exact window of these on-device calls (UTC; device local time is UTC+2):

| Time (UTC) | Function | `verifications.app` | `verifications.auth` |
|---|---|---|---|
| 23:44:27 | `aiequipmentrecognition` | `VALID` | `VALID` |
| 23:45:07 | `aiequipmentrecognition` | `VALID` | `VALID` |
| 23:49:40 | `aicoachadvice` | `VALID` | `VALID` |
| 00:02:27 (Aug 29) | `aiequipmentrecognition` | `VALID` | `VALID` |
| 00:03:41 (Aug 29) | `aiequipmentrecognition` | `VALID` | `VALID` |
| 00:07:06 (Aug 29) | `aiequipmentrecognition` | `VALID` | `VALID` |
| 00:07:11 (Aug 29) | `aimachinedescription` | `VALID` | `VALID` |

Two `aiequipmentrecognition` calls at 23:44/23:45 appear because the first on-device attempt
(gallery pick before the media-scanner broadcast had fully indexed the pushed photo) is captured
too — both independently passed real verification; the second is the one screenshotted. The same
pattern repeats at 00:02/00:03 for the elliptical photo. All are genuine calls, none mocked.

This closes the loop end to end for three of the four AI Gateway callables through real product
UI: `aiEquipmentRecognition`, `aiCoachAdvice`, and `aiMachineDescription`. `aiExerciseGeneration`
has, per its own source comment, "no consumer in `lib/`, deliberately, since C14" — it is not a
currently reachable product surface, so no UI proof applies to it; its real Vertex call and
quota-exhaustion path were already proven at the API level in Steps 4-6.

## Durable UI evidence

Round 1 GPT-PM review (below) flagged that the on-device screenshots were described in prose but
then deleted from the device with nothing preserved. Preserved copies, plus a manifest mapping each
one to its server-side log entry:

- `core/screenshots/g4_step7_equipment_recognition_98pct_2026-08-29.png`
- `core/screenshots/g4_step7_ai_coach_advice_rendered_2026-08-29.png`
- `core/screenshots/g4_step7_elliptical_recognition_98pct_2026-08-29.png`
- `core/screenshots/g4_step7_machine_description_not_equipment_2026-08-29.png`
- `core/evidence/g4_step7_ui_evidence_manifest_2026-08-29.json`

**Not captured**: a rendered `MachineCard` for a real, uncatalogued-but-nameable machine (the
`isGymEquipment: true` branch of the describer). Three real gym photos from the project's own
dataset were tried; all three matched the catalogue confidently (98% each), so the classifier
never reached `noEquipment` for them. A cropped weight-plate close-up was attempted to force a
non-catalogue shape while staying genuine gym content; the crop missed the target region (EXIF
rotation confused the raw-pixel crop coordinates) and still showed machine framework. Continuing
to iterate against real Vertex calls to hit this exact narrative was judged not worth the
additional cost, given the wiring is already proven for both of the describer's real outcomes
(request reaches the server, App Check/Auth verified, response parsed, state transitions, UI
renders correctly) — only the JSON shape differs, and `isGymEquipment: true` parsing is covered by
`mobile/test/features/visual_equipment/machine_describer_test.dart` (lines 18, 209, 353, 376, 395).

## Cleanup (same session, same lifecycle as every prior probe)

- Debug sign-in button and its `kDebugMode`/`FirebaseAuth` imports removed from `login_page.dart`
  (`flutter analyze` clean afterward).
- Test Auth user `g4-step7-product-e2e-probe` deleted (`accounts:delete`, verified via a follow-up
  `accounts:lookup` returning an empty `users` list).
- Temporary `roles/iam.serviceAccountTokenCreator` grant on
  `firebase-adminsdk-fbsvc@fitness-app-korostelev.iam.gserviceaccount.com` for
  `korostelevivan@gmail.com` revoked.
- Test photos and every screenshot removed from the device's `/sdcard` — the four screenshots
  needed as durable evidence were copied into `core/screenshots/` first (see above).

## Known observation, out of scope for this step

`gcloud functions deploy` auto-generates `functions/.gcloudignore` in the source directory when one
is absent, and it chains `#!include:.gitignore` — the exact mechanism that excluded `lib/` from a
bare `gcloud deploy` upload in Step 4 (worked around there with a scratchpad-only `--ignore-file`,
never touching a real ignore file). That auto-generated file is now sitting untracked in the repo
(`functions/.gcloudignore`, confirmed via `git status`) from an earlier deploy in this gate. It is
not staged or committed by this step's own commit. Flagged here rather than fixed silently — a
future bare `gcloud functions deploy` without an explicit `--ignore-file` would reproduce Step 4's
`lib/` bug. Worth a one-line `.gitignore` entry or a deliberate real `.gcloudignore` in a later
step; out of scope for Step 7's own DoD.

## Round 1 GPT-PM review: 2 MAJOR

**MAJOR 1** — `aiMachineDescription` is reachable from the real Scan UI (via
`_describeInstead()` on a `noEquipment` classify result) but was not exercised on-device; the
original submission only covered `aiEquipmentRecognition` and `aiCoachAdvice`. GPT-PM correctly
distinguished this from `aiExerciseGeneration`, which has no `lib/` consumer and is therefore not
a reachable product surface today. **Remediated**: see "What was proven" item 5 and the server-log
table above — a real on-device call reached `aiMachineDescription`, verified `app: VALID, auth:
VALID`, and the client correctly handled the real "not nameable" response. The happy-path
(`isGymEquipment: true`, rendered card) branch was attempted but not hit within a reasonable
number of real-device tries; disclosed honestly above rather than silently claimed.

**MAJOR 2** — the unique product-UI evidence (screenshots) was described in prose then deleted
from the device with nothing durable preserved; server logs alone cannot prove the client actually
parsed and rendered the answer (a callable can succeed while a Flutter-side parser/state bug still
shows nothing on screen). **Remediated**: see "Durable UI evidence" above — four screenshots
copied into `core/screenshots/`, with a manifest (`core/evidence/g4_step7_ui_evidence_manifest_2026-08-29.json`)
mapping each to its server-side log entry.

Two INFO notes, no change required: the debug-sign-in-probe approach is acceptable (Google
sign-in cannot be automated through adb, and the probe left zero net diff); `aiExerciseGeneration`
correctly stays out of the Step-7 UI inventory since it has no current `lib/` consumer.

Sent for round 2.

## Status

Round 1: 2 MAJOR, both remediated above. Round 2 GPT-PM review: pending. Next gate step: Step 8
(rollback/disable mechanism for the AI Gateway).
