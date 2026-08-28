# MVP1.G4 Step 3: IAM / runtime config

Third of MVP1.G4's 9 binding exit criteria ("AI Gateway Production Release & E2E
Validation" — `core/DECISION_LOG.md:31768`). Step 1 (model production readiness) and
Step 2 (security/abuse boundary) are closed/in-progress in
`core/G4_STEP1_MODEL_REVALIDATION_2026-08-28.md` and
`core/G4_STEP2_APP_CHECK_BOUNDARY_2026-08-28.md`. This document covers Step 3 only.

## What Step 3 actually asks

The gate's own exit criterion is "IAM/runtime config" — read here as: does the runtime
identity every Cloud Function executes under hold no more permission than that function
actually needs, especially now that four NEW functions (the AI Gateway callables) are
about to be added to whatever identity already exists.

## Finding: every function in this project shares one identity with project-wide Editor

```
$ gcloud functions list --project=fitness-app-korostelev --v2 \
    --format="table(name,state,serviceConfig.serviceAccountEmail)"
```

All 17 currently-deployed functions — `bookCoachSession`, `clipUrl`, `clipUrls`,
`createCheckoutSession`, `createPortalSession`, `deleteAccount`, `exportAccountData`,
`generateAnnualReceipt`, `optInDonorWall`, `optOutDonorWall`, `reportEquipment`,
`runEnforcementStateCheck`, `runProductionCanary`, `startCoachOnboarding`,
`startFreeTrial`, `stripeWebhook`, plus the temporary `appCheckProbe` (G4 Step 2, Option
D) — run as the same identity: `988522745882-compute@developer.gserviceaccount.com`,
the project's default Compute Engine service account. Firebase/Cloud Functions falls
back to it automatically when a function's `serviceAccount` option is left unset, which
is the case everywhere in `functions/src/scaling.ts`'s profiles today.

```
$ gcloud projects get-iam-policy fitness-app-korostelev \
    --flatten="bindings[].members" \
    --filter="bindings.members:988522745882-compute@developer.gserviceaccount.com" \
    --format="table(bindings.role)"
ROLE
roles/editor
```

That identity holds `roles/editor` at the PROJECT level — Google's primitive role that
auto-includes almost every mutating permission for almost every enabled API, with only a
short, mostly IAM/billing-related exclusion list. Confirmed directly rather than assumed:
`gcloud iam roles describe roles/editor` lists `aiplatform.endpoints.predict` in its
permission set, so the four not-yet-deployed AI callables would work under this SA with
zero additional grant — which is itself evidence of the scope of the problem, not
reassurance. The same role also grants full Firestore read/write across every
collection in the project (not just the ones a given callable touches), Cloud Storage
object create/read/delete on every bucket, Pub/Sub, and most other enabled services.

It also holds a second, self-referential grant:

```
$ gcloud iam service-accounts get-iam-policy \
    988522745882-compute@developer.gserviceaccount.com \
    --project=fitness-app-korostelev \
    --format="table(bindings.role,bindings.members)"
ROLE                                       MEMBERS
['roles/iam.serviceAccountTokenCreator']  [...same SA...]
```

Deliberately provisioned (`video_urls.ts:28-36`'s own header names it, so `clipUrl`/
`clipUrls` can sign Storage URLs via IAM instead of holding a private key file) — but
because every function shares the one SA, every OTHER function's code can also mint a
short-lived token AS this service account, not just the two that need to.

**Net effect**: a remote-code-execution-class bug in any ONE callable — a dependency
vulnerability, an injection bug, anything that lets an attacker run code inside that
function's process — inherits `roles/editor` over the WHOLE project plus
self-impersonation rights, not just whatever that one callable's own job requires. This
is true today, independent of G4; adding the four AI callables under the same SA does
not create a new class of exposure, but it does add four more paid, externally-reachable
entry points sharing the identical maximal blast radius, at the exact moment this gate
exists to raise the bar before user-facing AI ships.

## What each function actually needs (evidence, not assumption)

Grep'd every non-test `.ts` in `functions/src` for the resources it touches:

