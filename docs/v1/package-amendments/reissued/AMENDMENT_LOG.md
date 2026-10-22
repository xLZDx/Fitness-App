# Reissued registers: amendment log (2026-10-22)

Scope: `REQUIREMENTS.csv`, `BACKLOG.csv`, `ACCEPTANCE.csv`, `TRACEABILITY.csv` of package `FitnessUp_v1_Rebaseline_2026-10-20`, reissued with the four approved amendments (`LOCAL_QUEUE_DECISION`, `ATTENDANCE_SPEC_AMENDMENT`, `VOICE_READY_PROMPT_DECISION`, `MODULE_DISPOSITION_MATRIX`) and the three design documents (`OFFLINE_COMMAND_PROTOCOL.md` section 10, `QUEUE_LIFECYCLE_DATA_PRIVACY.md`, `MODULE_ROUTE_ACTION_MATRIX.md` section 5). Authority on which package rows change: `../SUPERSESSION.csv`. Check: `C:/Python314/python.exe validate_registers.py` in this folder.

Layout: original columns plus one trailing `amendment_note` (empty when the row is unaffected). UTF-8 with BOM kept; line endings kept per file (REQUIREMENTS and BACKLOG LF, ACCEPTANCE and TRACEABILITY CRLF, as in the package). No existing id was removed or renamed.

## Counts
| File | Package | Reissued | Rows with a note |
|---|---|---|---|
| REQUIREMENTS | 56 | 56 | 23 |
| BACKLOG | 56 | 56 | 23 |
| ACCEPTANCE | 91 | 139 (91 + 27 + 10 + 11) | 97 (49 amended old rows + 48 new) |
| TRACEABILITY | 91 | 139 | 97 |

New acceptance rows (48, all NOT_RUN, P0): FU-AC-092..118 (27, copied exactly from `ACCEPTANCE_AMENDMENTS.csv`), FU-AC-119 and FU-AC-125 (2, `OFFLINE_COMMAND_PROTOCOL.md` v1.3.1 section 10; 125 is the shared queue contract fixture), FU-AC-120..124 and 126..128 (8, `QUEUE_LIFECYCLE_DATA_PRIVACY.md` rev 3; 128 is the caps row, renumbered by the lifecycle document because 125 belongs to the protocol), FU-AC-130..140 (11, `MODULE_ROUTE_ACTION_MATRIX.md` section 5). Verified against the documents: 119..128 are ten ids, so the total is 91 + 27 + 10 + 11 = 139 (the earlier 138 omitted FU-AC-128). Rows 119..128 were regenerated from the current documents. FU-AC-125 names no requirement in the protocol; it is mapped to FU-RQ-015/FU-015. No new requirement or task ids were created. FU-AC-092..101 text is untouched (the design documents add test detail only; it is not copied into the amendment rows).

## Rewritten in place (active text changed, old wording moved to `amendment_note`)
- FU-RQ-015, FU-015, FU-AC-015, FU-AC-064: durable local acceptance for CompleteSet, AddEligibleExercise, SetDifficulty. No active column still contains "online-only" or "remain online" (checked by the validator on all four files, not only these rows). AC-064 scenario changed from "Unsent UI capture is lost" to "Locally accepted capture survives process loss".
- FU-AC-067 (+ FU-019 definition_of_done): bare go is not required; StartSet is the waiting-state action (WAITING_FOR_READY or touch).
- Other REWRITE entries of `SUPERSESSION.csv`: FU-RQ-008/FU-008/FU-AC-008 (local, pending, committed, conflicted), FU-RQ-011/FU-011/FU-AC-011 and FU-AC-057 (client-stable operation id, lost ack with the same operation id), FU-AC-047 and FU-047 (automatic detection, suggestion, unknown), FU-046 and FU-AC-046 (delivery 1 foreground text; delivery 2 stated as a separate later delivery), FU-AC-080 (one phrase: "honest online status" became "honest connectivity and sync status ... pending sync").
- Note-only (text kept): all EXTEND, PRESERVE_EXTEND, PRESERVE_CLARIFY rows, FU-AC-076, FU-RQ-018/FU-RQ-024 and their tasks/acceptance, FU-RQ-021/022.

