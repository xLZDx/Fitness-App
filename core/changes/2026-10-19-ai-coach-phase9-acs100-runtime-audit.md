# Phase 9 ACS-100 read-only runtime audit

Date: 2026-10-19. Read-only Firebase/Cloud Run/Cloud Monitoring inspection for the deployed AI Coach service and its alert route.

## Scope

This audit follows the correlated GPT-PM ownership decision in [the ownership and policy record](2026-10-19-ai-coach-phase9-gptpm-ownership-and-policy-decision.md). It reads deployment and monitoring metadata only. It does not call the advice endpoint, alter resources, create alert policies, modify recipients, or attempt delivery.

## Commands and evidence

1. `firebase functions:list --project fitness-app-korostelev --json`
   - Returned `status=success` and function `aiCoachAdvice`, project `fitness-app-korostelev`, region `europe-west1`, runtime `nodejs20`, `state=ACTIVE`.
   - Returned Cloud Run `runServiceId=aicoachadvice` and URI `https://europe-west1-fitness-app-korostelev.cloudfunctions.net/aiCoachAdvice`.
2. `gcloud run services describe aicoachadvice --region=europe-west1 --project=fitness-app-korostelev --format="yaml(metadata.name,metadata.labels,metadata.annotations,spec.template.metadata.labels,spec.template.spec.serviceAccountName,status.url,status.conditions)"`
   - Returned service name `aicoachadvice`, Cloud Functions function ID `aiCoachAdvice`, and status conditions `Ready=True`, `ConfigurationsReady=True`, `RoutesReady=True`.
   - This identifies the deployed runtime resource; creator/last-modifier service accounts are Google-managed deployment identities, not an accountable human owner.
3. `gcloud monitoring policies list --project=fitness-app-korostelev --format="table(name,displayName,enabled,conditions.displayName)"`
   - Returned six enabled alert policies. Their displayed targets were account deletion, account export, production canary, enforcement-state checks, and Stripe reconciliation. No listed policy was for `aiCoachAdvice`/`aicoachadvice`.

## Result and limits

- Project-local owning component remains Fitness_App AI Coach; deployed function/runtime identity is now evidenced as `aiCoachAdvice` / `aicoachadvice` in the project and region above.
- The correlated GPT-PM decision assigns the operator an interim human escalation role and Codex technical investigation; this audit does not establish a named accountable human service owner or an on-call rotation.
- No dedicated AI Coach alert policy was found in the returned project policy list. A reachable notification recipient, routing/rotation record, successful delivery, and acknowledgement remain unverified.
- ACS-100 therefore remains `CARRIED / OPEN`. Closure still requires an authorized recipient/rotation, configured policy/route and delivery plus acknowledgement evidence.
- This evidence is a query-time observation, not proof of continuous health, source revision identity, or delivery behavior.

## Verification

- Manually reviewed the three read-only command outputs at 2026-10-19 07:17 UTC.
- No endpoint invocation, runtime mutation, alert configuration, delivery test, tests, checks, build, CI, migration, push, or merge was performed.
