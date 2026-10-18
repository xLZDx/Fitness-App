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
| Who signs the dangerous-symptom list and the load limits | Existing eligibility/progression values are product heuristics, not approved AI Coach limits; symptom stop cannot ship until signed | The safety stop and AICR-053 stay blocked |
| May app-derived health data reach the model, and can spoken input itself contain health data? | App-derived restrictions, screening values and reason codes stay out of model context. A remote turn sends the user's utterance, which may contain health information, only with current server-confirmed consent. Operator acceptance and privacy wording remain open (OQ-08/OQ-19). | Consent text, privacy policy, model-bound payload/logging verification |
| Consent wording and the Play declaration | Prepared in AI-COACH-00, operator approves | The first build that calls the server |
| Device matrix, battery budget, accessibility target, latency numbers | Measured in spikes | Acceptance thresholds |
| Where the feature flag lives | Server per-feature flag plus build switch, default OFF | Rollout and rollback |
| Languages; minors and seniors | Current age policy, no relaxation | Scope |
| Second device on an active workout | Read-only with explicit takeover | UX and data safety |
| Emergency number per locale; call button on the locked-screen notification | Table signed by operator; no call button | Safety stop copy |
| Always-listening or tap-to-talk after the gym trial | Tap-to-talk | Battery, privacy, noise robustness |

## Current phase and next gates

Phase 8 (documentation gate) is complete and PR #13 is merged. Phase 9 drafts exist in `acceptance.md` and `release-notes.md`; acceptance remains pending operator/product-owner review, and release notes describe documentation only. Supplementary `doc-updater` and `product-ux-reviewer` reviews found and corrected a stale registry rationale, unclear decision routing, and an OQ-18 omission; both reported no remaining finding in their requested scope at exact head `70470336091c70b372a68202b06bb2c3866eac36`. A `code-explorer` re-read the OQ-18 interfaces and those facts are recorded in the code map and design. These reviews do not replace the required `product-owner` and `technical-writer` roles; the Codex agent host rejects both profile names (`unknown agent_type`), and the configured model is `gpt-6-luna`.

A later read-only `architect` review of the proposed OQ-18 composer at `a4dafe052e86215b5c2b175260954e9c7d73c53d` found two MAJOR specification gaps and two MINOR ambiguities. The proposal and OQ records now carry the clarifications; deficit projection, recovery horizon, and related TR approval remain open. See `13_PHASE9_OQ_TECHNICAL_REVIEW.md` and the linked per-commit change record.

PM Bridge later returned correlated `APPROVE` for the focused F-01..F-06 and linked-evidence review on supplied HEAD `65896f3d873ba66496062dbe28b24ed3ce1f8c5f` (request `75149685-e9df-42d1-8d6f-f7158b958982`, reply `6945d418-d6d3-4489-9b31-a7d4d167cdd7`). The exact scope and limitations are in `14_PHASE9_FINAL_EXACT_HEAD_REVIEW.md`; it does not cover later commits or close operator acceptance/open questions.

A subsequent exact-head review attempt for `fb9f94f53ef4d4548c8dfce8c1bbf6078c0c4da6` failed before send because attachments did not land in the ChatGPT composer. Same-ID send retry and await recovery both failed; there is no successful send baseline or reply correlation. This is recorded in `core/changes/2026-10-18-ai-coach-phase9-current-head-review-transport.md`. A later correlated GPT-PM review approved a one-file ownership-source evidence bundle for supplied HEAD `4f48f09c818cb87ea0e192a44e4c4350119dbf10`; that approval is limited to its stated evidence scope and does not establish Git ancestry or cover later HEADs. See [the coverage audit change record](../../core/changes/2026-10-18-ai-coach-phase9-current-review-head-audit.md) and [the ownership review record](16_PHASE9_OWNERSHIP_SOURCE_APPROVAL.md).

A separate focused review attempt for supplied HEAD `7d268912029f095947943cad83f911cd748fdcc7` also failed before send with `ATTACHMENT_NOT_LANDED`; request `b0d0ad57-869a-4484-86d0-3b9939eb1c0f` has no user turn or reply correlation. The exact missing attachment list and durable job status are recorded in `core/changes/2026-10-18-ai-coach-phase9-current-head-7d268-review-transport.md`. This was a new source revision request, not a retry of the earlier request, and no review is generating.