## Judgement calls
1. ADR-CMD-03 (Option A, online-only) lives in `docs/15_DECISIONS_AND_RISKS.md`, not in the registers. It is not edited here. Required follow-up in that document: keep the ADR text as history, add the superseding decision `LOCAL_QUEUE_DECISION`, and update ADR-CMD-02 (server-minted command id) and ADR-CMD-04 (writer takeover); also ADR-LOC-01 (GymVisit distinct from workout, delivery 1 foreground). The registers cite ADR-CMD-03 only in notes.
2. SUPERSESSION marks FU-RQ-011/FU-AC-011/057 and the voice, attendance entries as REWRITE; the task text only mandated rewriting for the 015 family and the voice rows. I rewrote the REWRITE rows whose active text directly contradicted an amendment (008, 011, 057, 046, 047, 067, 080) and left pure EXTEND rows as note-only. Reason: leaving active text that demands a server-minted prepare step or background registration would reintroduce the contradiction the review found.
3. FU-AC-012, 058, 059, 060, 081 still use admission/preparation/birth-epoch vocabulary (the withdrawn model). SUPERSESSION says EXTEND, so the text is kept and the note says it is read against `OFFLINE_COMMAND_PROTOCOL.md`. `OFFLINE_COMMAND_PROTOCOL.md` section 10 says 058 should be rewritten as "fence after detail TTL"; that is a decision for the package author once the protocol is frozen. Open item.
4. SPLIT of FU-RQ-046: requirement title unchanged; task definition_of_done and FU-AC-046 expected_result now state delivery 1 (foreground) as active and name delivery 2 as separate, later, behind a dated Play policy assessment. No delivery 2 acceptance rows were invented; they are still to be written.
5. Requirement mapping of the design-document rows: FU-AC-119 to FU-RQ-014/FU-014 (stated by the document). FU-AC-120..127 use the requirement the document names (013, 049, 019, 015) and the task with the same number. `MODULE_ROUTE_ACTION_MATRIX.md` names no requirement: FU-AC-133, 134, 135 (mode gate, recorder off/on, sport list) are mapped to FU-RQ-002/FU-002 (outdoor deferral); FU-AC-130..132 and 136..140 to FU-RQ-001/FU-001 (one fitness product, module disposition). Each such row says so in its note. FU-AC-136 (HIDE closure) could equally be FU-RQ-002; nearest requirement chosen by subject.
6. Numbering gap: FU-AC-129 is unused (FU-AC-128 now exists; the module matrix starts at 130). Not filled to avoid inventing content.
7. FU-AC-092..101 also have longer protocol-level scenario text in `OFFLINE_COMMAND_PROTOCOL.md` section 10. Per instruction the rows keep the exact `ACCEPTANCE_AMENDMENTS.csv` text; the longer scenarios are test-design detail, not a second row.
8. `SUPERSESSION.csv` row for FU-RQ-014 marks the legacy-writer versus typed-command proof as OWED; FU-AC-119 is the proposal from the protocol document and is marked "proposed" in its note. It is not yet listed in `ACCEPTANCE_AMENDMENTS.csv` or `SUPERSESSION.csv` (document edits outside this task).
9. TRACEABILITY new rows: document = the amendment or design file path; evidence empty (NOT_RUN as in package); legacy_ids = the acceptance row's source tag. Rows of amended old acceptances carry "See amendment_note of FU-AC-xxx".
10. Acceptance_ids cells were updated only from each new row's own requirement/task. Cross-attachments named in SUPERSESSION (for example FU-AC-110 also extending FU-RQ-045/048, FU-AC-099 also extending FU-AC-069/080) are recorded in notes, not as extra cells, so the one-requirement-one-row invariant checked by the validator holds.
11. The "go" phrase: the validator checks FU-AC-067 for WAITING_FOR_READY, StartSet and "not required to start a set"; it does not judge wording quality. The semantic scan is a string scan: it proves absence of the two phrases in active text, not absence of every online-only meaning.
12. Other registers (FEATURE_MATRIX, GYM_STORY_TEST_CROSSWALK, DATA_DICTIONARY, EVIDENCE_REGISTER, DOCUMENT_INVENTORY and so on) were not reissued; FEATURE_MATRIX repeats the FU-RQ-001/002 and 015 wording and will still show the old text until the package author reissues it. Documents `01_PRODUCT_SCOPE`, `03_ARCHITECTURE`, `04_CORE_TDD`, `05_DATA_MODEL`, `06_GLOBAL_COACH`, `09_GYM_VISITS_TDD` etc. are out of scope here (list in `../PACKAGE_RECONCILIATION_2026-10-22.md`).

