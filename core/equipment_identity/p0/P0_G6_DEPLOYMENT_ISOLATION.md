# P0.G6 — Functions deployment isolation decision

Status: CLOSED, strategy **SEPARATE_FIREBASE_CODEBASE** (pending push/remote-sync
verification — see §7 below). This is the final P0 gate — P0 aggregate
verification follows this close.

Purpose (per `SPTR_EQUIPMENT_RECOGNITION_V4_4_GATE_CONTRACTS_AND_AC_DOD_2026-08-22.md`
P0.G6): decide, with evidence, how a new ML/Vertex/vector-search workload
is added to the existing shared, multi-domain Functions codebase without
risking already-shipped paths, especially `stripeWebhook`. Story AC,
verbatim: "a deliberately-broken identity-module TypeScript error does NOT
block a `stripeWebhook` hotfix deploy under the chosen design — this is
the actual acceptance test, not an architectural assertion."

Strategy was already fixed by the gate contract's own task table wording
(T1's corrected note) and GPT-PM's P0.G5 reply: **(a) separate Firebase
codebase**, not (b) selective-deploy-within-one-codebase — chosen because
it gives the strongest possible isolation guarantee (a wholly separate
`tsc` compilation unit, dependency tree, and CI job) with no ongoing
per-deploy discipline required from a human.

## 1. What was built

| File | Role |
|---|---|
| `firebase.json` | Now declares two `functions` entries: `default` → `functions/`, `equipment-identity` → `functions-equipment-identity/`. |
| `.github/workflows/equipment-identity-functions.yml` (new) | A CI workflow file wholly separate from `flutter.yml`'s `functions-build` job — a break here cannot block or share a job with the default Functions pipeline. |
| `scripts/equipment_identity/verify_deployment_isolation.py` | The real build/compile isolation proof (8 steps, detailed in §3). |
| `scripts/equipment_identity/test_deployment_isolation.py` | 9 tests wrapping those 8 steps. |
| `core/equipment_identity/p0/p0_g6_isolation_evidence.json` | The recorded evidence, in the exact shape the gate's implementation plan specified. |
| `functions/package.json` | `deploy` script narrowed from `firebase deploy --only functions` to `firebase deploy --only functions:default` (§5 — this was a real, live accidental-dual-deploy risk, not a hypothetical). |
| `functions-equipment-identity/package.json` | Gained a matching `deploy` script: `firebase deploy --only functions:equipment-identity`. |
| `core/PHASE_4B_STRIPE_SETUP.md`, `scripts/catalog/provision_video_bucket.py` | Three bare `firebase deploy --only functions` references narrowed to `functions:default` (§5). |

No file under `functions/src/` was modified. No `IDENTITY` scaling profile
was added to `functions/src/scaling.ts` — per the gate contract's own T2
correction (AC-M02), that task applies only under strategy (b); strategy
(a) makes it `NOT_APPLICABLE`.

## 2. Why strategy (a), restated

A shared/selective-deploy codebase (b) would still compile the identity
module and the default module through the *same* `tsc` invocation before
Firebase can decide what to deploy — a broken identity file would fail
that single compile and block everything, including a `stripeWebhook`
hotfix. Only a genuinely separate codebase — its own `package.json`, its
own `package-lock.json`, its own `tsc` run, its own CI job — makes "the
identity module doesn't compile" structurally unable to touch the default
module's build. §3 proves this is not just an architectural claim.

## 3. The real isolation proof (§11.4 of the implementation plan)

`verify_deployment_isolation.py` runs eight real steps, none of them a
string assertion standing in for an actual build:

1. `firebase.json` declares exactly the two expected codebase → source
   mappings.
2. `functions/package-lock.json` and `functions-equipment-identity/package-lock.json`
   are real, distinct files (not byte-identical, not shared).
3. No file under `functions/src/**/*.ts` references
   `"functions-equipment-identity"` — the default codebase cannot import
   what it must not depend on.
4. `npm --prefix functions run build` → `PASS`.
5. `npm --prefix functions-equipment-identity run build` → `PASS` (normal
   state).
6. **The core invariant.** `functions-equipment-identity` is copied to a
   disposable temp directory (never the tracked source). A deterministic
   TypeScript compile error (`const __p0g6_deliberately_broken:
   ThisTypeDoesNotExistAnywhere = 1;`) is appended to the temp copy only.
   That temp copy's build is proven to fail (`returncode != 0`). **Then,
   while that broken copy still exists on disk**, `npm --prefix functions
   run build` is run again against the REAL default codebase and proven to
   still pass (`returncode == 0`). Cleanup runs in `finally`; the test
   suite additionally asserts the tracked identity source is
   byte-identical before and after the probe.
7. `firebase --version` is recorded (`15.17.0` — supports the codebase/
   targeted-deploy syntax used throughout). No deploy is ever invoked by
   this script — `test_no_production_deploy_command_appears_anywhere_in_this_module`
   asserts the module's own source never contains a `firebase deploy`
   call.
8. `npm --prefix functions test` (the existing Stripe/account Jest suite)
   → `PASS`, unmodified.

Measured locally (Windows, JDK 17 available): step 6's broken-copy build
returned `1`; the default build while it existed returned `0`. This is
the literal Story AC — proven by a real subprocess run, not asserted.

**Scope note (security-reviewer, §6):** step 6 proves npm/tsc-level
compile isolation. It does not exercise the Firebase CLI's own
predeploy-hook scoping — no `firebase deploy --only functions:default
--dry-run` is run here, by design, since this gate never performs a real
deploy. That the CLI actually skips the identity codebase's predeploy
hook when only `default` is targeted is documented firebase-tools
behavior, inherited from vendor docs rather than verified end-to-end by
this script.

## 4. Stripe regression (§11.5)

Beyond the base suite already covered by step 8 above, the emulator-backed
suites were run locally (JDK 17 was available, so these are not cited as
"current CI" placeholders):

```
npm --prefix functions run test:rules   -> 64/64 passed
npm --prefix functions run test:e2e     -> 11/11 passed
```

No Stripe source file was modified by this gate.

## 5. The accidental-dual-deploy risk found and fixed

Per GPT-PM's own P0.G5 review-round ask for G6 ("docs/scripts must not
recommend a generic `firebase deploy --only functions` that could
accidentally deploy both"): grepping the repo for that exact bare command
found it was genuinely live in four places, not hypothetical —
`functions/package.json`'s own `deploy` npm script, and three references
in `core/PHASE_4B_STRIPE_SETUP.md`/`scripts/catalog/provision_video_bucket.py`.
Now that `firebase.json` declares both codebases, running any of these
as originally written would deploy `equipment-identity` alongside
`default` on every Stripe-only hotfix — exactly the risk this gate exists
to prevent, sitting in the very docs a maintainer would actually follow.
All four now say `functions:default` explicitly (§1). Other existing
per-function-targeted references (`functions:clipUrl,functions:clipUrls`,
`functions:createCheckoutSession`, `functions:generateAnnualReceipt`) were
left untouched — naming specific functions is already unambiguous
regardless of how many codebases exist.

## 6. Review record (P0.G6)

Three independent cold-read reviewers, per the gate's own implementation
plan: `security-reviewer`, `silent-failure-hunter`, and a backend/release-
angle reviewer (`code-reviewer`, standing in — no project-scoped backend/
release reviewer exists in this repo's roster). `code-reviewer`'s first
completion notification arrived with no findings text at all; a follow-up
message asking it to restate its complete answer succeeded on the second
attempt (same recovery pattern already used once on P0.G5's
`security-reviewer`).

**security-reviewer** — 4 of 5 questions NO ISSUE, 1 MINOR:
- Isolation is structural (separate `package.json`/`package-lock.json`/`tsc`
  invocation/firebase.json codebase entry), and the compile-time half is
  proven empirically by a real subprocess run, not a mocked assertion —
  NO ISSUE.
- No bare `firebase deploy --only functions` remains live anywhere except
  a historical, already-executed decision-log entry predating this second
  codebase — NO ISSUE.
- No command-injection/path-traversal risk in `verify_deployment_isolation.py`:
  every subprocess call is list-form with `shell=False`; every path is
  derived from the script's own file location plus hardcoded literal
  subdirectory names, never from untrusted input — NO ISSUE.
- Broken-probe cleanup is structurally safe, not just "robust": the
  injected TS error is only ever written under a fresh OS temp directory,
  never to the tracked `functions-equipment-identity` path, so even an
  ungraceful kill before the `finally` block runs cannot leave a broken
  tracked file — NO ISSUE.
- The three CI workflow files (`flutter.yml`, `functions.yml`,
  `equipment-identity-functions.yml`) each have their own
  `concurrency.group` and their own `cache-dependency-path`, so there is
  no group collision or cache-key collision between the identity job and
  the default job — NO ISSUE.
- **MINOR (accepted, documented, not fixed):** what §3 step 6 proves is
  npm/tsc-level isolation, not Firebase CLI's own predeploy-hook scoping —
  nothing in this gate actually runs `firebase deploy --only
  functions:default --dry-run` to empirically confirm the CLI skips the
  identity codebase's predeploy hook. That behavior is documented
  firebase-tools functionality but is inherited from vendor docs, not
  verified end-to-end here. Recorded as an open, accepted gap rather than
  fixed in this gate — see the note added to §3 above.

**silent-failure-hunter** — 3 MAJOR, 1 NO ISSUE, 1 NO ISSUE with a MINOR
reliability note, all now addressed:
- **MAJOR, fixed:** `run_broken_identity_probe()` treated *any* non-zero
  return code from the broken-copy build as proof the injected error
  caused the failure, with no baseline build before injection and no
  check that the injected identifier actually appears in the build
  output — an unrelated toolchain failure (a corrupted copy, a flaky
  `npm ci`) would have reported PASS for the wrong reason. Fixed: a
  baseline build is now required to succeed before injection, and the
  post-injection failure is now required to actually name the injected
  marker in its own output.
- **MAJOR, fixed:** `main()` was never exercised by any test — only its
  constituent functions were tested in isolation, so a regression in
  `main()`'s own sequencing or error handling would not have been caught.
  Fixed: `test_main_runs_end_to_end_and_exits_zero` now runs the script as
  a real subprocess and asserts exit code 0 plus all eight step markers
  in stdout.
- **MAJOR, fixed:** the "no production deploy command anywhere" test did a
  source-text grep for two literal spellings of a deploy call — trivially
  defeated by any differently-shaped call site. Fixed at the root: `_run()`
  now refuses any command whose arguments contain `"deploy"`, and the test
  was rewritten to assert that runtime refusal instead of grepping source
  text.
- NO ISSUE: no `_run()` result is silently swallowed — every call site
  checks `returncode`, either directly or via a pytest assertion that
  includes `stderr`.
- NO ISSUE, MINOR reliability note (fixed): the isolation-verification CI
  job's 10-minute timeout was tight against the module's own 300-second
  per-subprocess timeout across multiple sequential builds. Fixed:
  `equipment-identity-functions.yml`'s `deployment-isolation-verification`
  job timeout bumped 10→15 minutes.

**code-reviewer (backend/release angle)** — 1 MAJOR fixed, 1 MINOR fixed
(2 sub-issues), 1 MINOR fixed, 1 MINOR accepted/documented, 1 NO ISSUE:
- **MAJOR, fixed:** `core/PHASE_4B_STRIPE_SETUP.md`'s "First deploy" step
  still read `firebase deploy --only firestore:rules,functions` (bare
  `functions`, not `functions:default`) — a live, first-deploy-from-scratch
  instruction that would deploy both codebases together once the identity
  codebase exports anything, in the same doc where a later step was
  already correctly narrowed. Fixed: now reads
  `firebase deploy --only firestore:rules,functions:default`.
- **MINOR, fixed:** CI convention parity — the new workflow matches
  `flutter.yml`'s trigger/concurrency/Node-setup conventions well, but the
  closer sibling is actually `functions.yml` (the dedicated default-codebase
  backend workflow), which the new workflow didn't mirror for its
  dependency-audit job (added after a real prior production CVE incident
  in a payment-adjacent dependency); also a cosmetic concurrency-group
  naming inconsistency. Fixed: added an `audit` job
  (`npm audit --omit=dev --package-lock-only --audit-level=high`, verified
  locally to exit 0) and changed the concurrency-group name to the
  literal `equipment-identity-${{ github.ref }}` to match `functions.yml`'s
  own convention.
- **MINOR, fixed:** release-process discoverability — the second codebase
  was documented only inside the gate/design docs, not in the
  general-purpose Stripe/first-deploy runbook a maintainer would actually
  follow. Fixed: added a paragraph at the top of
  `core/PHASE_4B_STRIPE_SETUP.md`'s "Deploy steps" section noting the
  second codebase exists and pointing to this doc.
- **MINOR (accepted, documented, not fixed):** cross-codebase
  function-deletion risk — the gate's own recorded evidence confirms the
  Firebase CLI version supports codebase syntax and that build/compile
  isolation holds, but never exercises a real or dry-run deploy to
  empirically prove per-codebase deletion scoping (i.e., that deleting a
  function from the identity codebase can't cause Firebase to propose
  deleting a default-codebase function). `--only
  functions:<codebase>` is the documented, generally-sufficient
  mitigation and is used consistently throughout — this is an asserted,
  not tested, claim. Deferred to when the identity codebase ships its
  first real function, per the reviewer's own suggested fix
  (`firebase deploy --only functions:equipment-identity --dry-run`,
  recorded and reviewed at that time).
- NO ISSUE: `firebase.json`'s `ignore` arrays are not what provides the
  isolation — the two `functions` entries point at distinct sibling
  source directories, so one codebase's build output has no path into the
  other's deploy payload regardless of what's in `ignore`.

No BLOCKER was raised by any reviewer. The two accepted MINORs above (both
about an un-exercised real/dry-run Firebase deploy) are deliberately
deferred, not silently dropped — both require the identity codebase to
actually export a function before a dry-run deploy against it would prove
anything, which is out of scope for P0 (the identity codebase still
exports nothing by design, per §1).

## 7. Close conditions (P0.G6 §11.8)

- [x] Separate codebase implemented (§1).
- [x] Default and identity build independently (§3, steps 4-5).
- [x] Deliberately broken identity build fails (§3, step 6).
- [x] Default build succeeds while identity is broken (§3, step 6).
- [x] Existing default backend regressions remain green (§4).
- [x] No production deploy occurred (§3, step 7; `productionDeployPerformed: false`
      in `p0_g6_isolation_evidence.json`).
- [x] Rollback documented (§8 below).
- [x] CI contains an independent identity job
      (`.github/workflows/equipment-identity-functions.yml`, wholly separate
      from `flutter.yml`).
- [x] Reviewers: no unresolved BLOCKER/MAJOR (§6) — 3 reviewers, 0 BLOCKER,
      4 MAJOR all fixed, 3 MINOR fixed, 2 MINOR accepted/documented as
      deferred (both require a real deployed identity function to test
      further, out of scope for P0).
- [ ] Commit pushed/synced — pending, see the close-out step below.

## 8. Rollback / failure handling

Per `p0_g6_isolation_evidence.json`'s `rollback` field: remove the
`equipment-identity` entry from `firebase.json`'s `functions` array; the
`default` codebase is completely untouched by that removal (no shared
config, no shared scaling profile, no shared `tsc` project). The identity
codebase was never production-deployed in P0 — `src/index.ts` still
exports nothing, so even an attempted deploy today would publish zero
functions. If the broken-identity probe itself ever fails partway through
(e.g. the temp `npm ci` fails), `run_broken_identity_probe`'s `finally`
block removes the temp directory and re-asserts the tracked identity
source is unmodified before propagating the error — no test run can leave
a broken source file in the working tree.
