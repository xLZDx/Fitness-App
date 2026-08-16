# 27 — CI and release

Two workflows, read in full: `.github/workflows/flutter.yml` and `functions.yml`.

## Jobs

| Workflow | Job | Runs on | Blocking | What it actually asserts |
|---|---|---|---|---|
| flutter | analyze + test | every push to master/main, every PR, nightly 04:00 UTC | yes | `flutter analyze --no-fatal-warnings --no-fatal-infos`, then `flutter test` |
| flutter | cloud functions tsc | same | yes | `npm ci` + `npm run build --if-present` — compile only |
| flutter | integration (emulator) | **not on push** — PR, nightly, manual | yes when it runs | `flutter test integration_test/app_test.dart` on an API 34 emulator with emulated cameras |
| functions | typecheck + unit tests | push to master, PR | yes | tsc + jest |
| functions | rules tests against the emulator | same | yes | `npm run test:rules` |
| functions | account deletion e2e | same | yes | `npm run test:e2e` — deletion + multi-account isolation |
| functions | dependency audit | same | yes | `npm audit --omit=dev --package-lock-only --audit-level=high` |
| functions | deployment drift | same | yes | `npm run build` + `npx jest scaling` |

No job uses `continue-on-error`. The `functions.yml` header states this explicitly as a design rule.

## VERIFIED strengths

- Firestore **rules are tested against the emulator in CI** (§38 of the audit mandate is covered by
  a real job, not by inference from app code).
- **Account deletion has a real e2e job** including multi-account isolation (§39).
- A dependency audit gates on high-severity production vulnerabilities.
- The integration job documents *why* it is not on every push and *why* API 34 (the only level the
  suite has been measured on) — cost and evidence, not habit.

## Findings

**HIGH | VERIFIED | The analyzer cannot fail the build.** `flutter.yml:` the analyze step passes
`--no-fatal-warnings --no-fatal-infos`, so only hard errors gate. The repository currently carries
7 analyzer issues (4 `unnecessary_type_check` warnings, 1 `unused_element`, 2 style infos) that CI
will never turn red. The flag is commented as deliberate; the consequence is that warning count can
grow without limit. *Minimal fix:* keep the flag but add a step asserting the issue count has not
increased against a checked-in baseline.

**MEDIUM | VERIFIED | The working branch gets no push-triggered CI.** `flutter.yml` triggers pushes
only on `master`/`main`; `functions.yml` only on `master`. All work on `formcoach/gates-a-c` — 16
commits in this mission alone — is covered only if a pull request is open. *Minimal fix:* add the
long-lived feature branch to the push trigger, or open a draft PR per gate.

**INFO | VERIFIED | Compile-only backend check duplicated.** `flutter.yml`'s `functions-build` job
compiles the functions but runs no tests; `functions.yml` does both. Harmless, but a reader could
mistake the green tick on the first for backend test coverage.

## UNAVAILABLE

Current pass/fail state of these jobs on the remote. This audit reads the workflow definitions and
runs the suites locally (`flutter test` 2643/0, `npx jest` 165/165 on 2026-08-16); it does not query
GitHub Actions history. Closing that needs `gh run list` against the repository.
