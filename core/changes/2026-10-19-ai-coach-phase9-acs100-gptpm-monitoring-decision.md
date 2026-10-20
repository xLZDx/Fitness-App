# Phase 9 ACS-100 GPT-PM monitoring decision and signal audit

Date: 2026-10-19. Documentation and read-only monitoring evidence for ACS-100. No production resource was modified.

## PM Bridge send correction and correlation

Request `7f2a3e91-6d40-4c81-9b56-2f8a7d13c904` failed after two transport attempts. The durable row confirms `status=failed`, `sendPhase=not-started`, `ATTACHMENT_NOT_LANDED` (missing `acceptance.md` in the composer), no send snapshot, and `userTurnId=null`; nothing was sent and no GPT-PM decision exists for it.

At the operator's request for a new PM Bridge chat and a new request, the project was rebound to fresh conversation `6ad5c886-d798-83eb-a90b-f12292d3b458` while the previous conversation was preserved. A no-attachment decision request was then actually sent and awaited in one `gpt_send_and_await` call:

- Request: `26649707-679f-4962-8d26-e3b2a2ff36b3`
- Job: `756f8b0c-6f79-4104-aef9-7662347d955d`
- User turn: `207de071-7066-44d6-b139-e6bae87e1eba`
- Reply: `7175bc88-b910-4573-9504-3b7750fb5bcf`
- Durable status: `succeeded`, `sendPhase=sent`, `correlated=true`

GPT-PM's decision `ACS-100-PM-20261019` is **APPROVED WITH CONDITIONS** for a dedicated production readiness policy, and explicitly keeps ACS-100 OPEN. FA-D1 is approved as interim notification destination. It does not authorize production policy creation, deployment, synthetic AI requests, callable changes, or other production mutations.

## Read-only metric evidence supplied and independently queried

Cloud Monitoring API `metricDescriptors.list` for `run.googleapis.com/container/instance_count_with_readiness` returned:

- `metricKind=GAUGE`, `valueType=INT64`, unit `1`;
- label `readiness_status`, with documented values `UNKNOWN`, `HEALTHY`, `UNHEALTHY`;
- monitored resource types `cloud_run_instance` and `cloud_run_revision`;
- descriptor metadata `samplePeriod=60s`, `ingestDelay=120s`, `launchStage=BETA`.

The project- and service-filtered seven-day time-series query for `cloud_run_revision`, `service_name=aicoachadvice`, `location=europe-west1` returned HEALTHY and UNHEALTHY series with 44 points each. Both series' latest sample was `2026-10-16T11:32:00Z`, value `0`. A query over the preceding 24 hours returned no points. The `run.googleapis.com/service_health_count` query returned no time series for the queried revision. Therefore the current service-specific metric freshness gate is BLOCKED; this is OBSERVABILITY UNKNOWN, not evidence of current healthy/unhealthy readiness.

## Correlated readiness-signal clarification

A second no-attachment request asked GPT-PM to resolve the readiness threshold, duration, missing-data behavior, and creation gate:

- Request: `2ecb7c98-74fe-4c3e-9a5d-1d39b00e44a1`
- Job: `36fb931c-aba1-4b24-8ebc-4f24a3d636a4`
- User turn: `8dc7c8ff-fc8b-41b8-88a9-c94cab6877a5`
- Reply: `d7d392db-a52f-456d-8cb7-bba4e9c85bb7`
- Durable status: `succeeded`, `sendPhase=sent`, `correlated=true`
- Decision: `ACS-100-PM-READINESS-20261019`, **CONDITIONALLY APPROVED — DEPLOYMENT BLOCKED**.

Approved candidate condition:

| Field | Candidate value |
|---|---|
| Metric | `run.googleapis.com/container/instance_count_with_readiness` |
| Monitored resource | `cloud_run_revision` |
| Target | Project `fitness-app-korostelev`; service `aicoachadvice`; region `europe-west1` |
| Readiness label | `readiness_status=UNHEALTHY` |
| Comparison / threshold | `GREATER_THAN 0` (at least one observed unhealthy instance) |
| Evaluation duration | `0s` (explicit product decision) |
| Severity / notification | `WARNING` / existing verified FA-D1 channel |
| Missing or stale data | UNKNOWN and non-alerting for new incidents; separate absence alert is out of scope |
| `evaluationMissingData` | Leave unspecified for duration `0s` |

The `> 0` condition derives from the instance-count metric, rather than an invented percentage. `duration=0s` is explicit GPT-PM direction; it does not guarantee instant detection or delivery. A 120-second alignment period with `ALIGN_MAX` is the candidate technical interpretation: the descriptor samples every 60 seconds and official guidance recommends choosing an alignment period longer than the sampling period; maximum aggregation preserves any nonzero unhealthy count in that window. This 120-second alignment is a technical candidate, not a product alert duration or SLO. Missing time-series data must not be silently treated as healthy or unhealthy.

