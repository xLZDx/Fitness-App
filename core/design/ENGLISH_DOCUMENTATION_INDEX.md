# Fitness App — Design Documentation English Reference Inventory

**Audit date:** October 11, 2026  
**Exact source/ref HEAD:** `f098d0a343f866023b1be9c02539d43f10f0e49b`  
**Scope:** All 13 original Markdown documents under `core/design/` (excluding newly proposed English companions).  
**Status:** COMPLETE FOLDER LANGUAGE AUDIT / HISTORICAL TRANSLATION COVERAGE — not a new/current Flutter UI approval.

## Source-by-source language classification

| Original design document | Original Git blob SHA | English status / treatment |
| --- | --- | --- |
| [p2_g5_readiness/P2_G5_READINESS_SHADOW_TELEMETRY_LIFECYCLE_CONTRACT_2026-09-12.md](p2_g5_readiness/P2_G5_READINESS_SHADOW_TELEMETRY_LIFECYCLE_CONTRACT_2026-09-12.md) | `78c32a70f2bb08cdd416086ea2e7d080dad70939` | English original; no Cyrillic |
| [reference/fitness_hud_v1/CLAUDE.md](reference/fitness_hud_v1/CLAUDE.md) | `25234e886fac645381a0bb9136b46e1ff44587ce` | [English companion](reference/fitness_hud_v1/CLAUDE.en.md) — source-identical reuse |
| [reference/fitness_hud_v1/README.md](reference/fitness_hud_v1/README.md) | `eb98a338dddda4c035d7591ae388ffeaec2366eb` | [English companion](reference/fitness_hud_v1/README.en.md) — source-identical reuse |
| [reference/full_handoff_v1/CLAUDE.md](reference/full_handoff_v1/CLAUDE.md) | `25234e886fac645381a0bb9136b46e1ff44587ce` | [English companion](reference/full_handoff_v1/CLAUDE.en.md) — source-identical reuse |
| [reference/full_handoff_v1/README_LOCAL.md](reference/full_handoff_v1/README_LOCAL.md) | `39ab6f699c3a6102d9d87e356c5b0bae3cdb98ad` | English original; no Cyrillic |
| [reference/full_handoff_v1/README.md](reference/full_handoff_v1/README.md) | `eb98a338dddda4c035d7591ae388ffeaec2366eb` | [English companion](reference/full_handoff_v1/README.en.md) — source-identical reuse |
| [reference/onboarding_v4/README.md](reference/onboarding_v4/README.md) | `c01785b66535bb83a7e86a81e96760e3da3c010c` | English technical narrative with original-language source/owner quotation; keep exact wording |
| [sptr_equipment_recognition_v4_1/SPTR_EQUIPMENT_RECOGNITION_INDEPENDENT_REVIEW_R1-R3_CONSENSUS_2026-08-21.md](sptr_equipment_recognition_v4_1/SPTR_EQUIPMENT_RECOGNITION_INDEPENDENT_REVIEW_R1-R3_CONSENSUS_2026-08-21.md) | `84fce5693dcf592cd5128e54c7f55ac7a09b653b` | English original; no Cyrillic |
| [sptr_equipment_recognition_v4_1/SPTR_EQUIPMENT_RECOGNITION_MASTER_TECHNICAL_PLAN_v4.1_CONSENSUS_2026-08-21.md](sptr_equipment_recognition_v4_1/SPTR_EQUIPMENT_RECOGNITION_MASTER_TECHNICAL_PLAN_v4.1_CONSENSUS_2026-08-21.md) | `f2b768105eeaa94b159f3ccd60d9606b3bcc9a62` | English technical narrative with original-language source/owner quotation; keep exact wording |
| [sptr_equipment_recognition_v4_1/SPTR_EQUIPMENT_RECOGNITION_MASTER_TECHNICAL_PLAN_v4.2_REMEDIATED_RC_2026-08-22.md](sptr_equipment_recognition_v4_1/SPTR_EQUIPMENT_RECOGNITION_MASTER_TECHNICAL_PLAN_v4.2_REMEDIATED_RC_2026-08-22.md) | `25801264ff045c6d2683b8b28cbcb25677f98805` | English original; no Cyrillic |
| [sptr_equipment_recognition_v4_1/SPTR_EQUIPMENT_RECOGNITION_MASTER_TECHNICAL_PLAN_v4.3_MECHANICAL_PATCH_2026-08-22.md](sptr_equipment_recognition_v4_1/SPTR_EQUIPMENT_RECOGNITION_MASTER_TECHNICAL_PLAN_v4.3_MECHANICAL_PATCH_2026-08-22.md) | `da1d35e7e1d7775a3caa43b2763edc23c8e6fbce` | English technical narrative with original-language source/owner quotation; keep exact wording |
| [sptr_equipment_recognition_v4_1/SPTR_EQUIPMENT_RECOGNITION_MASTER_TECHNICAL_PLAN_v4.4_MECHANICAL_PATCH_2026-08-22.md](sptr_equipment_recognition_v4_1/SPTR_EQUIPMENT_RECOGNITION_MASTER_TECHNICAL_PLAN_v4.4_MECHANICAL_PATCH_2026-08-22.md) | `e993c960d2aea4ab9be6ebcc23166081ac57d0f4` | English technical narrative with original-language source/owner quotation; keep exact wording |
| [sptr_equipment_recognition_v4_1/SPTR_EQUIPMENT_RECOGNITION_V4_4_GATE_CONTRACTS_AND_AC_DOD_2026-08-22.md](sptr_equipment_recognition_v4_1/SPTR_EQUIPMENT_RECOGNITION_V4_4_GATE_CONTRACTS_AND_AC_DOD_2026-08-22.md) | `f5e50b9b0a79cdf1d85399d24dbb8c3b43e28d6e` | English technical narrative with original-language source/owner quotation; keep exact wording |

