# Change record: hardening sprint documentation, QA reports and byte-pinning rules

## What changed
- `core/plans/PRODUCT_HARDENING_SPRINT_2026-10-13.md`: new "Revision 2" with the safety and release contracts (age policy, training context lifecycle, coach shipping, body-scan privacy boundary, release deny-by-default, deletion and webhook fence), the dependency order, the acceptance and exception register, and the F1..F13 traceability matrix. It answers the eight MAJOR findings of the GPT-PM documentation-gate review of 07d8e4a.
- `reports/FULL_PROJECT_QA_2026-10-13.html` and `.ru.html`: the whole-project QA report (nine reviewers, four extra analyses, findings F1..F13) that the plan cites as its evidence base.
- `.gitattributes`: `eol=lf` for every file whose raw bytes the CT-1 dataset registry hashes (`core/ml/datasets/**`, `core/ml/review/**`, `core/ml/DATASET_REGISTRY.json`, `core/review/worklist/**`, `mobile/assets/data/exercises_vendor*.json`). With `core.autocrlf=true` a Windows checkout produced CRLF bytes and a Linux CI runner LF bytes, so the registry verified on one machine and failed on the other.

## Why
The review rejected the plan as incomplete for implementation and verification, not on the operator's decisions. The contracts make each claim falsifiable and tie it to a test; the exception register names what is deliberately not closed, with owner and reason.

## Affected contracts and paths
Documentation and attributes only. The `.gitattributes` rule changes how those files are checked out on platforms with CRLF conversion; blobs in the index were already LF.

## Verification state
No code behaviour. The line-ending rule is exercised by the CT-1 registry check, which is re-derived from an LF checkout in the commit that regenerates the registry.
