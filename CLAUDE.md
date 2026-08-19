> **Inherits global rules from `D:\Repo\CLAUDE.md`** — approval gate, no-guessing, regression
> tests, git lifecycle (including todo-in-commits), shell pre-approval. Read that file too.

# Fitness App — router

This file is deliberately thin: it is re-sent on **every** turn, so detail lives in `core/` and is
read on demand. Start with the table below.

| Need | Go to |
|---|---|
| **Which file do I open?** — per-feature map with entry points and file counts | `core/CODEMAP.md` |
| The rules a change is reviewed against (layout, iOS portability, injury filtering, testing) | `core/CONVENTIONS.md` |
| Index of all docs, tiered by who reads them | `core/INDEX.md` |
| Stack versions, key decisions, toolchain paths | `core/TECHSTACK.md` |
| **Any bug report — read this before theorising** | `core/DEBUGGING.md` |
| Stripe test-mode price IDs and secret slots | `core/PHASE_4B_STRIPE_SETUP.md` |
| What to build next | `core/plans/` |
| Conventions for non-Claude agents + the agent cadence | `AGENTS.md` |
| Master 75-feature list | `FITNESS_APP_TASK_LIST.md` (repo root, tracked) |

`core/business/` holds positioning, competitor and fundraising material. It contains **no
engineering facts** — skip it for code work.

## Facts worth not re-deriving

- **Layout:** `mobile/` Flutter app · `functions/` Cloud Functions (TypeScript) · `wear/` Wear OS
  companion (Kotlin) · `core/` docs · `scripts/` PowerShell dev+ops · `logs/sessions/<latest>/`
  per-session debug captures.
- **Stack:** Flutter + Dart, Riverpod for state, go_router for routing, Firebase
  (Auth/Firestore/Storage/Functions), Stripe in **test mode**.
- **Android ships first, but every choice must accommodate iOS** — full rule in
  `core/CONVENTIONS.md`. The `HealthService` interface is the Health Connect ↔ HealthKit seam;
  do not bypass it.
- **Tests:** `mobile/test/` (216 files, 1,976 tests as of 2026-08-12) runs on the host — `flutter test`. The catalog
  build scripts have their own suite: `python -m pytest scripts/catalog/ -q` (74 tests). There IS also
  `mobile/integration_test/app_test.dart`, which drives the real app on a device or emulator and is
  the only thing that can see the native ML Kit bridge and what actually ends up in the APK. It
  needs hardware; `flutter test` does not run it.
- **Verify loop:** `/fitness-verify` — analyze, test, `scripts/dev/audit_doc_links.ps1`, and a real
  build+install on `Pixel_API_34` for UI changes.
