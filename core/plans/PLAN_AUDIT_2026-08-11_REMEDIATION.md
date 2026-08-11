# Audit remediation plan — 2026-08-11

Source: `core/AUDIT_REPORT_2026-08-11.md` (independent read-only review, verdict
**BLOCK** for a public production release), merged with the unfinished redesign
track (Ф3 unstarted, five R11 gates PARTIAL).

Authorised 2026-08-11 by the operator as one autonomous multi-gate run:
*"пуш + ГО все пункты и гейты автономно"*, with three decisions attached —
recorded in §0 below. Push of `3cc8126` executed under the same message.

This file is the source of truth for the run. `core/DECISION_LOG.md` carries the
per-turn narrative; this carries the gate list and its state.

---

## 0. Operator decisions that shaped the plan

| Question | Answer | Consequence |
|---|---|---|
| **A3** — complete the export, or amend the promise? | *"доводим экспорт до обещания"* | The export must reach what `public/privacy.html:89` already claims. No legal-copy edit substitutes for it. |
| **A7** — disable the ML features or label them experimental? | *"пока пропускаем, но нужен детальный план/стратегия как довести МЛ до ума и рабочего состояния, он необходим для составления индивидуальных программ и тренировок"* | A7 as a *gate* is skipped. It is replaced by a strategy document: how recognition / rep counting / posture get to a state that can drive individualised programmes. No shipping claim changes under this run. |
| **A5 / A6** — console access? | *"разрешаю доступ к Stripe/Firebase-консоли и выполнять все необходимые действия"* | Stripe and Firebase console operations are in scope for this run, not handed back as a checklist. |

## 1. Where the plan came from

v1 was drafted from the audit alone. The Rosetta Plan gate ran one matched
agent (`planner`; `security-reviewer` flagged **recommended, not spawned** per
`agent_routing.json` group `S_opt_in_only`) and moved it materially:

1. A1 and A4 were rewriting the same function four gates apart → merged.
2. A1's local photo wipe was keyed to a structure A2 later replaces → made
   directory-level, so it survives A2 either way.
3. A2 was merged with R11f, an independently XL gate → split back apart.
4. A8 bundled a real defect, stale-test triage and a redesign cosmetic → split.
5. A0 (shared data inventory) did not exist; A1 and A3 were each about to
   re-derive the same list.
6. A4 prevented new duplicate subscriptions but never reconciled existing ones.

One finding it raised as "possibly open" was measured rather than assumed: the
`iam.serviceAccounts.signBlob` grant from `DECISION_LOG.md:509-537` **is in
place** (`roles/iam.serviceAccountTokenCreator`, verified via
`gcloud iam service-accounts get-iam-policy`). That P0 is closed; only
end-to-end playback on a device remains unproven.

## 2. Gates

Order is dependency-driven, not severity-driven. Each gate is its own commit.

| # | Gate | Scope | State |
|---|---|---|---|
| **A0** | Data inventory | Every uid-bearing store, server and on-device, with its delete path and its export path. Markdown + CSV twin. Feeds A1 and A3. | |
| **A1** | Account deletion completeness | `deleteAccount` also sweeps `coach_bookings` + `equipment_reports`; cancels **every** subscription, not one id; client wipes local health blob and the photo directory **at directory level**; the server test stops pinning incomplete deletion as correct; one live multi-account check in-gate. | |
| **A6-lite** | Cost bleed | `enforceAppCheck` in monitoring posture, per-UID/device quotas, budget alert. Ahead of its siblings because it is the only finding losing money now rather than at release. | |
| **A4** | Stripe duplicate subscriptions | Idempotency key on checkout creation, server-side active-subscription pre-check, and reconciliation of duplicates that already exist. | |
| **A3** | Export completeness | Export reaches the promise in `public/privacy.html:89`: recognition history, machine cards/notes, generated exercises, subscriptions/receipts, equipment reports, coach bookings, donor entry, debug telemetry — and a decision, recorded, on photo bytes. | |
| **A2-sec** | Progress-photo hardening | UID-scoped directory + index + key, key into Android Keystore, plaintext camera temp deleted, "end-to-end encryption" copy corrected to what it is. R11f's seven remaining flow states are **not** in this gate. | |
| **A5** | Stripe deployment drift | Verify the endpoint's API version first; deploy the Acacia/Basil fix and replay test-mode events of both formats only if that verification says it is needed. Placeholder redirect domains (`index.ts:497`, `:1033-1034`) fixed here. | |
| **A8-lite** | Home CTA overflow | `mobile/lib/features/home/home_page.dart:475-489` — bare `Text` in a `Row`. Stale integration-test triage is P1, not this gate. | |
| **A6-full** | App Check enforcement | Staged enforcement, anonymous-trial rotation protection, cost anomaly alerts. | |
| **S1** | ML strategy (replaces A7) | Document: what each ML feature actually measures today, what "working" means for individualised programmes, and the measurement path to it. No behaviour change. | |

Then P1 (rules emulator tests, deletion + multi-account e2e, mock disclosure,
entitlement loading/error states, fail-closed CI, platform scope) and P2
(bundled fonts, accessibility, photo thumbnails/pagination, cache LRU, doc
refresh, production manifest), then the redesign remainder: Ф3, bug 5, bug 6's
programme-card half, R11f/R11h/R11b's open states, Paywall (still HELD on
pricing).

## 3. Scope-trigger acknowledgement

This run is far past the >2h / 15-file / 350-line line that normally forces a
split proposal before building. The rule permits an explicit operator override
and *"ГО все пункты и гейты автономно"* is one. Recorded here so the size is
not later mistaken for scope creep.

## 4. Execution status — 2026-08-11, 16:05 local (Europe/Chisinau) / 13:05 UTC

