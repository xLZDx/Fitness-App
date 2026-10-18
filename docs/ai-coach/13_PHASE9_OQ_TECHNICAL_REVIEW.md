# Phase 9 technical review of selected open questions

Date: 2026-10-18. Review source: local HEAD `10800ae716d552984fe0389181a157bca1e9af29`. Read-only; no files were changed by the reviewers, and no tests, checks or builds were run.

## Reviewers and scope

| Role | Model / effort | OQs reviewed |
|---|---|---|
| `database-reviewer` | GPT-6 Luna / medium | OQ-01, OQ-02, OQ-21, OQ-22, OQ-23, OQ-31 |
| `architect` | GPT-6 Luna / medium | OQ-03, OQ-10, OQ-12, OQ-13, OQ-17, OQ-18, OQ-24, OQ-28, OQ-30 |
| `security-reviewer` | GPT-6 Luna / medium | OQ-04, OQ-13, OQ-19, OQ-20, OQ-25, OQ-29 |
| `flutter-reviewer` | GPT-6 Luna / medium | OQ-03, OQ-09, OQ-10, OQ-12, OQ-24, OQ-26, OQ-27, OQ-30 |

These are discipline reviews of the documented defaults and evidence, not product-owner acceptance. The OQs not listed above were outside these reviews. All default proposals remain proposals unless an explicit decision is recorded under their source owner.

## Findings and disposition

