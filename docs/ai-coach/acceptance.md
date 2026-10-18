# AI-COACH-00 Documentation Sprint Acceptance (Draft)

Status: **DRAFT — proposed story dispositions; PENDING operator/product-owner acceptance.**
Date: 2026-10-18. Scope: AI-COACH-00 documentation only. This record does not accept product behavior, resolve proposed defaults, authorize implementation, or authorize production use.

The reviewed documentation head was `e6a85647fbb5904868b18c10382313c316a31259`; it was merged into `phase2/main` as `85e7e91`. This file is a post-merge draft and is not part of either hash. No GPT-PM approval is claimed for this file or for the full story-by-story disposition below.

## Proposed story dispositions

`ACCEPT` and `CARRIED` below are recommendations for the operator/product owner to review, not completed human acceptance. `CARRIED` means the stated acceptance condition cannot be closed from the reviewed evidence or is expressly deferred. Evidence is documentation evidence only.

| Story | Proposed disposition | Evidence and reason |
|---|---|---|
| ACS-001 — Workout Runtime and command contract | ACCEPT | Runtime states, commands, transitions, typed refusals, command envelope, journal acknowledgement and set record are specified in [03_DESIGN.md](03_DESIGN.md) §§4–6; outstanding storage and revision questions remain visibly open in [01_REQUIREMENTS.md](01_REQUIREMENTS.md) §6 (OQ-01/02). |
| ACS-002 — Event journal and WorkoutSession compatibility | ACCEPT | Additive compatibility, journal durability/replay, offline subset and reconnect flow are specified in [03_DESIGN.md](03_DESIGN.md) §§5–6 and [03a_ADR_PROPOSALS.md](03a_ADR_PROPOSALS.md); the remaining decisions are listed below, not treated as approved. |
| ACS-003 — Feature flag, compatibility and isolation | ACCEPT | Flag behavior, default-off/fail-closed behavior, account isolation and compatibility constraints are specified in [03_DESIGN.md](03_DESIGN.md) §§12, 19 and [03a_ADR_PROPOSALS.md](03a_ADR_PROPOSALS.md); OQ-13 remains a proposed default. |
| ACS-004 — Safety policy | ACCEPT | Safety eligibility, fail-closed behavior, stop scopes, typed refusals and allowed actions are specified in [03_DESIGN.md](03_DESIGN.md) §§9, 4.1b and [03b_UI_SPEC.md](03b_UI_SPEC.md). Numeric limits and symptom sign-off remain unsigned; OQ-07/20 explicitly prevent shipping the symptom stop until signed. |
| ACS-005 — Privacy and consent policy | ACCEPT | Data categories, consent states, retention/deletion/export and log allow-list are specified in [03_DESIGN.md](03_DESIGN.md) §§14–15 and [03b_UI_SPEC.md](03b_UI_SPEC.md); consent and legal/store wording remain subject to operator review under OQ-08. |
| ACS-006 — Security design: tool authorization and credentials | ACCEPT | Authorization checks, identity/session fences, credential handling and injection cases are documented in [03_DESIGN.md](03_DESIGN.md) §§7, 11 and [03a_ADR_PROPOSALS.md](03a_ADR_PROPOSALS.md). Provider/transport choice remains open under OQ-04. |
| ACS-007 — Voice engine and Android lifecycle design | ACCEPT | Mode comparison/default, voice state transitions, interruption/reconnect and Android lifecycle plan are documented in [03_DESIGN.md](03_DESIGN.md) §§8, 10 and [03a_ADR_PROPOSALS.md](03a_ADR_PROPOSALS.md). Mode and locked-screen behavior remain subject to the listed spikes and OQ-03/30. |
| ACS-008 — Cost control and observability | ACCEPT | Cap mechanism, manual fallback, usage events, latency measurement and alert signals are documented in [03_DESIGN.md](03_DESIGN.md) §§16–17. Numeric cost limits and operational thresholds remain open (OQ-05/28); the design labels delivery verification as planned, not run. |
| ACS-009 — Test plan and requirement-to-test map | ACCEPT | Planned requirement mappings and falsifiable scenarios are in [04a_FUNCTIONAL_TEST_PLAN.md](04a_FUNCTIONAL_TEST_PLAN.md) and [04b_E2E_AND_DEVICE_PLAN.md](04b_E2E_AND_DEVICE_PLAN.md). These are plans, not executed results; this documentation sprint has no product-test pass claim. |
| ACS-010 — Dependency map, Phase 2 relationship and registry | ACCEPT | Existing-module facts and track boundary are in [01b_CODE_MAP.md](01b_CODE_MAP.md), [03_DESIGN.md](03_DESIGN.md) and [00_README.md](00_README.md). The generated [DOCUMENT_REGISTRY.md](../DOCUMENT_REGISTRY.md) now lists the round-4/5 gate records, this acceptance file, and the release notes. OQ-17/18 remain open questions, with their stated defaults and evidence recorded; unresolved decisions are not represented as accepted. |
| ACS-011 — Design review gate and acceptance | CARRIED | Earlier gate records establish approvals only for their stated scopes and exact heads. Round 4 covers FT-2017, FT-1190 and FT-1175 at `e9a93808`; round 5 covers consistency records at `b11213dc`; round 6 covers state/milestone consistency at `e6a85647`. This acceptance file was added after those heads, so story-by-story approval of this file is outstanding. See [round 4](09_GPTPM_VERIFICATION_ROUND4.md), [round 5](10_GPTPM_GATE_RECORD_ROUND5.md), and the round-6 record referenced in [SDLC state](../sdlc/STATE.md). |
| ACS-100 — Observability sink, alerts and owners | ACCEPT | Sink, alert signals, provisional ownership and open thresholds are described in [03_DESIGN.md](03_DESIGN.md) §17. Delivery and alert-owner receipt checks are planned, not runtime-proven; OQ-28 remains open. |
| ACS-101 — Contracts for review-round-1 decisions | ACCEPT | Remediation decisions and status of D1–D17 are recorded in [06_REMEDIATION_DECISIONS.md](06_REMEDIATION_DECISIONS.md) §§A–E; the amended consent/privacy prerequisite is in [01_REQUIREMENTS.md](01_REQUIREMENTS.md) AICR-106 and [03_DESIGN.md](03_DESIGN.md) §14. No build, store submission or operator/legal approval is claimed. |

