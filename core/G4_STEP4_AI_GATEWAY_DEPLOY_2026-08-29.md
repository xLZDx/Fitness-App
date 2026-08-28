# G4 Step 4 — AI Gateway callables deployed with App Check enforced from first live revision

Full narrative: `core/DECISION_LOG.md`, section "G4 Step 4: AI Gateway callables deployed, App
Check enforced from first live revision" (2026-08-29). This file is the compact evidence table
GPT-PM review references.

## What changed

- `functions/src/scaling.ts`: `AI_METERED.serviceAccount = RUNTIME_SA.aiRuntime`.
- Deployed (first-ever live revision) via `firebase deploy --only functions:aiCoachAdvice,
  functions:aiEquipmentRecognition,functions:aiMachineDescription,functions:aiExerciseGeneration`.
- `APP_CHECK_ENFORCED_AI=true` applied via `gcloud functions deploy --update-env-vars` (not
  `.env` — blocked by sandbox permissions; alternative is documented in `scaling.ts`'s own header).

## Regression found and fixed (not part of this step's own scope, caused by Step 3's closure)

Default Compute SA (`988522745882-compute@developer.gserviceaccount.com`) had `roles/editor`
stripped as part of closing Step 3. GCF gen2 builds run under that SA and need
`roles/cloudbuild.builds.builder` specifically — build failed for all four functions until that
one role was restored. Confirmed via Google's own troubleshooting doc. No other role restored;
default Compute SA still holds nothing else.

## Verification (live, not just deploy success)

| Function | Identity | `APP_CHECK_ENFORCED_AI` | Unauthenticated call |
|---|---|---|---|
| aiCoachAdvice | fn-ai-runtime@... | true | HTTP 403 |
| aiEquipmentRecognition | fn-ai-runtime@... | true | HTTP 403 |
| aiMachineDescription | fn-ai-runtime@... | true | HTTP 403 |
| aiExerciseGeneration | fn-ai-runtime@... | true | HTTP 403 |

## Known, disclosed deviation

Each function's very first revision (the `firebase deploy` one, before the `gcloud
--update-env-vars` follow-up landed ~1-2 min later) ran without `APP_CHECK_ENFORCED_AI=true`.
No real users exist and no URL was ever distributed, so real-world exposure is zero
(`project-fitness-app-no-real-users-yet` applies) — recorded as a minor deviation from "enforced
from the very first revision," not hidden.

## Round 1 GPT-PM review: MAJOR — 2 MAJOR, 2 MINOR, all fixed

1. **MAJOR (confirmed real)**: the HTTP 403 did not prove App Check enforcement — it could be
   Cloud Run IAM blocking before the function ever ran. Verified against real state:
   `gcloud run services get-iam-policy aicoachadvice` returned an EMPTY policy (no `allUsers`
   invoker), while an existing working callable (`startfreetrial`) has `allUsers: roles/run.invoker`.
   The four new AI services never got the public-invoker grant `firebase deploy` normally applies.
   **Fixed**: `gcloud run services add-iam-policy-binding <svc> --member=allUsers
   --role=roles/run.invoker` for all four. Re-tested: response changed from a bodiless Cloud Run
   `403` to a Firebase-callable-shaped `401 {"error":{"message":"Unauthenticated","status":
   "UNAUTHENTICATED"}}` — proves the request now actually reaches the callable wrapper.
   **Chronology matters and resolves this cleanly**: the invoker grant was applied *after*
   `APP_CHECK_ENFORCED_AI=true` was already live (see decision log) — there was never a moment
   these functions were both publicly reachable and unenforced.
2. **MAJOR (confirmed real)**: `APP_CHECK_ENFORCED_AI` only existed as live, mutable Cloud Run
   state; the source's own `envFlag` still defaulted an absent/typoed var to `false` (fail-open),
   so a future clean `firebase deploy` (no `.env`, no manual `gcloud --update-env-vars` follow-up)
   would silently redeploy the AI callables unenforced. **Fixed**: added `envFlagFailClosed` in
   `scaling.ts` (enforced unless the var is the literal string `"false"`) and switched
   `APP_CHECK_ENFORCED_AI` to it. Two new tests in `scaling.test.ts` prove: (a) unset or any typo
   (`"1"`, `"TRUE"`, `"yes"`, `""`, `"0"`) still enforces; (b) explicit `"false"` still disables
   for deliberate rollback. Rebuilt and redeployed all four functions with the fix; live readback
   confirms identity/env var/invoker policy survived and unauthenticated calls still return 401.
3. **MINOR**: "zero exposure" during the brief unenforced-first-revision window was stated more
   strongly than the evidence supported. **Resolved by the chronology fact above**, not a log
   query — the functions were never both public and unenforced at the same time, so exposure was
   actually zero for a stronger, verifiable reason than "no real users."
4. **MINOR**: reviewer misread `functions/.gcloudignore` (an untracked, gcloud-auto-generated
   scratch file, never `git add`ed) as part of the committed diff. Verified via
   `git diff --cached --stat` — it was never staged. No fix needed; noted as a correction.

## Round 2 GPT-PM review: MAJOR — 1 MAJOR (round 1's MAJOR #2 confirmed closed)

**MAJOR (confirmed real, and a sharper point than round 1)**: the 401 `UNAUTHENTICATED` response
does not by itself prove App Check ran — these callables' own handlers throw
`HttpsError("unauthenticated", ...)` whenever `request.auth` is missing, *regardless* of App
Check status. A request with no Auth token and no App Check token produces the identical 401
whether enforcement is on or off. Required proof: a request with a **valid, non-anonymous Firebase
Auth token** and **no App Check header** — if App Check is genuinely enforcing, that still gets
rejected (Auth passes, App Check fails); if it silently is not, the request would instead reach
the handler and fail differently (or succeed).

**Executed exactly as specified**, no shortcuts:
1. Minted a real Firebase ID token for a throwaway test uid via IAM `signBlob` impersonation of
   `firebase-adminsdk-fbsvc@...` (self-granted `roles/iam.serviceAccountTokenCreator` temporarily,
   revoked immediately after) + `identitytoolkit.googleapis.com:signInWithCustomToken`.
2. Called all four AI callables with `Authorization: Bearer <token>`, no App Check header.
3. All four returned `401 UNAUTHENTICATED` again — but this time read the actual structured
   Cloud Logging entry (`firebase-log-type: callable-request-verification`) instead of trusting
   the HTTP response alone: **`"verifications": {"app": "MISSING", "auth": "VALID"}`** on all
   four (`aicoachadvice`, `aiequipmentrecognition`, `aimachinedescription`,
   `aiexercisegeneration`). Auth genuinely passed; the rejection is genuinely App Check.
4. Cleaned up both temporary artifacts: deleted the throwaway test Auth user
   (`identitytoolkit.googleapis.com:accounts:delete`), revoked the temporary IAM grant.

This closes round 2's MAJOR with the exact evidence GPT-PM specified, not a weaker substitute.

## Status

All findings across 2 rounds resolved and independently verified. Sent for round 3
confirmation. Next gate step after APPROVE: Step 5 (S8 App Check debug-token backend E2E),
then commit + push under CLAUDE.md §20 on a genuine correlated APPROVE.