GPT-PM's gate snapshot initially marked G5 pending. After the reply, Codex completed a read-only technical review against the descriptor and official Cloud Monitoring API documentation. The descriptor reports `samplePeriod=60s`; official guidance recommends an alignment period longer than the sampling period, and the AlertPolicy REST reference requires at least 60 seconds. Codex records 120 seconds (two sample intervals) as the candidate technical alignment, subject to exact configuration validation before deployment. The REST reference permits `ALIGN_MAX` for numeric GAUGE metrics and states that an omitted `trigger` fires if any matched series satisfies the comparison. The descriptor is GAUGE INT64 and the candidate filter selects per-revision series, so 120-second `ALIGN_MAX` with the default ANY-series trigger preserves the intended meaning: an unhealthy count greater than zero on any matching revision within the window. With `duration=0s`, the REST reference permits `evaluationMissingData` only when duration is at least 60 seconds, so leaving it unspecified matches the approved missing-data behavior. G5 is now PASS for candidate technical semantics; this does not validate a deployed policy or remove G2, G7, or G8.

| Gate | Required evidence | Status |
|---|---|---|
| G1 | Descriptor and readiness label semantics | PASS |
| G2 | Fresh service-specific time-series samples | BLOCKED — no samples in preceding 24 hours |
| G3 | `UNHEALTHY > 0` condition | APPROVED |
| G4 | `duration=0s` | APPROVED |
| G5 | Alignment, aggregation and trigger semantics | PASS — Codex read-only technical review against descriptor and API docs |
| G6 | Missing-data behavior | APPROVED |
| G7 | FA-D1 binding on the proposed policy | PENDING |
| G8 | Controlled delivery and human acknowledgement | PENDING |

GPT-PM directs fresh evidence to come from read-only observation of naturally reported metrics; no synthetic AI call or production mutation may be used to force samples. Policy creation remains blocked until fresh service-specific evidence and channel binding are verified. A test notification would establish delivery only, not that the operational condition fires.

## Project status and boundaries

- ACS-100 remains `CARRIED / OPEN`; monitoring workstream is not accepted.
- Role assignment follows the operator's direct instruction that Codex and GPT-PM perform the project roles: Codex is the technical owner/executor for OQ-07/OQ-14/OQ-18 TR work and ACS-100 technical investigation; GPT-PM owns product decisions. The operator remains accountable for the delegated task. The deployed target is Firebase callable `aiCoachAdvice`, backed by Cloud Run `aicoachadvice`; this role assignment does not claim a separate human service team or configured on-call rotation.
- The verified FA-D1 destination is approved, but no AI Coach policy currently binds it; delivery and acknowledgement remain unverified.
- All 13 Phase 9 story dispositions remain PENDING: 11 proposed ACCEPT plus carried-forward ACS-011 and ACS-100.
- OQ-28 and recovery, persistence, stuck-session, reservation-leak, and reconnect requirements remain open.
- No qualified human has signed OQ-07 clinical limits or symptom boundaries.
- No tests, build, CI, migration, alert policy, channel, callable, runtime resource, push, or merge was changed or executed as part of this record.

## Sources and implementation

- Read-only evidence commands and prior deployment/channel evidence: [runtime audit](2026-10-19-ai-coach-phase9-acs100-runtime-audit.md) and [notification channel audit](2026-10-19-ai-coach-phase9-acs100-notification-channel-audit.md).
- Acceptance status: [Phase 9 acceptance](../../docs/ai-coach/acceptance.md) and [project summary](../../docs/ai-coach/00_README.md).
- Cloud Monitoring API references: [alert policy REST resource](https://docs.cloud.google.com/monitoring/api/ref_v3/rest/v3/projects.alertPolicies), [time-series aggregation](https://docs.cloud.google.com/monitoring/api/v3/aggregation), [metric descriptor REST resource](https://docs.cloud.google.com/monitoring/api/ref_v3/rest/v3/projects.metricDescriptors). These document the 60s minimum alignment period, numeric GAUGE support for ALIGN_MAX, the default any-series trigger, and the duration constraint on `evaluationMissingData`.
- Updated durable acceptance and README records and prepared a bilingual HTML status report. No production policy configuration is included or applied.

## Current-turn correction and change contents

The operator explicitly assigned technical ownership to Codex and product decisions to GPT-PM, correcting earlier wording that implied the operator had to appoint a separate technical owner. This updates task-role assignment only; Codex does not claim clinical qualifications. OQ-07 values and symptom boundaries remain blocked until a qualified clinical signature exists. FA-D1 is the GPT-PM-approved interim notification route, but policy binding and delivery/acknowledgement are not yet evidenced.

This commit contains the bilingual status report, acceptance/README status corrections, decision-log correlation, and generated document registry. No tests, checks, builds, CI, migrations, runtime mutation, production configuration, push, or merge are claimed.

Document authoring performed: `C:\Python314\python.exe C:\Users\koros\.claude\tools\report_conform.py ...` refreshed the two requested HTML files (2 refreshed, 0 injected, 0 skipped); `C:\Python314\python.exe scripts/dev/gen_document_registry.py` generated the registry (371 Markdown documents). Reviewed the relevant status, PM Bridge correlation and ownership sections in both HTML files. No separate `--check`, project test/check, build, CI, or migration command was run.