## Open questions and proposed defaults

The defaults below are copied or faithfully condensed from [01_REQUIREMENTS.md](01_REQUIREMENTS.md) §6 and [06_REMEDIATION_DECISIONS.md](06_REMEDIATION_DECISIONS.md) §§C–E. **They remain proposals where the records say OPEN; this table does not turn a default into an operator or technical decision.** Owner labels retain the source meaning: OP = operator decision; TR = technical review (architect, security, Android or backend as applicable).

| ID | Unanswered question | Proposed default (not a decision) | Owner per source |
|---|---|---|---|
| OQ-01 | Set-record extension given existing `WorkoutSession` stores weight and reps only | Optional additive set fields plus a separate append-only journal; old documents unchanged (ADR-007). | TR |
| OQ-02 | Enforcing `expected_revision` where repository `save` has no revision parameter | Revision in journal/session document, checked in a Firestore transaction or Cloud Function. | TR |
| OQ-03 | MVP voice path: realtime Mode A or Mode B STT–LLM–TTS | Mode B first as command fallback; measure Mode A in a spike. | TR, then OP for cost |
| OQ-04 | Provider/transport and source of short-lived credentials | Server-issued short-lived credentials through Cloud Functions; no key in app. | TR (security) |
| OQ-05 | Per-user daily/monthly AI cost cap and behavior at limit | Hard per-user daily cap; manual mode and a message on exhaustion; no numeric cap proposed, operator sets it. | OP |
| OQ-06 | Memory/transcript retention | No transcripts; derived memory only; delete on user request or account deletion. | OP |
| OQ-07 | Safety load/repetition limits and symptom list/sign-off | Start from existing eligibility and `progression.dart` rules (not yet read in the source record); invent no new numeric limits without sign-off. | OP (clinical/legal advice if wanted), TR |
| OQ-08 | Voice consent text and Play data-safety/permission declaration | Draft in AI-COACH-00; submit with first build requiring `RECORD_AUDIO`; operator approval required. | OP |
| OQ-09 | Exact Android device/OS matrix and gym trial group | Samsung S23 plus one low-end device; Android 13–16 emulator for lifecycle only, real device for audio. | OP |
| OQ-10 | Battery budget per hands-free hour | Measure first in AI-COACH-02 and set budget from measurement; no invented number. | OP / TR |
| OQ-11 | Accessibility requirements | Follow existing app rules; always provide text conversation view. | OP |
| OQ-12 | Reconnect, interruption-stop and P95 sample-size targets | Measure in AI-COACH-02 and propose SLO values after first trial. | TR |
| OQ-13 | Location of `live_ai_coach_enabled` | Server-controlled per-feature flag read at startup, default OFF, plus server kill switch. | TR |
| OQ-14 | Verification of no invented numbers, reasons or technique claims | Validator compares model-output numbers/reason codes against context; fixture dialogues in tests. | TR |
| OQ-15 | MVP spoken languages | English plus current primary app language, to be named by operator. | OP |
| OQ-16 | Minors/seniors scope | Reuse current age policy unchanged; no relaxation. | OP |
| OQ-17 | Relationship to Phase 2 plans/branching | Separate AI-COACH track; do not edit Phase 2 plans. | OP |
| OQ-18 | Multi-week composition contract over `ai_planner`, `training_context`, `recovery`, and `visual_equipment` | Existing interface facts were read and recorded in [01b_CODE_MAP.md](01b_CODE_MAP.md#interface-facts-rechecked-2026-10-18-oq-18). Treat these as mobile-side inputs only; they do not prove a live-coach integration. Define a deterministic multi-week composer and source of weekly sets/reps/rest in technical design; the model must not add exercises outside the composer's candidate output. | TR |
| OQ-19 | Whether health-derived restrictions/screening data may reach model | No; nothing leaves the phone except what the user speaks (decision A6.2 wording). | OP |
| OQ-20 | Signer and stop scopes for dangerous-symptom list | Symptom stop cannot ship until signed. | OP |
| OQ-21 | Storage for per-set effort | Journal only. | TR, OP |
| OQ-22 | Whether abandoned sessions appear in History and where data lives | Keep on phone, do not show in History; offer “save what I did” as described in the backlog/design. | OP |
| OQ-23 | Second device behavior during a live session | Read-only with explicit user takeover. | OP |
| OQ-24 | Scope of the 2-second latency target | 2 seconds for voice acknowledgement; 300 ms for local/manual lane. | TR |
| OQ-25 | Emergency number by locale, signer, locked-screen call action | Operator-signed table; no call action. | OP |
| OQ-26 | Exact-alarm permission for rest-end backstop | No exact-alarm permission; normal notification. | OP, TR |
| OQ-27 | Listening mode after gym trial | Tap-to-talk. | OP |
| OQ-28 | Lease, turn, journal, sync and per-turn numeric limits | Measure in spikes; invent no number. Cost caps remain under OQ-05. | TR (OP for cost caps via OQ-05) |
| OQ-29 | Accept residual risk that process kill before durable safety marker loses a `safety_stop` | Not accepted until operator signs; “I am well to continue” remains mandatory. | OP |
| OQ-30 | Model tool-call mechanism and locked-screen Talk/headset support | JSON response schema; locked-screen Talk path unproven until Android spike S-A1. | TR |
| OQ-31 | Accept cooperative-only owner-epoch fence if rules/callable validation fail; confirm proposed 3 export offers/7 days and 5 unfinished-plus-parked sessions | Cooperative-only fence is NOT accepted; server-enforced epoch through rules or validating callable required for AI-COACH-01 exit. The numbers (3 offers, 7 days, 5 sessions) remain PROPOSED pending confirmation, not measured. | OP |

## Review and verification evidence

- Documentation review artifacts: [round 1](05_REVIEW_ROUND1.md), [round 2](07_REVIEW_ROUND2.md), [round-1 GPT-PM gate](08_GPTPM_GATE_ROUND1.md), [round-4 focused verification](09_GPTPM_VERIFICATION_ROUND4.md), and [round-5 gate-record verification](10_GPTPM_GATE_RECORD_ROUND5.md). The round-6 state/milestone verification is recorded under request `f1da6121-7598-4b45-9e5f-0a81b2886d47` in [SDLC state](../sdlc/STATE.md). See [backlog §4 and §5](02_BACKLOG.md) for the documentation-only Definition of Done and sprint gate; the design and review records contain the falsifiable document checks performed.
- Round 4 approved only FT-2017, FT-1190 and FT-1175 plus direct consistency in `04a_FUNCTIONAL_TEST_PLAN.md`, on exact head `e9a93808759dd1e4340c626a655fa209bd53f2ec` (request `b3e7a9d1-4c2f-4e8a-9f61-7d0a2c5e8b34`). Round 5 approved consistency records at `b11213dc3b762e0b6a3cd91c9763b53a5a4278ac` (request `a13d8f42-0cf6-4f6a-8b1d-e72c964ad5c1`). Round 6 approved state/milestone consistency at `e6a85647fbb5904868b18c10382313c316a31259` (request `f1da6121-7598-4b45-9e5f-0a81b2886d47`). These are separate scopes; none approves this post-merge draft.
- Product tests, builds, analyzers, device runs and runtime measurements: **NOT_RUN** for this documentation sprint. [04a_FUNCTIONAL_TEST_PLAN.md](04a_FUNCTIONAL_TEST_PLAN.md) and [04b_E2E_AND_DEVICE_PLAN.md](04b_E2E_AND_DEVICE_PLAN.md) explicitly say their scenarios are planned and not executed. No runtime outcome, latency, battery, cost, or device compatibility is claimed.
- Supplementary read-only reviews of the prior draft at exact head `bdf089c83b23ef35569ec09fc8ff117ac52b1194`: `doc-updater` reported a stale ACS-010 registry rationale (MAJOR); `product-ux-reviewer` reported the same stale rationale (MINOR) and ambiguous routing of technical versus operator-owned open questions (MAJOR). This revision corrects both. These were supplementary documentation reviews, not product-owner acceptance or the unavailable `technical-writer` review.
- Follow-up read-only reviews confirmed the fixes at exact head `4d98765ad5f4c8114aa0f99fce82a9b42febb66a`: `doc-updater` found no remaining ACS-010 registry issue; `product-ux-reviewer` confirmed the routing and registry corrections but found a MINOR OQ-18 omission. The OQ-18 guardrails were added in the current revision. Both reviewers rechecked their findings at exact head `70470336091c70b372a68202b06bb2c3866eac36` and reported no remaining finding in scope.

### Documentation-only falsifiable review checklist

These are manual document checks, not product tests. They were reviewed against the files in this worktree on 2026-10-18; they do not substitute for the missing named-role reviews or operator acceptance.

| Check | Falsifiable criterion | Result and evidence |
|---|---|---|
| D-1 Story accounting | Every AI-COACH-00 story ID ACS-001..011 plus ACS-100 and ACS-101 appears exactly once in Proposed story dispositions. | REVIEWED: the acceptance table contains all 13 IDs. |
| D-2 Open-question accounting | OQ-01 through OQ-31 each has a question, proposed default, and owner label; proposal language does not state those defaults are accepted. | REVIEWED: the OQ table includes all 31 IDs and explicitly labels defaults as proposals. |
| D-3 Evidence scope | Every cited GPT-PM round is tied to its exact source head/scope, and the text does not claim those approvals cover this post-merge file. | REVIEWED: rounds 4–6 and exact heads are listed above; this file is identified as added after those heads. |
| D-4 Release boundary | Release notes identify a documentation-only package and disclaim product behavior, tests, implementation, deployment, and migration. | REVIEWED: see [release notes](release-notes.md), sections “Release type” and “Not included in this release.” |
| D-5 Registry coverage | The derived registry lists the acceptance and release-note files. | REVIEWED: both entries are present in [DOCUMENT_REGISTRY.md](../DOCUMENT_REGISTRY.md), generated from the repository. |

## Acceptance required to close this record

To close this record, route each open question according to its source owner label: TR-only items require the relevant technical review; OP-only items require the operator/product-owner decision; mixed-owner items require technical review first and then the operator decision where the source assigns one. Record the reviewer, decision or carried status, and evidence for each question. The operator/product owner reviews and records the final story dispositions on this exact file revision; this does not substitute for the technical decisions above. `TR` is a discipline/role label, not a named person or service owner; the source records do not name an individual for every technical review. Until those reviews and acceptance are recorded, this file remains a draft; the historical documentation gate remains approved/merged, while this new acceptance artifact is not yet accepted.
