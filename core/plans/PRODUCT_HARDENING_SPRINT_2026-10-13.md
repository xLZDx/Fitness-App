# Product hardening sprint — plan (2026-10-13)

Status: approved by the operator for implementation ("GO", 2026-10-13). One PR for the sprint. Baseline: master at the merge of PR #2 (9c4072f).
Evidence base: the nine-agent whole-project review and the four extra analyses of 2026-10-13 (see `reports/FULL_PROJECT_QA_2026-10-13.html`).

## Operator decisions (verbatim intent)

1. Fix all review findings F1–F13.
2. F1 (demo features backed only by mock repositories): **hide them in release builds** (compile-time flag; direct deep links must not bypass the hidden entry points).
3. Age: for under-18 and senior users take a **cautious path and show a warning**.
4. Exercise catalog: **fix every discrepancy and gap everywhere** (missing `purpose`, missing `muscles`, equipment that disagrees with the title, duplicated steps, truncated names, the missing clip, the quarantined id).
5. Recommendations: **make the logic use every onboarding parameter that is available**, and **add a question at recommendation time about the training context**: gym with machines; outdoors without machines or with minimal kit (bands, balls, as examples only); at home; and yoga as a separate mode that is not tied to a place.
6. Live coach: **finish all candidate exercises** on a data-driven engine.
7. Body comparison: repeat the idea of the reference video — the user photographs themselves in the gym (a trainer held the phone in the reference; a tripod works too) with an automatic countdown and shutter.

## Workstreams

| ID | Scope | Main areas | Acceptance |
|----|-------|-----------|-----------|
| WS1 | Release-safety of mock-only features (F1, F2, F9) | `mobile/lib/core/config`, router, profile/settings/exercise reference entries, marketplace booking guard, progress-photos fallback | Flag defaults to off in release; gated routes redirect home; marketplace booking cannot run against a mock listing; photo-store failure shows an explicit error, never a demo grid |
| WS2 | Deletion and webhook hardening (F3, F12) | `functions/src/index.ts`, `account_export.ts`, `scripts/ci/data_lifecycle_policy.json` | Webhook never writes user data for a deleted Auth user; tokens revoked at deletion; export and policy cover `stats/workout_sessions` and the equipment-identity server records or record an explicit exemption |
| WS3 | Silent-failure fixes (F4, F5, F6, F7, F8, F11, F13) | prefetch, reminders, router redirect, manifest, health write, batch clears, logging | Each item has a regression test or a stated reason it cannot be tested here |
| WS4 | Python tooling (F10) | `scripts/ops`, `scripts/l10n`, `scripts/catalog`, `tools/catalog` | Non-zero exit on failure, no insecure retry with credentials, timeouts, atomic writes, correct bucket names |
| WS5 | Catalog data repair | `mobile/assets/data/exercises_vendor*.json`, `scripts/catalog` | Ratchet baselines in `scripts/catalog/test_catalog_text_ratchet.py` lowered to the new, smaller gap counts; edits survive the catalog build script |
| WS6 | Honest recommendations | profile/onboarding model, safety, `plan_builder`, `suggestion_builder`, `programme_builder`, exercise filter, l10n ru/en | The 100-profile suite reports zero violations for every honesty rule it covers and no questionnaire field is dead without a documented reason; the new training-context question is persisted and drives filtering |
| WS7 | Live coach engine | `mobile/lib/features/form_check`, assets registry | Exercises load from a JSON registry through one generic classifier; at least ten exercises supported; cues in ru/en; non-clinical wording |
| WS8 | Body comparison | `mobile/lib/features/progress_photos` and a new scan flow | Guided self-timer capture with readiness checks, three-pose scan sets, aligned comparison view, consent and privacy copy updated; photos never leave the device |
| WS9 | CI signals | four failing checks on the PR #2 head (CT-1 content QA, data access policy drift guard, release build, integration emulator) | Each failure triaged: fixed, or classified as an operator-only secret/environment item |

## Order and parallelism

WS1, WS2, WS4 and WS5 touch disjoint files and start together. WS3 and WS6 share some mobile files and are sequenced by file ownership. WS7 starts with a short design step, WS8 with answers to the open product questions. WS9 runs alongside.

## Verification

Per the operator's workflow: finish the code, then test-writing agents write and run focused tests for every workstream; relevant specialist reviewers run once; valid findings are fixed in one batch; a final GPT-PM review on the exact head precedes the push and the single PR. The 100-profile and catalog ratchet suites are re-run at the end.

## Known limits

Kotlin and the emulator-based suites cannot be run on the Windows development host; they stay unverified locally and are covered by CI where it can run them.