- **Vendor library lives at `D:\Downloads\Video\New folder`** (operator, 2026-08-04) — the 45 GB
  `4K UHD 2160P.zip`, `1500+ exercise data.xlsx`, `EXERCISE LIST.xlsx`, plus 1080p/720p/vertical
  renditions and the illustrations pack. It is NOT under `D:\Downloads\` directly; three catalog
  scripts pointed there and had been failing, which was mistakenly written up as "the vendor bundle
  is not present on this machine". Never hard-code it again: `scripts/catalog/vendor_paths.py` is
  the single definition, overridable with `FITNESS_VENDOR_DIR`. With it correct,
  `python scripts/catalog/build_vendor_catalog.py` runs end to end here — measured 2026-08-04:
  1,887 rows generated against 1,887 on disk, no drops.

- **Equipment recognition has TWO anchors, not one** (2026-08-07). The classifier is the weaker
  of them: measured against the operator's own 30 gym photos, v2 (29 classes) scores **top-3 5/18
  (28%)** on the frames that can be labelled, while the machine's own printed name identifies
  **18/18**. `machine_text_anchor.dart` reads that name and runs BEFORE the classifier; it is
  near-certain when it fires and silent otherwise. Numbers and per-frame evidence:
  `core/plans/B5b_TEXT_ANCHOR_2026-08-07.md`, `mobile/assets/models/README.md`,
  `D:\tools\equipment-model\gym_photos_truth.json`.
  Do not "simplify" the anchor to return one answer — returning a list is what stops a
  six-exercise cable-station decal being read as a shoulder-press machine.
- **The operator's 30 gym photos are TEST data.** `D:\Downloads\Photos-1-001 (1)`. They are the
  only real-world sample the project has; training on them buys a slightly better model and
  destroys the ability to know whether it is better.
- **Release builds go through `scripts/dev/build_release.ps1`** (2026-08-07). It derives
  `GIT_SHA`/`BUILT_AT` rather than accepting them, so B6's session header can never ship reading
  "unknown". Defaults to `--split-per-abi` (~98 MB arm64) instead of the ~244 MB fat APK, of which
  ~207 MB was native libs for three ABIs. `-Bundle` for Play, `-Distribute` to send to testers.
- **Wear pairing is currently broken for RELEASE installs** and not because of the package rename.
  `wear/build.gradle.kts` declares no `signingConfig`, so its release build is debug-signed while
  the phone's is signed with the upload key; the Data Layer pairs on applicationId **and** signing
  key. The ids match and `/workout_state` matches — signing is the remaining condition. Untouched
  on purpose: signing changes need their own explicit GO.

## Keeping docs true

Adding or removing a feature means updating `core/CODEMAP.md` in the same commit. Moving or
deleting anything a doc names means `scripts/dev/audit_doc_links.ps1` must still exit 0.

## History — 423 commits, and the shape they came in

36 commits in May, **none in June**, 91 in July, 296 in August. Three eras, and the June gap is
real: the project was built fast, abandoned for seven weeks, then restarted as a release-engineering
and audit effort rather than a feature effort. Most of what is in the app today was written in the
first three days; most of the *work* went into finding out what was wrong with it.

**Era 1 — 2026-05-07 to 05-10: the whole app in three days.** Phase 0 scaffold with the aurora
glass design system, Phase 1A auth plus a 34-question onboarding questionnaire, Phase 1B wiring
Firebase (against the existing `traidingbot-b4061` project — the trading bot's, reused, which is
why the Firebase console shows an unrelated name), Phase 2A scanner and 2B video player, 2C/2D
injury-aware recommendations, Phase 3A–3D logging → progress → scheduling → reminders, Phase 4A
subscription tiers and 4B Stripe Checkout with a Cloud Functions webhook. Then `ee72853`, a
competitive-assessment gap closure that added pricing, adaptive personalisation, missing pages and
the Wear OS scaffold.

**Era 2 — 2026-07-28 onward: release engineering.** It opens with `bc0a527` — "kill doc-vs-reality
contradictions + add link-audit gate" — which is the origin of the "Keeping docs true" rule above.
Then builds `1.0.0+2` through `+9` in three days, each one a real device install, with nine gates
checkpointed in `1163b3d` and `7df44ec` **including their stated non-goals**. `c66d43c`
("one owner, one conversion, structural release") is the camera refactor that followed a leak found
by using the app rather than by reading it.

**Era 3 — August: the audits.** This is where the interesting failures live.

- **Licensing.** Builds `+12`, `+13`, `+14` land the video library, and then `dcfef30` — "the
  catalog was still serving the unlicensed scaffold". Shipping the licensed bundle and *serving* it
  were two different things, and only a direct check found the gap.
- **The full-app Figma-parity audit (`4dc291a`, 2026-08-11)** found **six real bugs** and produced
  the R11 gate plan. It was followed by a run of "act gates" — deliberately adversarial passes over
  finished features — and every one of them found something the feature work had missed:
  `e6bfa85` (A2-sec: **two paths that destroyed photos**), `aa9abf7` (A3 export: the counterparty
  was not redacted, reads were unbounded, a stale token failed silently), `d7335c0` (A6-lite: the
  system **refunded what had never signed up**, and an empty batch read as success), `e54bbef`
  (unbounded batch, unpaginated list, unkeyed locale, silent skips). If you are about to call a
  feature done, the act gate is the step that has historically earned its cost here.
- **A fix can be a regression.** `8125a5c` — "correct the muscle clean, and five regressions the
  Gate E pass introduced". The catalog re-verification pass broke five things while fixing others.
- **Honest release logging.** `e8ad0a7` records a **failed** release build — no APK, nothing
  distributed — as its own commit. `4d8e681` records that a branch shipped **without** a Codex
  round. Absence is logged, not omitted.
- **Measurement over assertion.** The equipment classifier was measured against the operator's own
  30 gym photos and scored top-3 5/18, while the machine's printed name identified 18/18 — which is
  why the text anchor runs first and why those photos are test data that must never be trained on.
  Both facts are in the section above; they came from measurement, not design.
- **Agent cost.** `d69ccc7` installed the v2.3.1 expert-team pack project-scoped without its
  installer, and `3783e98` then **downgraded 10 of the 12 opus agents to sonnet**. The 30 agents in
  `.claude/agents/` are a real running cost; treat adding another as a decision.

**2026-08-14 (`4071655`)** finished the `D:\test 2` → `D:\Repo` path rewrite across docs, agents and
scripts — which is why any path of that older form found anywhere in this repo is a bug, not
history.

**Current state (2026-08-17).** `master` at `3783e98`, working tree clean, in sync with
`origin/master`. A second worktree exists at `D:\Repo\_wt-formcoach` on branch
`formcoach/gates-a-c`; the gates-a-c merge and its stash disposition are recorded in `8a16d2d`.
Two things are deliberately left broken and must not be "fixed" casually: Wear release pairing
(`wear/build.gradle.kts` declares no `signingConfig`, so signing changes need their own GO) and the
open personalisation ranking decision named in `a42abe3`.