| Gate | Status | Commit |
|---|---|---|
| **A0** Data inventory | **DONE** | `2953bc3` |
| **A1** Account deletion | **DONE** | `1aee73b` + `e54bbef` |
| **A4** Stripe duplicates | **DONE** except reconciliation of pre-existing duplicates | `1aee73b` + `e54bbef` |
| **A8-lite** Home CTA overflow | **DONE** | `b481dd0` |
| Act gate (Rosetta) | **DONE** — 2 units, 6 findings, 4 fixed, 1 deferred, 1 rejected | `e54bbef` |
| **A6-lite** Cost bleed | **DONE** except the budget notification rule (attempt did not apply) | `ec5aae4` + `d7335c0` |
| Act gate on A6-lite | **DONE** — 3 findings, all 3 fixed | `d7335c0` |
| **A3** Export completeness | **DONE** — server assembler + client merge; photo bytes still excluded | `7a73cbf` + `4c81fbe` |
| **A2-sec** Photo hardening | **DONE** — key in the Keystore, per-uid store, temp deleted, copy corrected | `1ef60f6` + act-gate fixes |
| **A5** Stripe drift | **DONE** except the endpoint's live API version (secret access denied by the environment) | `af6dc6a` |
| **A6-full** App Check | **DONE** — staged flags + anonymous-trial guard; budget `notificationsRule` still unset | `af6dc6a` |
| Act gate on A2-sec | **DONE** — 2 BLOCKER, 2 MAJOR, 1 MINOR, all 5 closed | act-gate commit |
| **S1** ML strategy | **DONE** — `core/plans/ML_STRATEGY_2026-08-11.md` | `1cd9a72` |
| **P1a** Rules emulator tests | **DONE** — 27 tests; found and closed two `firestore.rules` gaps | `7a31d3c` |
| **P1b** Fail-closed CI | **DONE** — 4 jobs; found two live production advisories, both fixed | `7a31d3c` |
| **P1c** Platform scope | **DONE** — `core/PLATFORM_SCOPE.md` | `7a31d3c` |
| **P1d** Entitlement states | **DONE** — paywall no longer shown to paying users on cold start or stream error | `55cb4ae` |
| **P1e** Duplicate reconciliation | **DONE** — repairs pre-A4 double charges on the webhook | `55cb4ae` |
| **P1f** Deletion + multi-account e2e | **DONE** — 8 tests, real Admin SDK against the emulators | this commit |
| **P1g** Device photo-capture ordering | **BLOCKED** — needs hardware | |
| Mock disclosure (P1) | **already closed** before the gate ran (see below) | |
| P2 / redesign remainder | not started | |

**Audit finding that no longer holds.** `AUDIT_REPORT_2026-08-11.md:35` says
`/community` uses an undisclosed in-memory mock. It is disclosed:
`app_router.dart:337` routes `/community` to `team_feed_page.dart`, which
renders `DemoDataBanner` at `:39` gated on `teamFeedIsDemoProvider` (`:31`,
defined at `team_feed_providers.dart:15-18`). Closed by an earlier gate in this
same remediation round; no work needed.

**Resume point.** The next gate is **A2-sec**, after an Act gate on A3's two new files (`functions/src/account_export.ts`, `mobile/lib/features/data_export/server_export.dart`). A3's shape is
already decided and does not need re-deriving: `core/DATA_INVENTORY_2026-08-11.md`
§"What this fixes in the two dependent gates" lists exactly which collections
`buildExport` is missing, and each has a repository with an `exportAll()`
already (the pattern `WorkoutLogRepository.exportAll()` established). The one
open question inside A3 is photo BYTES — excluded today by a comment in
`data_export.dart:13-22` that `public/privacy.html` does not repeat.

**Push state.** `c496a13` is on `origin/master`. Everything after it is local
and awaiting a push-GO.

## 4b. Run outcome — 2026-08-11, 19:40 local (Europe/Chisinau) / 16:40 UTC

**Shipped:** `1.0.0 (2344)` from `e8ad0a7`, 103.5 MB arm64, to
korostelevivan@gmail.com with release notes naming what changed, what to check
and what is knowingly not ready.

**Not started, and named in the operator's GO:** P1, P2, and the redesign
remainder — Ф3, bug 5, bug 6's programme-card half, R11f/R11h/R11b, Paywall
(still HELD on pricing). The run covered A2-sec + its act gate, A5, A6-full,
S1, the deploy and the build, then stopped.

**Still open inside the gates that are done:**

- The live Stripe endpoint's API version was never read — `STRIPE_SECRET_KEY`
  access is refused by the environment's permission classifier. The
  Acacia/Basil reader handles both layouts by construction, so the deploy is
  safe either way; what is unknown is whether an incident existed.
- The budget `notificationsRule` on `projects/988522745882` is still empty.
- UI labelling of scanner / Form Coach / Posture as experimental — audit
  recommendation 7, and the one item `ML_STRATEGY_2026-08-11.md` names as
  gate-worthy before release.
- No device verification of the Keystore migration, the per-uid photo
  directory or the camera-temp delete. The shipped build is the first
  execution.

**Machine-level change made under a separate operator approval:**
`D:\.gradle\gradle.properties` now sets
`systemProp.javax.net.ssl.trustStoreType=Windows-ROOT` (backup:
`gradle.properties.bak-20260811`). Without it no new Maven artifact can be
downloaded on this machine — NetLimiter intercepts TLS and the previous
explicit truststore held no proxy CA.

## 5. Closing condition

Per "Ship the Build to the Tester, With Real Release Notes": the run ends with
a build distributed through `scripts/dev/build_release.ps1 -Distribute`, with
notes in user-visible terms naming what changed, what to check, and what is
knowingly still broken. A build whose tests do not pass is reported, never
shipped.