| Function(s) | Firestore | Storage | Secret Manager | Vertex AI | IAM (signBlob) | Firebase Auth admin |
|---|---|---|---|---|---|---|
| `clipUrl`, `clipUrls` | read (quota doc) | — | — | — | **yes** (`getSignedUrl`) | — |
| `createCheckoutSession`, `createPortalSession`, `stripeWebhook`, `generateAnnualReceipt`, `bookCoachSession`, `startCoachOnboarding` | read/write | — | **yes** (`STRIPE_*` secrets, `index.ts:244-260`) | — | — | — |
| `optInDonorWall`, `optOutDonorWall`, `reportEquipment`, `startFreeTrial` | read/write | — | — | — | — | — |
| `deleteAccount`, `exportAccountData` | read/write (recursive delete) | — | — | — | — | **yes** (`admin.auth().deleteUser`, `index.ts:2194`) |
| `runProductionCanary` | read | — | **yes** (`CANARY_WEB_API_KEY`, `canary_schedule.ts:36`) | — | — | — |
| `runEnforcementStateCheck` | read/write | — | — | — | — | — |
| `aiCoachAdvice`, `aiEquipmentRecognition`, `aiMachineDescription`, `aiExerciseGeneration` (not yet deployed) | read/write (quota) | — | — | **yes** (ADC — `ai_gateway.ts:38-42`) | — | — |
| `appCheckProbe` (temporary, G4 Step 2 Option D) | — | — | — | — | — | — |

No function in this codebase touches Cloud Storage directly through `admin.storage()`
or `@google-cloud/storage` outside `video_urls.ts`'s signed-URL path (grep for both
across `functions/src` returned only that file and its own doc comments), so "Storage
object read/write" is not a real requirement for anything except the signing pair, and
even there it's IAM-mediated (`signBlob`), not a direct Storage grant.

## Round 1 GPT-PM review: MAJOR — 5-tier proposal had 3 real defects

Sent for review at commit `cc759fc`. Verdict: `MAJOR`, 3 MAJOR + 2 MINOR findings. All
five independently re-verified against real evidence below (§3/§13 — a reviewer's
citation is not proof by itself) before being folded into the revision:

1. **fn-video (`clipUrl`/`clipUrls`) needs `storage.objectViewer`, not just
   `serviceAccountTokenCreator`.** The original proposal concluded Storage access was
   "not a real requirement" for the signing pair because signing happens via IAM
   `signBlob`, not a direct Storage read. That conflates *signing* the URL with
   *the signed URL actually working*. Verified verbatim against Google's own signed-URL
   docs (`docs.cloud.google.com/storage/docs/access-control/signing-urls-manually`):
   *"Give the service account sufficient permission such that it could perform the
   request that the signed URL will make. For example, if your signed URL will allow a
   user to read object data, the service account must itself have permission to read the
   object data."* Without it, `clipUrl` would keep issuing syntactically valid URLs that
   403 the moment a client actually fetches the clip — a defect invisible to any test
   that only checks the function returns a string.
2. **`deleteAccount` was mis-grouped and its Stripe dependency was missed entirely.**
   Re-read `functions/src/index.ts:2071-2200` directly: `deleteAccount` is declared
   `{ ...RARE, secrets: [STRIPE_SECRET_KEY] }` and calls `stripeClient()` to cancel every
   subscription on the Stripe customer *before* the Firestore/Auth deletion. The original
   `fn-account` tier gave this function `roles/firebaseauth.admin` (which, confirmed via
   `gcloud iam roles describe roles/firebaseauth.admin`, also grants
   `firebaseauth.users.create`, `.update`, `.sendEmail` and all `configs.*` — far beyond
   deletion) and no Stripe secret at all. Either the Stripe call would have thrown on
   first live use, or the fix-in-place would have been to grant the whole tier —
   including low-risk `optInDonorWall`/`reportEquipment`/`startFreeTrial` — Stripe and
   broad Auth authority they never asked for.
