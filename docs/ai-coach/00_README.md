# Live AI Coach (TDD-001): documentation package

Status as of 2026-10-18: AI-COACH-00 documentation gate is approved and merged. PR #13 merged into `phase2/main` as `85e7e91` from exact reviewed head `e6a85647`. The programme remains documentation-only; implementation, production deployment and user-data migration are NOT authorised. This line is separate from the Phase 2 sprints and changes none of them.

Review state: round 1 (five independent reviewers, 97 claims, two BLOCKER) and round 2 (four reviewers, 23 new MAJOR, 0 BLOCKER) are recorded in `05_REVIEW_ROUND1.md` and `07_REVIEW_ROUND2.md`; the remediation decisions are in `06_REMEDIATION_DECISIONS.md`. GPT-PM documentation gate round 1 returned MODIFY (14 MAJOR, 6 MINOR; `08_GPTPM_GATE_ROUND1.md`). Focused rounds 2 and 3 returned MODIFY and were remediated. Round 4 approved the final three affected test rows on exact head `e9a93808`; rounds 5 and 6 approved the gate-record and state consistency updates on their respective exact heads. PR #13 then merged as `85e7e91`. Decision records are `09_GPTPM_VERIFICATION_ROUND4.md` and `10_GPTPM_GATE_RECORD_ROUND5.md`; round 6 is recorded in PM Bridge under request `f1da6121-7598-4b45-9e5f-0a81b2886d47`. Current phase and remaining artifacts are in `docs/sdlc/STATE.md`.

## Reading order

| Order | File | What it is |
|---|---|---|
| 1 | `TDD-001_LIVE_AI_COACH_v0.1_INPUT.md` | Operator draft, translated. Source of intent |
| 2 | `01_REQUIREMENTS.md` | 145 requirements (AICR-001 to 145), non-functional targets, 31 open questions |
| 3 | `01b_CODE_MAP.md` | The draft checked against the real code: 17 disagreements, reusable seams, risks |
| 4 | `02_BACKLOG.md` | Sprints AI-COACH-00 to 05, stories with acceptance criteria, definition of done, coverage |
| 5 | `03_DESIGN.md` | Technical design revision 4 |
| 6 | `03a_ADR_PROPOSALS.md` | ADR-001 to ADR-013, all PROPOSED |
| 7 | `03b_UI_SPEC.md` | Hands-free UI: journeys, screens, states, copy and accessibility rules (DRAFT) |
| 8 | `04a_FUNCTIONAL_TEST_PLAN.md` | Unit, provider, rules-emulator and function tests, all PLANNED |
| 9 | `04b_E2E_AND_DEVICE_PLAN.md` | End-to-end and real-device plan, spikes, operator-owned blockers; all PLANNED, nothing run |
| 10 | `05_REVIEW_ROUND1.md` | The 97 reviewer claims |
| 11 | `06_REMEDIATION_DECISIONS.md` | The decisions applied after rounds 1 and 2 and the questions that stay open |
| 12 | `07_REVIEW_ROUND2.md` | Round 2 verification findings |
| 13 | `08_GPTPM_GATE_ROUND1.md` | GPT-PM documentation gate round 1: verdict MODIFY and its findings |
| 14 | `09_GPTPM_VERIFICATION_ROUND4.md` | Focused approval for FT-2017, FT-1190 and FT-1175 |
| 15 | `10_GPTPM_GATE_RECORD_ROUND5.md` | Focused review of gate/state evidence |

## What the package decides, in one paragraph

A deterministic Workout Runtime owns workout state; the AI only proposes. A live workout is kept in its own collection with one owning device and an epoch, and is written to the normal workout history only when finished, because history totals count every stored session. Every state change goes through an idempotent command envelope and an encrypted local journal; "saved" is shown only after the Runtime confirms. A safety stop takes effect first and cannot be undone by a storage failure or cleared by voice. Health answers stay on the phone. Voice starts as tap-to-talk with a text-to-speech reply built on the device; the realtime provider is chosen by measurement. Cost is capped per turn and per session.

## What the package does not claim

Nothing in it has been built, run or measured. Realtime provider availability and price, Android 13 to 16 foreground-service behaviour, recogniser behaviour over a long session, journal durability on a real device and gym-noise performance are UNKNOWN until the spikes in `04b_E2E_AND_DEVICE_PLAN.md` run. Reviewer claims were applied as decisions; the editing agents re-opened only the code lines they cite themselves.

## Decisions that belong to the operator (full list: `01_REQUIREMENTS.md` section on open questions and `06_REMEDIATION_DECISIONS.md` section C)

| Question in words | Default if unanswered | What changes |
|---|---|---|
| Which voice mode and provider first | Text-to-speech reply first (Mode B), realtime measured in a spike | Cost, latency, privacy review scope |
| Daily and monthly AI cost cap per user and what happens at the limit | Hard daily cap, then manual mode; no number proposed | Whether the sprint 02 server work can be sized |
| Keep transcripts or not | No transcripts | Privacy text and storage |
| Who signs the dangerous-symptom list and the load limits | Symptom stop cannot ship until signed | The safety stop and AICR-053 stay blocked |
| May any health-derived data reach the model | Nothing leaves the phone except what the user says aloud | Consent text, privacy policy |
| Consent wording and the Play declaration | Prepared in AI-COACH-00, operator approves | The first build that calls the server |
| Device matrix, battery budget, accessibility target, latency numbers | Measured in spikes | Acceptance thresholds |
| Where the feature flag lives | Server per-feature flag plus build switch, default OFF | Rollout and rollback |
| Languages; minors and seniors | Current age policy, no relaxation | Scope |
| Second device on an active workout | Read-only with explicit takeover | UX and data safety |
| Emergency number per locale; call button on the locked-screen notification | Table signed by operator; no call button | Safety stop copy |
| Always-listening or tap-to-talk after the gym trial | Tap-to-talk | Battery, privacy, noise robustness |

## Current phase and next gates

Phase 8 (documentation gate) is complete and PR #13 is merged. Phase 9 drafts now exist in `acceptance.md` and `release-notes.md`. The acceptance record proposes story dispositions and lists OQ-01..31 defaults, but remains explicitly unaccepted; the release notes describe documentation only. Supplementary `doc-updater` and `product-ux-reviewer` reviews found and corrected a stale registry rationale, unclear decision routing, and an OQ-18 omission; both reviewers reported no remaining finding in their requested scope at exact head `70470336091c70b372a68202b06bb2c3866eac36`. A `code-explorer` re-read the OQ-18 interfaces and their facts are recorded in the code map and design. These reviews do not replace the SDLC roster's `product-owner` and `technical-writer`; the current Codex agent host rejects both profile names (`unknown agent_type`). The configured subagent model is `gpt-6-luna`; those profiles are absent from the installed Codex profile list. Generic GPT-6 Luna agents prepared draft files only; they did not provide the named role reviews or operator acceptance. The exact-head GPT-PM request was not sent: PM Bridge failed before the send boundary because `STATE.md` and `DOCUMENT_REGISTRY.md` attachments did not land (`ATTACHMENT_NOT_LANDED`; request `f04320dd-2c85-47a1-9944-c56853af455f`). Phase 9 remains pending those gates. Later sprint AI-COACH-01 remains unauthorised and requires its own explicit go-ahead.