| OQ | Technical review result | Remaining owner/action |
|---|---|---|
| OQ-01 | Existing serialized `WorkoutSession`/`SetCapture` shape is consistently preserved, but the separate journal/replica schema, retention, and projection boundary remain a TR decision. | TR: define and review durable journal and replica contracts before implementation. |
| OQ-02 | Revision fencing is described, but “Firestore transaction or Cloud Function” remains unresolved and no atomic write path is evidenced. | TR: choose the enforcement path and specify the atomic revision check; verify in the authorized implementation phase. |
| OQ-03 | Existing `aiCoachAdvice` is a one-shot callable; no streaming, provider credential, or audio service boundary exists. Mode B is closer to current architecture, but the voice path remains a proposal pending spike/provider evidence. | TR: run the voice/provider spike. OP: decide cost and shipping path under OQ-05. |
| OQ-04 | Short-lived server credentials are the safer direction, but provider/transport choice, identity binding, TTL/revocation, App Check and metering evidence remain open. | TR/security: select and verify provider and transport. OP separately sets cost caps under OQ-05. |
| OQ-09 | Device/lifecycle coverage is outlined; exact low-end device, trial access, participants and trainer are not set. Emulator lifecycle does not substitute for real-device audio. | OP: confirm devices and trial group. TR: capture exact device/build conditions. |
| OQ-10 | Measurement method is described; no repository evidence supports a numeric battery budget. | TR: measure on selected devices. OP: set budget from results. |
| OQ-12 | Latency/reconnect/interruption measurement protocol is outlined, but thresholds and target sample sufficiency remain unaccepted and need evidence. | TR: run measurements and propose SLOs. OP: accept targets and sample rule. |
| OQ-13 | Proposed server-side feature flag / default OFF / kill switch is not an accepted implementation contract. Flag source, authentication, freshness/cache, Secret Manager authority and lifecycle remain to be specified. Any feature flag must gate new starts without stranding active-session recovery/end. | TR: define the control-plane contract and enforcement. OP: decide rollout/product policy where required. |
| OQ-17 | The documented Phase 2 snapshot confirms existing `ai_coach/` and absence of `live_coach/`; the separate-track / branch-plan choice is governance, not a technical inference. | OP: decide whether to keep the separate track and avoid Phase 2 plan edits. |
| OQ-18 | Existing interfaces are mobile-side inputs only; deterministic multi-week composition and weekly sets/reps/rest policy are new design work. Progression safety overlaps OQ-07. | TR: define composer inputs/outputs and deterministic candidate boundary. OP/TR: resolve safety policy through OQ-07. |
| OQ-19 | Data-flow restrictions are documented, but spoken health statements may still be sent for remote model processing; “nothing leaves the phone except what the user speaks” is not a zero-health-data guarantee. No runtime serialization/logging evidence exists. | OP: decide whether spoken health content may be processed and approve consent/privacy wording under OQ-08. TR later verifies payload/logging behavior. |
| OQ-20 | Stop behavior is technically specified, but symptom list, scope, wording and signer remain unsigned; the design says no list ships unsigned. | OP: name signer and approve the list/scope/copy. TR later proves implementation and recovery behavior. |
| OQ-21 | Journal-only effort storage is proposed, but type/range and projector mapping to `DifficultyRating` remain open; design labels this OQ-21. | TR: define type/range/projection. OP: accept or change user-facing meaning. |
| OQ-22 | Whether an abandoned session offers “save what I did” and how it appears in History is a product decision; the projection option is only proposed. | OP: decide whether to offer it and approve the History status. TR then records the selected projection. |
| OQ-23 | Read-only second device and explicit takeover are technically described; product acceptance is open. Secure enforcement depends on OQ-31. | OP: accept/change takeover behavior. TR implements/proves the server epoch fence later. |
| OQ-24 | Design defines separate latency lanes and timestamp boundaries, but which lane the two-second target governs remains unconfirmed. | OP: confirm target scope. TR: preserve lane-separated measurements. |
| OQ-25 | No signed locale emergency-number table or call action exists. The safe documented default is no number/call until signed. | OP: sign locale table and decide whether call action is permitted. |
| OQ-26 | Existing reminders use inexact scheduling and no exact-alarm permission; that does not prove the AI Coach rest backstop. Lateness tolerance is unmeasured. | TR: measure normal-notification lateness. OP: decide exact-alarm permission and tolerance. |
| OQ-27 | Tap-to-talk and headset hands-free are covered by a proposed comparison; no gym trial has run. | TR: provide trial evidence. OP: select listening mode afterward. |
| OQ-28 | Lease/heartbeat, per-turn limits, journal/sync queue caps, and live-session count are distinct controls. Several safety invariants are defined, but numeric operating limits remain unmeasured; 5 sessions is only proposed. | TR: split into per-control contracts and load/fault measurements. OP: set product/cost limits where assigned (OQ-05). |
| OQ-29 | Marker-before-journal and explicit restart confirmation are documented mitigations; the residual loss before durable marker cannot be removed by wording and is not accepted. | OP: accept/reject the residual risk. TR later proves durability/recovery behavior. |
| OQ-30 | JSON schema does not settle the production tool-call mechanism. Server provider/parser behavior remains open; locked-screen Talk requires Android spike S-A1. Current manifest lacks audio and foreground-service declarations. | TR/server: choose tool-call contract. Android TR: run S-A1. OP: decide whether to include a Talk notification action. |
| OQ-31 | Cooperative-only fencing is not accepted by default; server-enforced epoch is a technical exit requirement. Rules-vs-callable path and race/refusal evidence remain open. Numeric offer/session limits and any risk exception are OP-owned. | TR: assess rules budget, choose rules or validating callable, specify races/refusals. OP: decide any exception and confirm proposed limits. |

## Current checkout evidence

The mobile reviewer inspected the current Android manifest and reminder path: `RECORD_AUDIO`, foreground-service declarations and imported `speech_to_text` are absent; reminders use `inexactAllowWhileIdle` and no exact-alarm permission. The existing deadline-driven rest timer is not evidence of AI Coach microphone/service lifecycle, audio routing, or recovery on physical devices.

## Closure boundary

These reviews improve technical routing and identify concrete next deliverables. They do not close implementation-dependent verification, create a product decision, accept the Phase 9 stories, or authorize the next sprint. OQ-05 through OQ-08, OQ-11, OQ-14 through OQ-16, and any unreviewed parts remain governed by their existing ownership labels in `acceptance.md`.