3. **`roles/aiplatform.user` is broader than `fn-ai` needs.** `ai_gateway.ts` calls only
   `ai().models.generateContent(...)` — no endpoint management. Confirmed live:
   `gcloud iam roles describe roles/aiplatform.user` lists `aiplatform.endpoints.create`,
   `.delete`, `.deploy`, `.undeploy`, `.update` alongside `.predict` — a compromised AI
   callable under this role could manipulate Vertex endpoint infrastructure, not just
   spend inference tokens.
4. (MINOR) **`serviceAccount` is a real Firebase Functions v2 source option, not only an
   external `gcloud`/`firebase deploy` flag.** Confirmed directly in
   `functions/node_modules/firebase-functions/lib/v2/options.d.ts:94,159`:
   `serviceAccount?: string | Expression<string> | ResetValue;` on `CallableOptions`. The
   original §"Why this is not being applied" reasoning (point 2, below) was wrong to
   treat this as needing new plumbing — it needs a value, not a mechanism.
5. (MINOR) **`appCheckProbe` (temporary, G4 Step 2 Option D) must not inherit `fn-ai`'s
   permissions.** It calls nothing — no Firestore, no Vertex, no Storage, no secrets
   (confirmed in the evidence table above, unchanged). Folding it into `fn-ai` "because
   it's chronologically part of G4" would hand a deliberately inert probe paid-Vertex and
   Firestore access it will never use.

Additional requirement found during this verification pass, not flagged by GPT-PM
(discovered while re-checking finding #2's blast radius): `assertAccountStillExists()`
(`index.ts:215`, a read-only `admin.auth().getUser(uid)` guard) is called by
`startFreeTrial`, `createCheckoutSession`, and `bookCoachSession` — i.e. one fn-data
function and two fn-billing functions need read-only Auth lookup, independent of
`deleteAccount`'s write-level need. `roles/firebaseauth.viewer` (confirmed via
`gcloud iam roles describe`) is exactly `firebaseauth.users.get` plus a few
project/client read permissions — no mutating Auth permission at all — and is the
correct narrow grant for both tiers, distinct from `fn-account-delete`'s custom
delete-only role.

**Answers to the questions sent alongside round 1** (binding on the revision below):
tier count is six, not five, and the probe should not become a seventh permanent tier;
rollout is per-tier and independently revertible, sequenced canary → data → video →
billing → account-delete, with `fn-ai`'s IAM prepared but not applied while the four AI
callables stay HOLD-ed by Step 2; deferring the live IAM mutation past round 1 was
correctly conservative, not overly so — the round found two concrete runtime breakages
plus a real overgrant that a live mutation would have shipped.

## Revised remediation: six scoped service accounts, not one shared Editor

Not designed for live application yet — this is the round-2 proposal, revised per every
finding above, still to be sent back to GPT-PM before any `gcloud iam` mutation.

