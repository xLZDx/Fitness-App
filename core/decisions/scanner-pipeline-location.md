# Decision: `scanner-pipeline-location`

**Decision: S-1 approved, S-2 approved, S-3 approved — the council's recommended combination,
in full.**

## S-1 — where the pipeline source lives

**Approved: extract source + provenance only (~80KB of Python, ~1.3MB of logs, the JSON manifests)
into a separate, clean repository.** The evidence tree at `D:/tools/equipment-model` stays exactly
as it is and becomes read-only. Nothing is moved; source is copied. Corpora
(`dataset/`, `dataset_v2/`, `dataset_v2_thin/`, `fresh_test/`, `_roboflow_raw/`) and model
artefacts (`out/*.tflite`, `out_v2/*.tflite`) never enter git — addressed by the existing
content-hash manifests, per `core/ml/SCANNER_PROVENANCE.md`'s "S-1's recommended architecture" and
"The migration package" sections.

## S-2 — may the corpora leave this machine

**Approved: no. The corpora stay on this machine, in place, never uploaded anywhere.**
`dataset/` (1,741 files) has no recoverable per-image source record — presumptively
all-rights-reserved third-party photographs. `dataset_v2` (90,817 files) is claimed CC BY 4.0 but
its attribution manifest was never retained and must be reconstructed by re-querying the Roboflow
Universe API before that becomes impossible. Neither corpus is cleared for distribution; keeping
both local is licence-neutral, any hosted remote is a transfer to a third party.

## S-3 — does the scanner programme continue

**Approved: yes, the equipment-recognition ML programme continues.** Recorded independent of S-1/S-2:
both v1 and v2 currently measure 0/18–1/18 top-3 on real gym photos, so this is not a claim that the
current models are adequate — see the separate FITAPP-EQUIP-ACC-2026-09-17 gate (2026-09-17), which
already routes every cloud (Gemini) classifier answer through the app's "alternatives" flow rather
than presenting it as a confident identification, precisely because of this measured gap. Continuing
the programme means the preservation work above (S-1/S-2) is not academic — v1's training corpus is
the only evidence of what the currently-shipped model was trained on, needed for as long as v1 ships
regardless of whether a v3 is ever trained.

## Who decided, and how

Recorded from a live, in-session exchange with the operator (the product's sole owner —
`korostelevivan@gmail.com`), 2026-09-17, presented with the full decision package from
`core/ml/SCANNER_PROVENANCE.md` ("Where the pipeline should live — decision package", "Three
decisions, not one") including the independent MLOps/repository-architecture and
data-governance/licensing council review that arrived at S-1/S-2's recommendation. The operator's
own words: *"S-1: Одобряю вынос исходников в отдельный чистый репозиторий (Рекомендовано), S-2:
Корпуса НЕ покидают эту машину (Рекомендовано), S-3: ML-программа распознавания продолжается."*

## What this closes and what it does not

This closes the `scanner-pipeline-location` row in `core/CURRENT_STATE.md` as an operator decision
on WHERE and WHETHER, not as the migration itself — the actual repository split (S-1) is
engineering work not yet performed, tracked separately as `RESIDUAL[scanner-pipeline-location]`
per `core/ml/SCANNER_PROVENANCE.md`'s own note that building the migration ahead of the decision
would have been "engineering performed to look busy." A fresh Plan → GO is still needed before that
migration work begins, including its own CI-asymmetry hazard fix (`test_the_pin_is_dated` /
`test_the_pipeline_is_still_not_a_git_repository`, same file) landing in the same change.
