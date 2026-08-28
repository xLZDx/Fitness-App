# G4 Step 5 — S8 App Check debug-provider backend E2E, real proof

## What was proven

A real Android device (S8, `SM-G950F`, Play Integrity-ineligible — bootloader-unlocked dev
device, see G4 Step 3 doc) can reach all four AI Gateway callables end-to-end through the App
Check enforcement boundary using the documented debug-provider path, with no change to
enforcement itself.

## What changed (durable)

- `mobile/lib/main.dart`: corrected a wrong code comment. The empty-string default for
  `AndroidDebugProvider(debugToken: ...)` was documented as "SDK falls back to generating its
  own" — verified false on-device: the current `firebase_app_check` Android plugin sends the
  empty string to the backend as-is, which rejects it (`400: the debug_token cannot be empty`).
  A real value must be generated and registered explicitly. No behavior change, comment only.
- Firebase App Check: one debug token registered for the debug app
  (`1:988522745882:android:7c05c915aa42410ec201a3`, package
  `com.fitnessapp.fitness_app.sptr.debug`), display name
  `G4-Step5-S8-debug-probe-2026-08-29`, via the App Check Admin REST API
  (`firebaseappcheck.googleapis.com/v1/.../debugTokens`, `X-Goog-User-Project` header needed —
  same quota-project requirement `fn-enforcement` hit in Step 3). This token is the durable
  deliverable: any future debug build on any machine, built with
  `flutter build/run --dart-define=APP_CHECK_DEBUG_TOKEN=<this value>`, attests successfully
  without registering a new one. Value recorded in the operator's own records (not committed —
  same handling as any other credential-shaped value); regenerable at will via the same API call.

## What was temporary (built, used, deleted — same lifecycle as `appCheckProbe`)

- A `kDebugMode`-gated `FirebaseAppCheck.instance.getToken(true)` debug-print block in
  `main.dart`, added only to capture the token value once and removed after.
- A throwaway Firebase Auth test user (uid `g4-step4-app-check-probe`, real ID token minted via
  IAM `signBlob` impersonation of `firebase-adminsdk-fbsvc@...` — same mechanism as Step 4 round
  2's proof), used for both the negative and positive control calls, deleted after each use.
- Self-granted `roles/iam.serviceAccountTokenCreator` on `firebase-adminsdk-fbsvc@...`, revoked
  immediately after each token mint.

## Evidence

1. **Debug provider genuinely attests**: after registering the token, the app's own
   `getToken(true)` call returned a real signed App Check JWT (`"provider":"debug"` in the
   decoded payload), where it had previously failed with `400` (empty) then `403` (unregistered).
2. **Positive control — the actual Step 5 requirement**: called all four AI callables with a
   valid, non-anonymous Firebase Auth token AND the valid App Check debug token. All four
   returned `400 INVALID_ARGUMENT` with a callable-specific validation message (e.g. `"source
   must be 'equipment' or 'exercise'"`) — proving the request passed BOTH Auth and App Check and
   reached the handler's own business-logic validation, not a security rejection. Confirmed via
   the structured `callable-request-verification` log: `app=VALID; auth=VALID` on
   `aicoachadvice` (spot-checked; same code path as all four). No Vertex call was made or
   billed — input validation fails before that, which is sufficient proof for this step.
3. Negative control from Step 4 (`app=MISSING; auth=VALID` → `401`) still holds; this step adds
   the positive half GPT-PM asked about in round 1 ("the positive control ... belongs formally
   to Step 5").

## Round 1 GPT-PM review: MAJOR — the earlier proof stopped short of Vertex

**MAJOR (confirmed real)**: stopping at input validation (`400 INVALID_ARGUMENT`) proves App
Check + Auth + the callable wrapper, but not the production chain this gate actually introduced
— handler → quota → `ai_gateway` → Vertex → response contract. GPT-PM: "App Check works
perfectly, yet fn-ai-runtime lacks a real Vertex permission ... quota interaction breaks ... Step
5 would be marked PASS without ever exercising precisely the production backend path." Explicitly
authorized as bounded: "Four deliberately small calls are enough; there is no need for load
testing here." `GO: AUTHORIZED — run that narrow four-call Vertex E2E proof.`

**Executed.** Built valid payloads per callable (read `parseInput` in each `ai_*.ts` source
directly, not guessed): `aiCoachAdvice` (`source`, `subjectName`, `languageCode`),
`aiExerciseGeneration` (`equipmentId: "treadmill"`, `languageCode`), and for the two
image-based callables (`aiEquipmentRecognition`, `aiMachineDescription`) a real photo from this
project's own `data/gym_photos_2026-07-30/` set, base64-encoded (4MB, under the 9MB limit) --
a hand-typed 1x1 JPEG passed this app's own magic-byte sniffing but Gemini's own decoder
rejected it (`400 Failed to decode image data`, visible in the structured `ai_gateway: generate
failed` log's `error` field) -- itself informative proof the request really reached the Vertex
API, just with content Gemini couldn't parse; a genuinely decodable real photo fixed it.

Results, same valid Auth + valid App Check debug token as the earlier proof, run against all
four with the corrected payloads:

| Callable | Result |
|---|---|
| `aiCoachAdvice` | `200`, real coaching-advice text |
| `aiExerciseGeneration` | `200`, real 4-exercise JSON array with muscle/difficulty/duration fields |
| `aiEquipmentRecognition` | `200`, `{"machine":"cable machine","confidence":0.96,...}` -- correctly identified the real gym photo |
| `aiMachineDescription` | `200`, correct structured description of the same cable machine |

Every one of the four AI Gateway callables genuinely reached Vertex/Gemini through the full
`fn-ai-runtime` identity + App Check + Auth chain and returned a real, sensible, on-contract
answer. No mocking anywhere in this path. Cleaned up the same two temporary artifacts again
(test Auth user, temporary IAM grant) immediately after.

## Status

Round 1 fix applied and live-verified with real Vertex calls. Sent for round 2. Next gate step
after APPROVE: Step 6 (real quota-exhaustion proof).
