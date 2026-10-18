# GPT-PM full documentation review — Phase 9

Date: 2026-10-18. Review type: adversarial documentation sweep; no implementation review.

## Review identity and result

- Request ID in the operator-supplied reply: `b67c397a-87d6-40ae-8837-cb21383b543d`.
- Reviewed source HEAD: `b15275fc693eb2934cb71d058ac7be02b7882627`.
- Reviewed source tree: `6d8c23e723898e081a0695f0915bacaf4c4d6f80`.
- Verdict: **MODIFY** — 0 BLOCKER, 4 MAJOR, 2 MINOR.
- The operator supplied the reply as an attachment; PM Bridge recorded the pasted text with `gpt_ingest_reply`. The automated send job still has no correlated `userTurnId` or `replyId`, so this record does not claim transport-level correlation. The verdict is attributed to the source HEAD and request ID stated in the supplied text.
- Review input set named by the supplied report (seven files): `docs/ai-coach/00_README.md`, `01_REQUIREMENTS.md`, `01b_CODE_MAP.md`, `02_BACKLOG.md`, `03_DESIGN.md`, `acceptance.md`, and `release-notes.md`. The report says `docs/DOCUMENT_REGISTRY.md` and full `docs/sdlc/STATE.md` were not supplied.
- The report counted all 13 story IDs and all 31 open questions, and recorded product tests executed as 0 / NOT_RUN.

## Findings and disposition

| Finding | Severity | Review issue | Remediation or disposition |
|---|---|---|---|
| F-01 | MAJOR | OQ-01 and ACS-002 proposed additive serialized set fields even though design §5.1 excludes them from MVP. | Updated OQ-01 and ACS-002 AC-1 to preserve `WorkoutSession`/`SetCapture` shape and keep richer records in the journal/replica; design §5.1 now explicitly marks the old additive default superseded, not approved, and the separate-journal direction as still subject to technical review. |
| F-02 | MAJOR | ACS-001 AC-1 still used ten states and 15 commands, conflicting with nine persisted states, derived `NEXT_EXERCISE`, and the current closed set. | Rewrote AC-1 to use the nine persisted states, derived-view rule, current closed command set, typed refusals, and canonical design §4.1b matrix. |
| F-03 | MAJOR | ACS-100 required named accountable alert owners; design only identified the operator provisionally until a named on-call exists. | Changed the proposed ACS-100 disposition to CARRIED; no person or service owner is invented. Delivery/receipt tests remain NOT_RUN. |
| F-04 | MAJOR | Registry was absent from review attachments and current `live_coach/` layout had not been independently checked against the Phase 2 branch. | At remediation, inspected the generated repository registry and exact `origin/phase2/main` commit `85e7e91ed042b0395b7442839868a35975b62905`; recorded current `ai_coach/` files and the absence of `live_coach/` in the code map. The review is still accurately described as lacking those attachments. |
| F-05 | MINOR | ACS-004 AC-3 retained old helper actions and a dangerous-symptom outcome of PAUSED or ABANDONED. | Rewrote ACS-004 AC-3 to cite design §§4.1a–4.1b and require locked PAUSED, never automatic abandonment or resume. The local documentation review also found the same stale outcome in ACS-027 AC-3; that direct sibling criterion was corrected to the locked-PAUSED and user-only restart contract. |
| F-06 | MINOR | The review package lacked exact source identity and a complete source-file inventory for the new review. | Recorded source HEAD/tree and the seven supplied source documents above; separately identify the registry and STATE omissions. |

## Scope boundary

The review did not accept stories on the operator/product owner's behalf and did not authorize implementation, product tests, production, migration, or push. Its source head predates the remediation described here; the fixes require a fresh exact-head review. Historical Phase 8 approvals retain their original narrower scopes.