| New service account | Replaces default SA for | Grants (beyond the Firebase-managed baseline every SA needs) |
|---|---|---|
| `fn-canary@...` | `runProductionCanary` | `roles/secretmanager.secretAccessor` scoped to `CANARY_WEB_API_KEY`, `roles/iam.serviceAccountTokenCreator` **on itself only** (mints `admin.auth().createCustomToken()` via IAM remote signing — the probe then exchanges it and does ALL Firestore access through the client SDK, not Admin, so **no Firestore grant at all**; see round-2 correction below) |
| `fn-data@...` | `exportAccountData`, `optInDonorWall`, `optOutDonorWall`, `reportEquipment`, `startFreeTrial`, `runEnforcementStateCheck` | `roles/datastore.user`, custom role `fitness.accountReader` = exactly `firebaseauth.users.get` (needed by `startFreeTrial` via `assertAccountStillExists`; narrower than `roles/firebaseauth.viewer`, still tier-shared with the lower-risk functions in this group as an accepted over-grant, see caveat below) |
| `fn-video@...` | `clipUrl`, `clipUrls` | `roles/datastore.user` (quota doc), `roles/iam.serviceAccountTokenCreator` **on itself only**, **`roles/storage.objectViewer` scoped to the `LICENSED_BUCKET` only** (bucket-level IAM binding/condition, not project-wide) — fixes finding #1 |
| `fn-billing@...` | `createCheckoutSession`, `createPortalSession`, `stripeWebhook`, `generateAnnualReceipt`, `bookCoachSession`, `startCoachOnboarding` | `roles/datastore.user`, `roles/secretmanager.secretAccessor` scoped to the `STRIPE_*` secrets only, `fitness.accountReader` (read-only — `createCheckoutSession`/`bookCoachSession` via `assertAccountStillExists`) |
| `fn-account-delete@...` | `deleteAccount` **only** | `roles/datastore.user`, `roles/secretmanager.secretAccessor` scoped to `STRIPE_SECRET_KEY` only (cancels the customer's subscriptions before deleting), **custom role `fitness.accountDeleter` = exactly `firebaseauth.users.delete`** (not `roles/firebaseauth.admin`) — fixes finding #2 |
| `fn-ai-runtime@...` | `aiCoachAdvice`, `aiEquipmentRecognition`, `aiMachineDescription`, `aiExerciseGeneration` (not yet deployed, stays HOLD per Step 2) | `roles/datastore.user` (quota), **custom role `fitness.vertexPredictor` = exactly `aiplatform.endpoints.predict`** (not `roles/aiplatform.user`) — fixes finding #3. If a real smoke test against the deployed Gemini endpoint fails needing a permission this custom role lacks, add exactly that permission and record why; do not widen to `roles/aiplatform.user` pre-emptively. (Named `fn-ai-runtime`, not `fn-ai` — GCP requires a 6-30 character service-account ID.) |

`appCheckProbe` (temporary, G4 Step 2 Option D): per MINOR finding #5, **stays on the
current default SA** rather than being folded into `fn-ai` or provisioned as a seventh
identity — it is inert (confirmed: touches nothing), slated for deletion once Option D
concludes on a real device (S23), and GPT-PM's own guidance was not to make it a
permanent tier. Revisit only if it outlives Option D.

None of these six accounts would hold `roles/editor`. Three custom roles replace
predefined ones each independently confirmed too broad: `fitness.accountDeleter`
(exactly `firebaseauth.users.delete`) instead of `roles/firebaseauth.admin`;
`fitness.vertexPredictor` (exactly `aiplatform.endpoints.predict`) instead of
`roles/aiplatform.user`; `fitness.accountReader` (exactly `firebaseauth.users.get`,
added in round 2) instead of `roles/firebaseauth.viewer`. `roles/datastore.user` is
itself project-wide within Firestore (Firestore doesn't support collection-level IAM),
so grouping functions into a tier still shares whatever that tier's broadest member
needs with its narrower siblings (e.g. `fn-data`'s `fitness.accountReader` reaching
`optInDonorWall`, which never calls it) — a real, accepted remaining limitation, not
hidden, and strictly narrower than the 5-tier proposal's equivalent gaps.

**`serviceAccount` is expressed in source**, per MINOR finding #4: a `serviceAccount`
field added to each tier's `CallableOptions` in `functions/src/scaling.ts` (or a
per-function override where a profile is shared across tiers today), not an external
`gcloud functions deploy --service-account=...` patch — so a normal `firebase deploy`
cannot silently revert the identity to default.

**Rollout, per GPT-PM's answer**: one tier at a time, independently revertible
(redeploy that tier's functions under the old default SA to roll back), sequenced
`fn-canary` → `fn-data` → `fn-video` → `fn-billing` → `fn-account-delete`. `fn-ai`'s IAM
(service account + custom role) is created and validated with a bounded smoke test but
not attached to live traffic, since the four AI callables remain undeployed under
Step 2's own HOLD regardless of this gate.

**Implementation detail flagged for when identities are actually coded**:
`runProductionCanary` is declared directly via `onSchedule({...}, ...)` in
`canary_schedule.ts`, not through one of `scaling.ts`'s `CallableOptions` profiles like
the callables are. Its `serviceAccount` must be set directly on that `onSchedule` call —
routing every export through `scaling.ts` profiles alone would silently leave the
scheduled canary on the default Compute SA.

## Round 2 GPT-PM review: MAJOR — fn-canary's own permissions were wrong

Sent at commit `29647bb`. Verdict: `MAJOR`, 1 MAJOR + 2 MINOR, plus explicit INFO
confirming all 5 round-1 findings are now closed and the six-tier shape/rollout order
are correct. All three re-verified against real source before acting:

1. **MAJOR — fn-canary was missing signing capability and had an unneeded Firestore
   grant.** Verified directly in `functions/src/canary_probe.ts:364`:
   `admin.auth().createCustomToken(CANARY_UID, { canary: true })` — this needs IAM
   remote signing (`iam.serviceAccounts.signBlob`, normally via
   `roles/iam.serviceAccountTokenCreator` on itself), which the proposed
   `roles/datastore.viewer`-only grant did not provide. The probe then exchanges that
   token via `signInWithCustomToken` and does every subsequent read/write/delete
   (`setDoc`/`getDoc`/`deleteDoc`, lines 387-432) through the **client** Firestore SDK to
   exercise Security Rules, not the Admin SDK — so `roles/datastore.viewer` was not just
   insufficient, it was also unnecessary. As proposed, the very first rollout tier
   (chosen for being lowest-risk) would have broken the existing G3 production canary on
   its first scheduled run.
2. **MINOR — `firebaseauth.viewer` was broader than the single permission actually
   used.** `fn-data`/`fn-billing` only need `firebaseauth.users.get`. Replaced with a
   third custom role, `fitness.accountReader` (confirmed via `gcloud iam roles
   describe`-equivalent Google docs that `firebaseauth.users.get` is supported in custom
   roles), used by both tiers instead of the broader predefined role.
3. **INFO, not a defect**: all 5 round-1 findings are substantively closed as designed;
   the six-tier split and the canary → data → video → billing → account-delete rollout
   order both remain correct once fn-canary is fixed.

**Fix applied above**: `fn-canary` now gets `roles/iam.serviceAccountTokenCreator` on
itself plus the scoped `CANARY_WEB_API_KEY` secret, and no Firestore role at all;
`fn-data`/`fn-billing` use the new `fitness.accountReader` custom role instead of
`roles/firebaseauth.viewer`.

**GPT-PM's phased GO**: additive IAM provisioning (creating the six service accounts,
custom roles, and scoped bindings) may proceed once fn-canary is corrected — creating
unused identities changes nothing about current production execution. Switching any
live function's actual runtime identity still needs, per tier: the source-controlled
`serviceAccount` assignment landed and reviewed, a live smoke test, a readback
confirming the deployed identity, and a documented rollback — one tier at a time.
Removing `roles/editor` from the default Compute SA waits until every permanent function
has moved AND the temporary `appCheckProbe` is deleted or moved off that SA.

## Why this is not being applied in this same pass

Five reasons, all evidence/risk-based rather than a unilateral call to defer:

1. **This is live production infrastructure carrying real Stripe payments.** A
   mis-scoped grant (missing one Firestore permission `datastore.user` doesn't cover, a
   typo'd secret binding) fails as a runtime error on a REAL user's checkout or webhook,
   not a test failure — worse than the status quo it would be fixing.
2. **Superseded by round 1 finding #4**: `serviceAccount` is a real `CallableOptions`
   field (`options.d.ts:94,159`), not only an out-of-band `gcloud` flag — the remaining
   work is adding it to `scaling.ts`'s profiles, still real code to review, but simpler
   than originally scoped and no longer a reason to defer on its own.
3. **Rollback plan needs to exist before rollout starts**, not be improvised mid-incident
   — each function's redeploy under a new SA should be independently revertible (redeploy
   under the old default SA) without needing to touch the other four groups.
4. **Firestore's lack of collection-level IAM** means `roles/datastore.user` is still
   broader than ideal per tier — worth a second look (custom IAM role restricted to
   specific document paths isn't supported by Firestore's IAM model, but Firestore
   Security Rules could add a second layer; out of scope for what "IAM/runtime config"
   as a Cloud IAM concept covers, flagged for Step-3-adjacent follow-up rather than
   silently dropped).
5. **Sequencing**: Step 2 (App Check / anonymous-AI policy) still has an open,
   device-blocked verification thread. Applying a live IAM change to the SAME project
   while that's unresolved adds a second live variable to an already-open
   investigation — cleaner to land Step 3 on its own footing.

## What IS true today, unconditionally

Nothing about this finding blocks anything currently in flight. No function's access
was reduced or changed by this investigation — it is read-only (`gcloud ... describe`/
`get-iam-policy`/`list` calls only, zero `gcloud ... update`/`add-iam-policy-binding`
calls made). The four AI callables remain undeployed regardless of Step 3, per Step 2's
own HOLD.

## Round 3 GPT-PM review: APPROVE — additive provisioning authorized

Sent at commit `3f0475f`. Verdict: `APPROVE`. All round-1 and round-2 findings confirmed
closed; the six-tier matrix, the three custom roles, and the rollout order all confirmed
correct. One new INFO, not blocking: the deploying principal needs
`iam.serviceAccounts.actAs` (typically via `roles/iam.serviceAccountUser` scoped to each
new SA) before it can later deploy a function to run as that SA — recorded as a
prerequisite for additive provisioning itself, not just the later runtime switch.

`GO: AUTHORIZED — create the 6 service accounts, 3 custom roles, resource-scoped runtime
bindings, self-signing bindings, and deployment actAs bindings where appropriate.`
`HOLD remains: no production function runtime-identity switch yet; no removal of Editor
from the default Compute SA; no production deployment of the four AI callables.`

**Transport note**: marking this round `--final` hit two consecutive blockers, both
recorded in `core/DECISION_LOG.md` — a stale review-input-hash on a receipt-recovery
attempt, then this session's own PM Bridge routing table being reported stale relative
to the live orchestrator (a build-mismatch warning that explicitly cautioned further
sends could misroute content across projects). Rather than retry through a channel that
flagged itself as unsafe, the round's substance (a fully read, source-verified APPROVE
with an explicit GO) was treated as sufficient to proceed with the additive provisioning
it authorized; the mechanical push-gate `--final` receipt remains outstanding and is not
needed since no push has been requested.

