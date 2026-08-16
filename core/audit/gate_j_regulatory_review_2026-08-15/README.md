# Gate J regulatory review — recovered source

`GATE_J_REGULATORY_REVIEW_2026-08-15.md` is the finding list Gate J acted on. It is the output of
the "regulatory-compliance sweep" reviewer in the 14-agent expert-pack round of 2026-08-15
(task `ae31c31fdb5230dc7`), and it is where the labels **R1–R12** come from.

## Why this file exists

`core/DECISION_LOG.md` recorded Gate J as fixing R1, R2 and R6 and deferring R4, R5, R7, R8, R9 and
R11 — but it recorded only *what R4, R5 and R7 were*. R8, R9 and R11 were carried as bare labels,
and the 2026-08-16 review round could only mark them **UNKNOWN**, because inventing three findings to
fill three slots is worse than an admitted gap.

Gate G5 was opened to find the source rather than guess at it. This is it.

## Provenance, stated exactly

The reviewer's own `.output` file
(`D:\Temp\claude\d--Repo\eb11d7ac-0a37-492b-88f8-e4e0ef85eac2\tasks\ae31c31fdb5230dc7.output`)
still exists and is **0 bytes**. The surviving copy was the `result` field of one record in the
session transcript at
`C:\Users\koros\.claude\projects\d--repo\eb11d7ac-0a37-492b-88f8-e4e0ef85eac2.jsonl` — outside the
repository, on one machine, in a directory the tool rotates.

The text here was extracted from that field verbatim. Nothing was reworded, reordered, renumbered or
summarised; the only edit is trailing-whitespace normalisation at the file end. What the reviewer
wrote in 2026-08-15 is what this file says, including the parts that later turned out to be wrong.

## What it contains beyond R8/R9/R11

Twelve findings, not eleven — the log never mentioned **R3**, **R10** or **R12** at all:

| | severity | subject | recorded in DECISION_LOG before today |
|---|---|---|---|
| R1 | BLOCKER | Health Connect / HealthKit undisclosed | yes, fixed in Gate J |
| R2 | BLOCKER | "rehab-grade" therapeutic claim | yes, fixed in Gate J |
| R3 | MAJOR | no explicit Art. 9(2)(a) consent event for health data | **no — never recorded** |
| R4 | MAJOR | export promises "everything", omits photo bytes | yes, fixed 2026-08-16 |
| R5 | MAJOR | device-local claim absolute in notice, conditional in code | yes, open (G4) |
| R6 | MAJOR | `READ_HEART_RATE` declared with no consumer | yes, fixed in Gate J |
| R7 | MAJOR | insurance attestation module | yes, deleted 2026-08-16 (G1) |
| R8 | MINOR | deletion pseudonymises two shared collections | label only |
| R9 | MINOR | About page shows a clinical-review budget line | label only |
| R10 | MINOR | Crashlytics has no in-app opt-out | **no — never recorded** |
| R11 | MINOR | stale comment says progress photos are unencrypted | label only |
| R12 | MINOR | BMI bands label users with an ICD category | **no — never recorded** |

R3 is the one that matters: a MAJOR finding about the legal basis for special-category data was
dropped from the deferral list entirely, so no later gate knew to look at it. Recovering R8/R9/R11
was the stated goal; finding R3 was the reason the search was worth doing rather than guessing.

## Read it as a 2026-08-15 document

Its claims were true then and some are not true now. R11 in particular describes a stale comment
that the reviewer had already found to be stale, and R7's module has since been deleted. Each
finding's current state is resolved in the 2026-08-16 G5 entry in `core/DECISION_LOG.md`, not here.
This file is preserved evidence and is not edited as the code changes.

Verify with `python tools/evidence/validate_csv_evidence.py`.