**Measured:** **13/13** original Markdown documents were fetched and inspected. **Four** had zero literal Cyrillic; **nine** contained Cyrillic. Four of the nine are **two unique, byte-identical pairs** of substantially Russian reference files. Their originals share two unique source blob SHAs:

- `CLAUDE.md`: original `25234e886fac645381a0bb9136b46e1ff44587ce` → English companion blob `f8d6efe59f9e675d2768a92cf757c1090cf81430`.
- `README.md`: original `eb98a338dddda4c035d7591ae388ffeaec2366eb` → English companion blob `a3d02499961ecf1f661b3c1bc5a0a22539aa6778`.

**Four English files** were created across both original reference directories from **two source translations**, giving each original copy a local `.en.md` file. All four English companions were directly re-fetched: **0 Cyrillic, 0 broken local Markdown references, balanced code fences and source-original SHAs unchanged**. No code or project UI was altered.

The other **five** Cyrillic-bearing source files consist of:
- `reference/onboarding_v4/README.md` — actual original Russian mobile copy/UI verification examples (including mock "94% technique" explicitly flagged as unsupported);
- `sptr_equipment_recognition_v4_1/...v4.1...md` — Russian headings in a legacy technical authority plan;
- `...v4.3_MECHANICAL_PATCH...md` and `...v4.4_MECHANICAL_PATCH...md` — verbatim originally Russian review findings with historic non-approval and closure conditions;
- `...v4.4_GATE_CONTRACTS_AND_AC_DOD...md` — exact owner instruction establishing per-gate AC/DoD; remain source evidence.

**Do not delete or blindly replace the five source-attached quotations.** The surrounding technical material is English; a verbatim historical owner or reviewer sentence may need an English gloss in a future separately checked companion, not a silent rewrite of audit evidence.

## Historical HUD reference caveats

The original source called the HUD design "approved" at its historical checkpoint and described **floating glass on photos**, the original `#C9FF47` accent, a **390×844** phone reference and touch targets >=44px. These do **not** supersede newer design-system/Flutter contracts by virtue of translation alone.

Crucially, the archive's Form Coach preview **simulated pose recognition using a timer and trigonometry**. Its "94% technique" counter or every-fourth-rep error simulation must **not** be presented as verified production ML accuracy. True current App camera/ML gates and actual validation evidence take precedence. The English translated HUD README explains exact source CSS, view states, assets and simulation boundaries.

## Distinct source paths and version safety

Two directories contain byte-identical original documentation. Maintaining an English counterpart **beside each original** makes navigation reliable, while authoring the actual translation **only once per unique original blob**. The exact source SHA permits comparison and protects against silently treating duplicates as unrelated approvals.

This folder-specific result is not a claim that other historical SVG/HTML/photo/video assets, `mobile/` app UI localization, `core/DECISION_LOG.md`, Git history, maintained branches or GitHub review comments are English-only. No external independent translation-fidelity signoff or rendered Figma/UI test was performed.

**Disposition:** 13/13 design-folder original Markdown files classified; two substantive Russian source blobs translated and available beside four duplicate source paths; project PR draft, not merged.