## Not verified
Priority rationale for FU-AC-066/067/072 (P0 under P1 parents) is unchanged. Nothing here was executed against an application; every new row is NOT_RUN by design.

## Gate follow-up (GPT-PM, after protocol v1.3.1 and lifecycle rev 3)
- **M-02 (withdrawn online admission protocol).** FU-AC-012, 058, 059, 060 and 081 and the FU-012 definition_of_done were REWRITTEN IN PLACE to test the permanent replay fence and terminal outcomes (result codes of protocol section 4.4, outcome table 3.7: COMMITTED, ALREADY_COMMITTED, ALREADY_COMMITTED_DETAIL_EXPIRED, ALREADY_REJECTED with reason UNAVAILABLE, SUPERSEDED, OUTCOME_UNKNOWN_REPLAY_CLOSED). Old expectations are in `amendment_note`. FU-AC-078 wording "closed-epoch fences" changed to "deletion tombstones and replay fences". The validator now fails if any active (non-note) column of any row contains `prepareWorkoutCommand`, `admission token`, `OPEN admission`, `CLOSED_NO_EFFECT` or `birth epoch` (case-insensitive). Exceptions: none (the `ALLOWED_WITHDRAWN` map in the validator is empty; no row states that the withdrawn protocol is still separately active).
- **M-06 / M-05 (matrix is a partial trace).** Every note that said FU-AC-130..140 close M-05 now reads "PARTIAL: ... M-05 stays open until the untraced paths in MODULE_ROUTE_ACTION_MATRIX.md section 6 are traced" (the validator rejects the old wording). FU-AC-130 gained a known/unknown inventory requirement: release-scope certification FAILS while any required path is UNKNOWN or when a KEEP capability is claimed reachable without evidence. This addition is the reissue's, not the matrix document's; it is flagged in the row note.
- **Name unification.** The gate also required the lifecycle and protocol names to be unified: states ACCEPTED, SENDING, UNKNOWN_EFFECT, HELD, SYNCED, CONFLICTED, DISCARDED (FU-AC-125 enforces one fixture for both documents). Rows 119..128 use these names as written in the current documents; old names (for example OUTCOME_EXPIRED, "pending", "conflicted" in lower case) survive only in notes or in amendment-owned rows.

## Gate follow-up round 2 (GPT-PM, head fcaa90a1: 2 BLOCKER, 5 MAJOR)
- FU-AC-014 and FU-AC-082 (acceptance) and FU-014 (definition_of_done) REWRITTEN IN PLACE: legacy writes are accepted, quarantined and repaired in DRAIN and SERVER_ONLY; only the operator-only SEALED state denies them. The earlier "denied for migrated records" wording is kept in the notes only.
- FU-AC-119 gained scenarios 11 (late legacy delete preserves newer typed sets), 13 (tombstone before conversion), 14 (forged server provenance), 15 (once-per-event quarantine count). FU-AC-125 and FU-AC-128 use one `effective_set` schema (marker kept, values erased). FU-AC-126 gained the `UNKNOWN_EFFECT` removal test. FU-AC-100 and FU-AC-103 carry additional required tests in their notes (their approved text is unchanged).

