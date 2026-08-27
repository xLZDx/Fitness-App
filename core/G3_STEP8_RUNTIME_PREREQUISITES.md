# MVP1.G3 Step 8 -- runtime-monitor prerequisites

Rosetta plan `Fitness_App-2026-08-27T01-44-56-612Z-f57b28`
(hash `9f5e9bbd0aeb97b33b3d078dcbc49765bdf88f8569634959e0474879f61dfa09`),
APPROVED by GPT-PM 2026-08-27 with a 12-item binding DoD (see
`core/DECISION_LOG.md`'s Step-8 entry for the full exchange). This document is
the design record for the parts of that DoD that are evidence-and-design work,
not yet the live infrastructure change -- creating and binding the actual
production alert channel is explicitly on HOLD pending the operator's own
confirmation of `DECISION G3-RUNTIME-OWNER` (see bottom of this file).

## 1. Alert destination -- design, not yet created

**Mechanism:** one Cloud Monitoring email notification channel on
`fitness-app-korostelev`, type `email`, pointed at the project owner's Google
account. Additive to the budget's existing default IAM-role recipients per
GPT-PM's correction -- `disableDefaultIamRecipients` stays at its default
(`false`); this is redundancy, not a replacement.

**Verification GPT-PM requires before Step 8.2 counts as DONE:** a temporary,
harmless Cloud Monitoring alerting policy (a condition guaranteed to fire
almost immediately, e.g. "log entry count > -1 in the last minute") is created,
its incident is confirmed to actually produce an email at the recipient, and
the temporary policy is then deleted. Configuration existing is not sufficient
proof by itself -- GCP's own documentation is explicit that a misconfigured
notification channel can fail silently with no separate failure signal.

**Not done yet:** creating the channel and running that verification requires
actually sending mail to a real address and binding production alerting to a
human recipient -- both are the operator's call per `DECISION
G3-RUNTIME-OWNER` below, not something to do on an inferred default.

## 2. Cloud Scheduler -- job-budget evidence (real, not assumed)

GPT-PM corrected the original proposal: Cloud Scheduler's free tier is
**3 jobs/month per BILLING ACCOUNT, not per project** -- additional jobs are
$0.10/job/month. Checked live, 2026-08-27, against every project on this
billing account (`019944-23376A-5C1743`):

| project | Scheduler API enabled | jobs (any region checked) |
|---|---|---|
| `fitness-app-korostelev` | Was No; **enabled 2026-08-27** (`gcloud services enable cloudscheduler.googleapis.com`, per GPT-PM's explicit "Scheduler/API readiness" GO -- reversible, zero cost, does not bind any alert to a human recipient) | 0 |
| `traidingbot-b4061` | No | 0 |
| `trading-bot-496818` | No | 0 |
| `erp-moldova-staging-20260819` | Yes | 0 (checked `us-central1`) |

**Current billing-account-wide Scheduler usage: 0 of 3 free jobs.** GPT-PM's
recommendation -- one consolidated scheduled dispatcher for Step 9's runtime
probes rather than one `onSchedule` function per monitor -- fits inside the
free allowance with headroom for two more jobs elsewhere on this billing
account before any cost is incurred. This replaces the original "free tier is
generous, assumed zero cost" claim GPT-PM flagged as unverified with an actual
number.

## 3. Canary identity -- design (per GPT-PM's amended invariant)

GPT-PM's required shape:

```
synthetic identity -> real Firebase Auth token exchange -> authenticated
Firestore request -> only /_canary/<its-own-id> -> read/write/delete ->
actionable alert on failure
```

Two hard constraints from the review: the canary must not use the Admin SDK
for the Firestore read/write if the report will claim it proves the
client-facing Auth+Firestore path (Admin SDK bypasses Security Rules
entirely), and the design must inspect this app's ACTUAL production sign-in
providers rather than adding a new one purely because it is easy to automate.

**Actual production sign-in providers (verified against
`mobile/lib/features/auth/data/firebase_auth_repository.dart`):**
- Anonymous (`signInAnonymously`, line 76-78).
- Google Sign-In (`signInWithGoogle` -> `GoogleAuthProvider.credential`, line
  132-143, with anonymous-to-Google account linking via `linkWithCredential`).
- No email/password provider -- the file's own comment (line 183) records
  that this was already checked and confirmed absent.

Google Sign-In is not safely automatable headlessly without storing a real
Google account's credentials somewhere (exactly the "credential stored in
repo/env file" failure GPT-PM's DoD 8.11 forbids). Per GPT-PM's own fallback
("a custom-token exchange can test core Firebase Auth availability, but its
narrower coverage must be recorded"):

**Chosen design:** the canary function (Admin SDK, server-side) mints a
Firebase custom token via `admin.auth().createCustomToken(canaryUid, {canary:
true})` for a single dedicated, fixed UID reserved for this purpose. The
canary CLIENT step -- the part that must prove the real path -- then calls
the Firebase Auth **Client SDK's** `signInWithCustomToken()` with that token
to obtain a genuine ID token issued through the real Firebase Auth token
exchange, and uses that authenticated client session (not the Admin SDK) to
read/write/delete `/_canary/<canaryUid>`. This is Firebase's own documented
mechanism for a server-provisioned service/test identity -- it is not a new
sign-in provider in the Console/App sense, and it correctly separates
"provision an identity" (Admin SDK, server-side, no Security Rules bypass
claim) from "prove the client path" (Client SDK, real Security Rules
enforcement).

**Honest scope statement, required by GPT-PM's DoD 8.6/8.7:** this design
proves Firebase Auth token issuance/validation and Firestore Security Rules
enforcement for an authenticated identity. It does **not** exercise the
Google Sign-In OAuth flow specifically -- that remains unmonitored by this
canary, and this document records that gap rather than silently claiming full
sign-in coverage.

**Firestore isolation:** Security Rules must require BOTH request
`auth.uid == canaryUid` AND the custom claim `request.auth.token.canary ==
true` (not UID possession alone -- GPT-PM's explicit requirement), scoped to
`/_canary/{docId}` only, with no rule anywhere in the ruleset granting that UID
or that claim access to any real user-data collection. Positive proof (canary
can read/write/delete its own `_canary/` doc) and negative proof (same
identity denied on a real user-data path, e.g. `/users/{anyId}`) are both
required before this counts as built, per DoD 8.8 -- not yet implemented,
this section is the design GPT-PM reviews before Step 9 builds against it.

**Synthetic-data hygiene (DoD 8.9):** canary documents live only under
`_canary/`, a namespace prefix already outside every real per-user or
per-workout collection path in this schema, and are deleted by the canary run
itself immediately after use (read-write-delete in one pass, not a lingering
write). Any future data-lifecycle/export/deletion monitor (Step 9) must
explicitly exclude the `_canary/` collection from its counts so synthetic
writes cannot be mistaken for real user data.

## 4. App Check -- truthful scope (DoD 8.7)

If App Check enforcement is active on the callables/paths this canary
exercises, the canary's server-side step can mint a synthetic App Check token
via Admin SDK's `appCheck().createToken(appId)`. Per GPT-PM's correction, this
proves **enforcement/token acceptance only** -- it does not exercise real
Android/Play Integrity device attestation, since that path only exists on a
genuine client device. Any future report citing this canary must state that
distinction explicitly rather than imply full App Check health coverage.

## 5. DECISION G3-RUNTIME-OWNER -- pending operator confirmation

GPT-PM's ruling, verbatim: *"This does require direct operator confirmation,
because our previously agreed escalation policy explicitly classifies a human
on-call/notification obligation as a real ownership decision rather than
something an agent may infer."*

**Decision text, as GPT-PM framed it:**
> The operator accepts responsibility as the primary alert owner/on-call
> recipient for MVP1.G3 runtime alerts, using the project-owner Google account
> as the primary email notification destination, until explicitly changed.

**Status: PENDING.** Not yet answered by the operator as of this writing.
Per GPT-PM's authority ruling: Step 8's design/investigation/reversible
infrastructure-prep work may continue without it (this document is exactly
that work), but Step 8 cannot be marked fully DONE, and no production alert
policy may be bound to a human recipient, until this is explicitly confirmed.