A one-file evidence bundle subsequently received correlated GPT-PM `APPROVE` for supplied HEAD `f2bfcaaa79f39415943b5ecfecc27adc980c4196` (request `9ef40019-3f84-4b0f-818d-80e36887eab0`, reply `f94bfc55-2896-4521-9621-f6f2ca8e9443`). It approved only the stated evidence-consistency scope; it did not decide operator or technical questions, accept stories, authorize implementation, or independently inspect the Git tree. See `15_PHASE9_CURRENT_EVIDENCE_APPROVAL.md`.

The expanded ownership-source audit later received correlated GPT-PM `APPROVE` on supplied HEAD `4f48f09c818cb87ea0e192a44e4c4350119dbf10` (request `13e975c3-2249-49ee-9ffb-4e1d5944cceb`, reply `c7daff3a-1f8b-44ad-b4e1-2ef805d029ab`). The review confirms role-versus-owner wording in its attached scope but does not independently verify the absent `CODEOWNERS` paths or assign owners. See `16_PHASE9_OWNERSHIP_SOURCE_APPROVAL.md`.

The final-head Phase 9 documentation review returned correlated `APPROVE` for supplied HEAD `e039ec1f9c994a031f2cbb2c9582bd5aed4bbff3` (request `ddd6df0b-b4b6-4d04-b66c-198233a501df`, reply `d530a2c3-93d0-4f5f-8aa4-8e99e3991f75`), with 0 BLOCKER/MAJOR/MINOR and one nonblocking evidence-scope INFO. It does not accept stories/OQs, assign owners, authorize implementation, or extend to later commits. See `17_PHASE9_FINAL_HEAD_REVIEW.md`.

A supplemental read-only GitHub check found no conventional `CODEOWNERS`/`OWNERS` files in the queried paths on `phase1/main` or `phase2/main`, and no matching issues for OQ-18 or ACS-100. This does not rule out assignments in other refs or external systems; see `18_PHASE9_REMOTE_OWNER_SOURCE_CHECK.md`.

The full GPT-PM documentation review labelled request `b67c397a-87d6-40ae-8837-cb21383b543d` returned `MODIFY` for source HEAD `b15275fc693eb2934cb71d058ac7be02b7882627`, with 4 MAJOR and 2 MINOR findings. The operator supplied the review text, and PM Bridge recorded it; that historical reply is not independently transport-correlated. Findings F-01..F-06 and their remediations are recorded in `11_GPTPM_FULL_DOCUMENTATION_REVIEW.md`. A targeted follow-up returned correlated `APPROVE` on the supplied remediation package identity `57bd7092163d60f40bdc37bfd0dc7a6f824ddc5e` (request `6e62cb08-9ff1-417b-af21-045c70d3d2d9`); see `12_GPTPM_PHASE9_REMEDIATION_APPROVAL.md`. GPT-PM then approved the evidence-record package on current supplied HEAD `10800ae716d552984fe0389181a157bca1e9af29` (request `d5b9dc03-021c-46f8-814b-c67b02bb6f95`). Selected technical reviews for open questions are recorded in `13_PHASE9_OQ_TECHNICAL_REVIEW.md`; their proposals remain open pending the listed technical evidence and operator decisions. Phase 9 story acceptance remains pending operator/product-owner review, and the named product-owner and technical-writer reviews remain unavailable in the current host. Later sprint AI-COACH-01 remains unauthorised and requires its own explicit go-ahead.

A correlated PM Bridge review approved the bounded remote owner-source evidence package at supplied HEAD `924df4518617d25c9fecfd7200aa59ee83a4be0c` (request `f0a8df7d-3a50-49f1-b5b2-6d4c16c34fd4`, reply `f729d4e5-9bff-4296-834c-95b945decdb9`; 0 BLOCKER/MAJOR/MINOR, 1 INFO). Raw GitHub responses, full branch inventory and complete-registry recount were not independently verified. No owners or product decisions were assigned; see `19_PHASE9_REMOTE_OWNER_SOURCE_REVIEW.md`.

A later read-only connector repeat recorded normalized results for the same limited checks: ten 404 owner-path responses and empty issue-search results; the two exact branch queries returned the requested branch. It is not a raw HTTP archive or full branch inventory; see `18_PHASE9_REMOTE_OWNER_SOURCE_CHECK.md`.