## Gate follow-up round 3 (GPT-PM, head 3d166137: 1 BLOCKER, 6 MAJOR)
- FU-AC-082 now states the outcome per session class; FU-AC-119 scenarios 16, 17, 18 added and 11, 14, 15 extended; FU-AC-125 covers the appendExists branch and the serverStateUnknown field. Notes of FU-AC-100 and FU-AC-103 cross-reference the right rows.

## Gate follow-up round 4 (GPT-PM, head ae119f26: 2 BLOCKER, 3 MAJOR)
- FU-AC-082 adds the legacy ledger and the deletion fence for never-converted sessions; FU-AC-119 scenarios 13 and 18 extended and 19, 20, 21 added; FU-AC-063 note covers the summary and head documents.

## Gate follow-up round 5 (GPT-PM, head 3bb60dd7: 2 BLOCKER, 2 MAJOR)
- The class-C ledger and fence of round 4 are removed; FU-AC-082 and FU-AC-119 (scenarios 13, 18, 20, 21) describe eager conversion, backfill at entry to DRAIN and the non-authoritative legacy delete; FU-AC-049 note covers the quarantine entries in the export.

## Gate follow-up round 6 (GPT-PM, head 7d619cb7: 1 BLOCKER, 5 MAJOR)
- FU-AC-119 gained scenarios 18b, 22, 23, 24 and an extended 21; the validator rejects the withdrawn trigger-tombstone, ledger and divergent-entry wording in the protocol document.

## Gate follow-up round 7 (GPT-PM, head 300bf9e7: 0 BLOCKER, 3 MAJOR)
- FU-AC-119 scenarios 21, 22 and 24 extended (stripped-field server delete, OPEN certifies only the scan snapshot, marker expiry).

## Gate follow-up round 8 (GPT-PM, head e1bd259b: 0 BLOCKER, 2 MAJOR)
- FU-AC-119 scenarios 21 and 24 extended for exact incarnation identity and resolved-entry redelivery.

## Pre-implementation review (independent, master 03ea66e1)
- FU-AC-119 gained scenario S25 (deletion fence) and S26 (trigger failure, watchdog, recovery), a scenario manifest and a two-run scenario 21; FU-AC-125 wording aligned with the no-export removal path.

## Pre-implementation gate round 1 (GPT-PM, head d02b2d5b: 1 BLOCKER, 5 MAJOR)
- FU-AC-119: S26 rewritten around the audit-log write inventory, S25 around the corrected deletion order, scenario 21 run B around the complete classification matrix, frozen inventory of 27 ids (S01 to S26 and S18b); FU-AC-125 gained the quota-boundary replay fixture case.

## Pre-implementation gate round 2 (GPT-PM, head 467881fc: 1 BLOCKER, 5 MAJOR)
- FU-AC-119: S26 extended (version-time no-op proof, delayed trigger after watchdog, gap-only account, parent gate blocked until O-R2 is accepted); parent criterion reworded; FU-AC-121 gained the lost-begin-acknowledgement case.

## Pre-implementation gate round 3 (GPT-PM, head 15cf0f02: 1 BLOCKER, 4 MAJOR)
- FU-AC-119: S26 gained the audit-key accounting cases (unrecoverable DELETE with repeated and concurrent passes, repeated no-op DELETE), per-class DELETE deltas, and a verdict table replacing the unconditional failure sentence; FU-AC-121 gained the lost response without a client crash.

## Pre-implementation gate round 4 (GPT-PM, head 79cd1fb0: 1 BLOCKER, 3 MAJOR)
- FU-AC-119: S26 gained the resolved-gap assertions, no-op write accounting, unverified write gaps and audit extraction cases.
