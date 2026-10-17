# Live AI Coach (TDD-001): documentation package

Status as of 2026-10-17: documentation program for sprint AI-COACH-00 only. Implementation, production deployment and user-data migration are NOT authorised. Branch `docs/ai-coach-tdd-001`, base `origin/phase2/main` at `14513a87`. This line is separate from the Phase 2 sprints and changes none of them.

Review state: round 1 (five independent reviewers, 97 claims, two BLOCKER) is remediated in commit `0965349a`. Round 2 (four reviewers verifying the fixes; 23 new MAJOR, 0 BLOCKER) is remediated in the next commit; its findings are in `07_REVIEW_ROUND2.md`. A cross-document consistency check and the GPT-PM documentation gate follow; they are recorded in `docs/sdlc/STATE.md` under the AI Coach section. Nothing in this package is approved until that section says so.

## Reading order

| Order | File | What it is |
|---|---|---|
| 1 | `TDD-001_LIVE_AI_COACH_v0.1_INPUT.md` | Operator draft, translated. Source of intent |
| 2 | `01_REQUIREMENTS.md` | 138 requirements (AICR-001 to 138), non-functional targets, 30 open questions |
| 3 | `01b_CODE_MAP.md` | The draft checked against the real code: 17 disagreements, reusable seams, risks |
| 4 | `02_BACKLOG.md` | Sprints AI-COACH-00 to 05, stories with acceptance criteria, definition of done, coverage |
| 5 | `03_DESIGN.md` | Technical design revision 3 |
| 6 | `03a_ADR_PROPOSALS.md` | ADR-001 to ADR-013, all PROPOSED |
| 7 | `03b_UI_SPEC.md` | Hands-free UI: journeys, screens, states, copy and accessibility rules (DRAFT) |
| 8 | `04a_FUNCTIONAL_TEST_PLAN.md` | Unit, provider, rules-emulator and function tests, all PLANNED |
| 9 | `04b_E2E_AND_DEVICE_PLAN.md` | End-to-end and real-device plan, spikes, operator-owned blockers; all PLANNED, nothing run |
| 10 | `05_REVIEW_ROUND1.md` | The 97 reviewer claims |
| 11 | `06_REMEDIATION_DECISIONS.md` | The decisions applied after rounds 1 and 2 and the questions that stay open |
| 12 | `07_REVIEW_ROUND2.md` | Round 2 verification findings |

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

## Next gates

1. Round 2 reviewer verdicts and the fixes for any new BLOCKER or MAJOR.
2. GPT-PM documentation gate on the exact final head.
3. Only after approval: the push of this branch as one pull request. Code starts with sprint AI-COACH-01 and needs its own authorisation.
