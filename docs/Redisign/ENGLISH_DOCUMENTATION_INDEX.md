# Fitness-App Redesign — English Documentation Index

**Reviewed:** October 10, 2026  
**Original docs/Redisign source HEAD:** `dcf428126d23f6e4145e5ab18e7d476d10e35860`  
**Proposed translation branch:** `docs/add-english-readme-20261010`  
**Status:** 15/15 UNIQUE ORIGINAL REDESIGN MARKDOWN BLOBS HAVE ENGLISH DOCUMENTATION OR ALREADY-ENGLISH CONTENT. NOT FULL REPOSITORY OR SEMANTIC REVIEW.

## Seven Source-Linked English Companions

| Original document | Original Git blob SHA | Proposed English companion |
| --- | --- | --- |
| [DEV_COMPLETION_SCOPE_v1.5.md](DEV_COMPLETION_SCOPE_v1.5.md) | `9c3b3355421eddc400387558a7f05892d9a0a90d` | [English](DEV_COMPLETION_SCOPE_v1.5.en.md) |
| [DEV_SINGLE_FILE_MASTER_PROMPT_v1.6.md](DEV_SINGLE_FILE_MASTER_PROMPT_v1.6.md) | `d3b5e7702a2cfbbe0c53c32d8abfd5784f05d0ff` | [English](DEV_SINGLE_FILE_MASTER_PROMPT_v1.6.en.md) |
| [FIGMA_DECISION_REGISTRY_SCREEN_PROMPT_v1.3.md](FIGMA_DECISION_REGISTRY_SCREEN_PROMPT_v1.3.md) | `230fc80a994c11c324f3b97f0c212590dd754525` | [English](FIGMA_DECISION_REGISTRY_SCREEN_PROMPT_v1.3.en.md) |
| [FIGMA_FINAL_MINIMUM_SCOPE_PROMPT_v1.5.md](FIGMA_FINAL_MINIMUM_SCOPE_PROMPT_v1.5.md) | `e1d91e5eddd2fb71350794ff5e80d72579faf219` | [English](FIGMA_FINAL_MINIMUM_SCOPE_PROMPT_v1.5.en.md) |
| [FIGMA_FULL_APP_REFACTOR_PROMPT_v1.3.md](FIGMA_FULL_APP_REFACTOR_PROMPT_v1.3.md) | `81538d09cb23d2c6acc8b84b61da5450128ca4cb` | [English](FIGMA_FULL_APP_REFACTOR_PROMPT_v1.3.en.md) |
| [HANDOFF_GAP_MATRIX_v1.5.md](HANDOFF_GAP_MATRIX_v1.5.md) | `7a0dd462bfecb58dd6d4b4c8e010154785a00571` | [English](HANDOFF_GAP_MATRIX_v1.5.en.md) |
| [OPEN_DECISIONS_REGISTER_v1.3.md](OPEN_DECISIONS_REGISTER_v1.3.md) | `b39a24ae56d569e764388a701c17c50a2b51c26c` | [English](OPEN_DECISIONS_REGISTER_v1.3.en.md) |

The seven original sources remain unchanged. Byte-identical `(1)` copies of some original imports have the **same source blob SHA** and are intentionally not retranslated twice. The v1.6 master English companion covers 35 numbered sections, its retained v1.3 Decision Governance appendix, Figma handoff, R0–R9 and explicit STOP/owner-GO/individual push-GO boundaries. The full v1.3 Figma master preserves the internal v1.1 header and separate v1.3 governance update; the 44-question register preserves open/locked statuses.

**QA:** Each of these seven English proposals was directly re-fetched by exact Git blob SHA: zero literal Cyrillic, zero broken relative links and no odd number of triple-backtick fence delimiters. No original feature, training metrics, camera code, consent, tests or production state was changed.

## Eight Original Unique Documents Already in English

| Original document | Source Git blob SHA | Treatment |
| --- | --- | --- |
| [DEV_SINGLE_FILE_MASTER_PROMPT_v1.7_EN.md](DEV_SINGLE_FILE_MASTER_PROMPT_v1.7_EN.md) | `4eb148d76d8495044b4381339541c4cad071d7f1` | Byte-identical to LATEST_DEV_SINGLE_FILE_MASTER_PROMPT_EN.md |
| [DEV_SINGLE_FILE_MASTER_PROMPT_v1.8_EN.md](DEV_SINGLE_FILE_MASTER_PROMPT_v1.8_EN.md) | `b2a15c7bd0ca0b586073fdade39dba04295fe5d5` | Already English |
| [DEV_SINGLE_FILE_MASTER_PROMPT_v1.9_EN.md](DEV_SINGLE_FILE_MASTER_PROMPT_v1.9_EN.md) | `fd90a31239f744075f690430987059d3fcef5ff8` | Already English |
| [DEV_SINGLE_FILE_MASTER_PROMPT_v2.0_EN.md](DEV_SINGLE_FILE_MASTER_PROMPT_v2.0_EN.md) | `3efea5a9db18b6924ddcaa1cba103095fe3cc884` | Duplicate v2.0_EN(1).md |
| [R2_SCANNER_EXECUTION_CORRECTION_v2.0.md](R2_SCANNER_EXECUTION_CORRECTION_v2.0.md) | `489b0eedd4ede0a19aeceb2d539638b63ec2ddcc` | Duplicate v2.0(1).md |
| [R2_SCANNER_SCOPE_CORRECTION_v1.9.md](R2_SCANNER_SCOPE_CORRECTION_v1.9.md) | `7cd7b1229eacfc40e0156ecca415d2ccfefad6a7` | Already English |
| [reference/emulator/README.md](reference/emulator/README.md) | `7c38e077a35bfacfc6528b97a3c32590b180ae27` | English instructions preserve literal historical screenshot/UI labels (20 Cyrillic chars) |
| [reference/prototype/README.md](reference/prototype/README.md) | `40c4af447d0e7f8ac7c316c8a9387926bc3e9e15` | English instructions preserve literal historical screenshot/UI labels (18 Cyrillic chars) |

The two screenshot-reference README files are English narratives containing original screenshot labels and user-interface quotations. They have, respectively, 20 and 18 literal Cyrillic characters. Those are source artifacts and locale text, **not** prose that should be silently replaced. Four later development master revisions are already English, and different versions are **not** interchangeable translation substitutes.

## Exact Source Inventory Arithmetic

The original `docs/Redisign` cohort has **22 Markdown source paths** but **15 unique original Git blobs** because several are byte-identical copies. Of those unique sources, **seven required English companion translations**, which were added in the existing isolated Draft PR, and **eight were already written primarily in English**. Thus the defined original documentation cohort is **15/15 covered**, without altering original files. Literal Cyrillic source labels are intentionally preserved in two reference documents.

## Historical Safety and Remaining Scope

This index does **not** approve undocumented exercise counts, on-device pose/Form Check claims, user Health Connect/photo collection, BMI classifications, subscription products, ML training or a code release. The original v1.6 developer contract prohibits a push without a **separate push-GO** and requires a STOP after each implementation gate; these historic limitations remain visible in the translation.

The broader pinned Fitness-App repo contains **320 Markdown/TXT files**, **88 Russian-named historical HTML reports with conventional English counterpart paths**, and many Dart/JSON/locale/media files. These are **not** covered by this 15-blob conclusion. Original programmatic identifiers, consent/legal source text, native app RU locale and user/customer data remain unchanged.

**Disposition:** Specific redesign-doc English text coverage completed in a draft branch; independent semantic fidelity, current implementation, other source/branch scans and authorized merge still pending.