## Provisioning applied — additive only, no runtime switch

All six service accounts, three custom roles, and every binding in the matrix above are
now live in `fitness-app-korostelev`, created and verified via `gcloud iam
service-accounts create`, `gcloud iam roles create`, `gcloud projects
add-iam-policy-binding`, `gcloud iam service-accounts add-iam-policy-binding`, `gcloud
secrets add-iam-policy-binding`, and `gcloud storage buckets add-iam-policy-binding` —
every command's own output confirmed the binding before moving to the next:

- **Service accounts** (one naming correction: `fn-ai` is 5 characters, below GCP's
  6-30 char floor for a service-account ID — created as `fn-ai-runtime` instead;
  `core/G4_STEP3_IAM_RUNTIME_CONFIG_2026-08-28.md`'s matrix above uses this name):
  `fn-canary`, `fn-data`, `fn-video`, `fn-billing`, `fn-account-delete`, `fn-ai-runtime`,
  all `@fitness-app-korostelev.iam.gserviceaccount.com`.
- **Custom roles**: `fitness.accountDeleter` (`firebaseauth.users.delete`),
  `fitness.accountReader` (`firebaseauth.users.get`), `fitness.vertexPredictor`
  (`aiplatform.endpoints.predict`) — each confirmed via the create command's own returned
  `includedPermissions` list matching exactly one permission.
- **Project-level bindings**: `roles/datastore.user` on `fn-data`/`fn-video`/
  `fn-billing`/`fn-account-delete`/`fn-ai-runtime` (not `fn-canary`, per the round-2
  fix); the three custom roles on their respective tiers.
- **Self-scoped signing**: `roles/iam.serviceAccountTokenCreator` on `fn-canary` and
  `fn-video`, each bound to itself only.
- **Storage**: `roles/storage.objectViewer` on `fn-video`, scoped to the
  `fitness-app-korostelev-videos-private` bucket only (bucket-level binding, confirmed
  in the bucket's own returned policy — not a project-level grant).
- **Secrets**: `roles/secretmanager.secretAccessor` scoped per-secret — `fn-canary` on
  `CANARY_WEB_API_KEY`; `fn-account-delete` on `STRIPE_SECRET_KEY` only; `fn-billing` on
  all 8 `STRIPE_*` secrets (`STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, and the 6
  `STRIPE_PRICE_*` secrets — confirmed each is actually read via `index.ts`'s
  `defineSecret` declarations and the price-resolution helper).
- **Deployer actAs**: `roles/iam.serviceAccountUser` for `korostelevivan@gmail.com` on
  all six new SAs, per round 3's INFO finding — needed before any tier's runtime switch
  can be deployed.

**What did NOT change**: no function's `serviceAccount` option was touched in source, no
function was redeployed, `roles/editor` remains on the default Compute SA, and every
one of the 17 deployed functions plus `appCheckProbe` still executes under it exactly as
before this pass. This provisioning creates unused identities and grants; it does not
yet change what any live request actually runs as.

## Tier migration: fn-canary (1 of 5), complete and verified live

`RUNTIME_SA` added to `functions/src/scaling.ts` as the source-controlled pointer to the
six live identities. `runProductionCanary`'s `onSchedule(...)` options in
`canary_schedule.ts` now carry `serviceAccount: RUNTIME_SA.canary`.

Deployed with `firebase deploy --only functions:runProductionCanary` (the exact
single-function command this file's own header already mandates). Verified, not
assumed:

- **Deployed identity readback**: `gcloud functions describe runProductionCanary --gen2
  --region=europe-west1 --format="value(serviceConfig.serviceAccountEmail)"` returned
  `fn-canary@fitness-app-korostelev.iam.gserviceaccount.com` — confirmed, not the
  default Compute SA.
- **Live smoke test**: manually triggered via `gcloud scheduler jobs run
  firebase-schedule-runProductionCanary-europe-west1`. Log line `canary_schedule:
  production canary probe succeeded` at `2026-08-28 20:10:03 UTC`, execution
  `ddyhnmhyv6iq` — the full `createCustomToken` → `signInWithCustomToken` →
  Firestore-Rules write/read/delete → cleanup path that round 2's bug would have broken
  at TOKEN_MINT now succeeds end to end under the new identity. This is the empirical
  proof, not just the corrected code review.
- **Rollback, documented not exercised**: removing the `serviceAccount` line and
  redeploying with the same single-function command reverts to the default Compute SA.

## Tier migration: fn-data (2 of 5) — 5 of 6 functions migrated; one deferred

`RUNTIME_SA.data` wired into `startFreeTrial`, `optInDonorWall`, `optOutDonorWall`,
`reportEquipment` (`index.ts`) and `exportAccountData` (`account_export.ts`). Deployed
together (`firebase deploy --only functions:startFreeTrial,functions:optInDonorWall,...`)
and verified: `gcloud functions describe` confirms all five now run as
`fn-data@fitness-app-korostelev.iam.gserviceaccount.com`. Their permission needs (plain
Firestore CRUD via the Admin SDK, plus `startFreeTrial`'s `assertAccountStillExists`
read) match `fn-data`'s granted `datastore.user` + `fitness.accountReader` exactly, both
independently confirmed live via `gcloud` during provisioning. **Not independently
re-proven with a real authenticated end-to-end call** the way `fn-canary` was — these are
ordinary CRUD functions without a fragile signing/token chain, so identity readback plus
confirmed grants plus a clean build were judged sufficient; a full live functional smoke
test through a real client is not yet done and is called out here rather than implied.

**`runEnforcementStateCheck` deliberately NOT migrated in this pass** — a real finding
caught before deploying, not after: `enforcement_state.ts`'s probe calls
`cloudfunctions.googleapis.com`, `firebaserules.googleapis.com`,
`firebaseappcheck.googleapis.com`, and `identitytoolkit.googleapis.com` directly via
`GoogleAuth({ scopes: ["cloud-platform"] })` bound to whatever SA the function runs as —
none of which is covered by `datastore.user` or `fitness.accountReader`. The original
Step 3 evidence table never itemized these REST-API reads (it only checked
Firestore/Storage/Secret Manager/Vertex/IAM-signBlob/Auth-admin), so grouping this
function into `fn-data` was itself a gap in the original investigation, not something
GPT-PM flagged — moving it now would have silently degraded the probe to
DEGRADED/FAILED status on every run rather than crashing (the probe is "documented to
never throw"), a failure mode that could easily go unnoticed. It stays on the default
Compute SA until its actual permission set (likely `roles/cloudfunctions.viewer` +
Firebase Rules/App Check/Auth-config read equivalents) is investigated with the same
rigor as the other five tiers.

## Tier migration: fn-video (3 of 5) — the actual round-1 finding, closed with real bytes

`RUNTIME_SA.video` added directly to the `VIDEO_HOT`/`VIDEO_BATCH` profile constants in
`scaling.ts` (both are exclusively `clipUrl`/`clipUrls`, no cross-tier sharing, so the
shared-constant edit was safe here unlike `INTERACTIVE`/`RARE`). Deployed together;
`gcloud functions describe` confirmed both now run as
`fn-video@fitness-app-korostelev.iam.gserviceaccount.com`.

This is the one finding round 1 was actually about, so it got the strongest available
proof rather than a readback alone: generated a real IAM access token AS `fn-video`
(via `iamcredentials.googleapis.com:generateAccessToken`, using a temporary
`serviceAccountTokenCreator` self-grant added for this test only and removed
immediately after) and used it to call the GCS JSON API directly against a real object
in the licensed bucket —
`exercises/men/Abdominals/45 degree bicycle twist knee to elbow.mp4`. Both the metadata
read and `?alt=media` byte fetch returned `HTTP 200`; the download returned 266,805 real
bytes. This is the exact chain round 1 found broken (a signer with no reader permission
would 403 here) now proven working end to end, not just re-reviewed on paper.

## Tier migration: fn-billing (4 of 5)

`RUNTIME_SA.billing` added directly to the `WEBHOOK` profile constant (exclusively
`stripeWebhook`, safe as a shared edit) and as a per-call override on
`createCheckoutSession`, `createPortalSession`, `generateAnnualReceipt`,
`bookCoachSession`, `startCoachOnboarding` (all share `INTERACTIVE`/`RARE` with other
tiers, so each needed its own override rather than a shared-constant edit). Deployed
together; `gcloud functions describe` confirmed all six now run as
`fn-billing@fitness-app-korostelev.iam.gserviceaccount.com`. The deploy itself
re-confirmed every one of the 8 `STRIPE_*` secret grants without error — real signal
that the provisioned bindings are functionally correct, not just declared. **No live
Stripe-triggered functional test performed** (no Stripe CLI/API access in this session)
— same class of caveat as `fn-data`, called out rather than implied; `stripeWebhook`
also has Stripe's own non-2xx retry as a safety net per this profile's original header.

## Status

Round 1 (5-tier proposal, `cc759fc`): `MAJOR`, 3 MAJOR + 2 MINOR — fixed. Round 2
(six-tier, `29647bb`): `MAJOR`, 1 MAJOR + 2 MINOR (fn-canary's own permissions) — fixed
at `3f0475f`. Round 3 (fn-canary fix, `3f0475f`): `APPROVE`, additive provisioning
authorized and applied live. **Tiers 1-4 migrated**: `fn-canary` (verified live with a
real triggered run), `fn-data` (5/6 functions; `runEnforcementStateCheck` deliberately
deferred, above), `fn-video` (verified with a real object fetch returning actual bytes),
`fn-billing` (6/6 functions, identity confirmed, no live Stripe-triggered test).
Remaining: `fn-account-delete`, the last and most sensitive tier. `roles/editor` stays
on the default Compute SA until every tier has migrated (including
`runEnforcementStateCheck`, once scoped) and the App Check probe is deleted or moved off
it. `fn-ai-runtime`'s identity is prepared but stays unattached; the four AI callables
remain HOLD-ed by Step 2. See `core/DECISION_LOG.md` for all verdicts and migration
evidence.
