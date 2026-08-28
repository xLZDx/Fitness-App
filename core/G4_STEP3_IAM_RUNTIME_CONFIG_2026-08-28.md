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

## Proposed remediation: four scoped service accounts, not one shared Editor

Not designed or applied yet — proposed here for review before any live IAM change,
given the blast radius of getting this wrong on a project taking real Stripe payments.

| New service account | Replaces default SA for | Grants (beyond the Firebase-managed baseline every SA needs) |
|---|---|---|
| `fn-billing@...` | `createCheckoutSession`, `createPortalSession`, `stripeWebhook`, `generateAnnualReceipt`, `bookCoachSession`, `startCoachOnboarding` | `roles/datastore.user` (Firestore), `roles/secretmanager.secretAccessor` scoped to the `STRIPE_*` secrets only |
| `fn-video@...` | `clipUrl`, `clipUrls` | `roles/datastore.user` (Firestore, quota doc only in practice but IAM can't scope to a document), `roles/iam.serviceAccountTokenCreator` **on itself only** (unchanged behavior, narrower blast radius since no other function shares this identity) |
| `fn-account@...` | `deleteAccount`, `exportAccountData`, `optInDonorWall`, `optOutDonorWall`, `reportEquipment`, `startFreeTrial`, `runEnforcementStateCheck` | `roles/datastore.user`, `roles/firebaseauth.admin` (covers `getUser`/`deleteUser`) |
| `fn-ai@...` | `aiCoachAdvice`, `aiEquipmentRecognition`, `aiMachineDescription`, `aiExerciseGeneration` (not yet deployed), `appCheckProbe` (temporary) | `roles/datastore.user`, `roles/aiplatform.user` |
| `fn-canary@...` | `runProductionCanary` | `roles/datastore.viewer`, `roles/secretmanager.secretAccessor` scoped to `CANARY_WEB_API_KEY` only |

None of these five accounts would hold `roles/editor`, and only `fn-video` would hold
any `iam.serviceAccounts.*` permission, self-scoped. `roles/datastore.user` is itself
project-wide within Firestore (Firestore doesn't support collection-level IAM), so this
is coarser than ideal but still a large reduction from Editor's cross-service scope —
noted as a real remaining limitation, not hidden.

## Why this is not being applied in this same pass

Five reasons, all evidence/risk-based rather than a unilateral call to defer:

1. **This is live production infrastructure carrying real Stripe payments.** A
   mis-scoped grant (missing one Firestore permission `datastore.user` doesn't cover, a
   typo'd secret binding) fails as a runtime error on a REAL user's checkout or webhook,
   not a test failure — worse than the status quo it would be fixing.
2. **`--service-account` is a per-function deploy flag** (`firebase deploy` /
   `gcloud functions deploy --service-account=...`), not something `scaling.ts`'s
   `CallableOptions` profiles currently express — this needs either a per-function
   override added to each profile or a new field threaded through, a small but real code
   change to review alongside the IAM change itself.
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

## Status

Investigation complete, evidence-backed, remediation proposed but NOT applied. Sent to
GPT-PM for review before any live `gcloud iam` mutation — see `core/DECISION_LOG.md` for
the round and verdict once it lands.
