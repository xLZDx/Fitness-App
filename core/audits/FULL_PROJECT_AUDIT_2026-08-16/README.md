# FULL_PROJECT_AUDIT 2026-08-16

Forensic audit of SPTR against `formcoach/gates-a-c` @ `f965302`. Start with
`00_EXECUTIVE_SUMMARY.md`, then `37_FINAL_VERDICT.md` and `29_FINDINGS.csv`.

Every number here was produced by a command that can be re-run against the shipped assets and the
working tree. Nothing was carried forward from an earlier document without re-measurement, and where
a document disagreed with the code, `31_CONTRADICTIONS.md` records which one the evidence supports.

## Produced

| File | Contents |
|---|---|
| `00_EXECUTIVE_SUMMARY.md` | The three blockers, what is well built, what could not be verified |
| `01_REPO_BASELINE.md` | Branch, HEAD, upstream, tree state, instruction sources |
| `02_ARCHITECTURE_MAP.md` | Measured scale and feature surface |
| `03_FILE_INVENTORY.csv` | 1,058 files classified by domain and sensitivity |
| `04_CLAIM_LEDGER.csv` | 930 claim candidates across 224 files |
| `05_PRODUCT_FLOW_MATRIX.csv` | 32 routes with reference and test counts |
| `06_FIGMA_PRODUCTION_DRIFT.csv` | UNAVAILABLE, with what would close it |
| `07_EXERCISE_INVENTORY.csv` | All 1,887 rows, 28 columns, per-row quality status |
| `08_EXERCISE_MEDIA_SEMANTIC_AUDIT.csv` | What was automated, and what needs human review |
| `09_MEDIA_COVERAGE.csv` | Clip and poster coverage |
| `10_EQUIPMENT_INVENTORY.csv` | 69 machines with alias and exercise counts |
| `12_MODEL_INVENTORY.csv` | 4 models, provenance separated from vendor-pretrained |
| `13_FORM_CHECK_AUDIT.csv` | 8 pose targets over 540 exercises |
| `14_PERSONALIZATION_INPUT_MATRIX.csv` | 37 questionnaire fields, collected vs actually used |
| `19_FEATURE_REALITY_MATRIX.csv` | Designed / implemented / reachable / tested / safe, kept separate |
| `20_EQUIPMENT_EXERCISE_MATRIX.csv` | The bipartite graph |
| `22_HEALTH_SAFETY_AUDIT.md` | Injury filtering, health inputs, refusal path, pregnancy |
| `23_FEMALE_HEALTH_AUDIT.md` | Cycle logic - dead code, and the dangerous version already removed |
| `24_PROGRAMME_QUALITY_AUDIT.md` | The filler and the bypassed gate |
| `25_AI_COACH_AUDIT.md` | What the coach actually is, and what it is not guarded by |
| `26_SECURITY_AUDIT.md` | Rules, functions, deletion, secrets, photos - with its own open list |
| `27_CI_RELEASE_AUDIT.md` | Eight jobs, what each really asserts |
| `28_DEAD_CODE_AUDIT.md` | 7 unreferenced providers, and a correction to an earlier count |
| `29_FINDINGS.csv` | All 27 findings in the required format |
| `31_CONTRADICTIONS.md` | Where two sources disagree, including this audit with itself |
| `32_UNVERIFIED_CLAIMS.md` | 17 areas that need a device, a clinician or a live project |
| `34_AGENT_REVIEW_MATRIX.md` | Reviewers, corroboration, and where one was overruled |
| `36_PRIORITIZED_REMEDIATION_PLAN.md` | P0-P3, not started |
| `37_FINAL_VERDICT.md` | Per-area status |
| `48_PROVIDER_INVENTORY.csv` | 196 providers with lifecycle and reference counts |

## Not produced, and why

The mandate lists 38 artefacts. Nine were not written, in every case because writing them would have
meant presenting unread territory as audited:

- `11_SCANNER_AUDIT.md` - the pipeline needs a device session; the static parts are in
  `12_MODEL_INVENTORY.csv` and `19_FEATURE_REALITY_MATRIX.csv`.
- `15_PROGRAMME_INVENTORY.csv` - seven programmes are covered narratively in
  `24_PROGRAMME_QUALITY_AUDIT.md`; a per-programme volume and progression table needs the semantic
  review that `32_UNVERIFIED_CLAIMS.md` marks unavailable.
- `16_FIREBASE_DATA_MAP.md` - the collection-level facts are in `26_SECURITY_AUDIT.md`; retention and
  backup policy was not inspected.
- `17_PRIVACY_DATA_INVENTORY.csv` - partially covered by
  `14_PERSONALIZATION_INPUT_MATRIX.csv` and `26_SECURITY_AUDIT.md`.
- `18_TEST_INVENTORY.csv` - the test-forensics reviewer inspected 4 of 264 files and declined to
  report the rest; a per-file false-green column would have been invention.
- `21_DOC_CODE_DRIFT.csv` - `04_CLAIM_LEDGER.csv` holds the candidates; only the high-consequence
  subset was verified.
- `30_EVIDENCE_INDEX.csv`, `33_REPRODUCIBILITY_MATRIX.csv` - every claim already carries its
  file:line or the command that produced it.
- `35_QA_ADVERSARY_REPORT.md` - the adversarial attack list was not run as a separate final pass.

`FULL_PROJECT_AUDIT.json` was likewise not produced.

## Status

**Audit only. No source file was changed.** The remediation plan has not been started; it awaits an
explicit `REMEDIATION-GO`.
