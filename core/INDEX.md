# core/ — documentation index

Single entry point for everything under `core/`. **Read this file first; open only what your task
actually needs.**

`core/` is split into three tiers because they serve different readers. The split exists to stop an
agent doing a code task from reading a 776-line nonprofit strategy doc looking for build context.

| Tier | Directory | Who reads it | Read it for a coding task? |
|---|---|---|---|
| Engineering reference | `core/*.md` | Anyone touching code | **Yes** — this is the useful tier |
| Plans | `core/plans/` | Deciding *what* to build next | Only when picking up new work |
| Business / strategy | `core/business/` | Investor, positioning, fundraising | **No** — contains no engineering facts |

---

## Engineering reference — `core/`

| Doc | What it answers |
|---|---|
| [CODEMAP.md](CODEMAP.md) | Where does feature X live? Which file is its entry point? **Start here for navigation.** |
| [CONVENTIONS.md](CONVENTIONS.md) | The rules a change is reviewed against — feature layout, Riverpod/go_router, iOS portability, injury filtering, testing. **Single source; the reviewer agent and `/fitness-feature` both point here.** |
| [TECHSTACK.md](TECHSTACK.md) | What frameworks/versions/SDKs does this repo use, plus local toolchain paths |
| [DEPENDENCIES.md](DEPENDENCIES.md) | What packages are pulled in, and why? (`DEPENDENCIES.csv` is the machine-readable twin) |
| [DEBUGGING.md](DEBUGGING.md) | **Read first for any bug report.** Debug-daemon runbook — captures logs, errors, touches, screencaps per session. |
| [PHASE_1B_FIREBASE_SETUP.md](PHASE_1B_FIREBASE_SETUP.md) | Firebase project wiring, `google-services.json`, auth setup |
| [PHASE_4B_STRIPE_SETUP.md](PHASE_4B_STRIPE_SETUP.md) | Stripe **test-mode** price IDs and secret slots |
| [CLIP_LICENCE_AUDIT_2026-08-03.md](CLIP_LICENCE_AUDIT_2026-08-03.md) | **Where every exercise clip comes from and whether we may host it.** Read before touching `exercises.json` or the video buckets. CSV twin beside it; per-exercise verdicts in `subset_verdicts.csv` |
| [CATALOG_STATE_2026-08-03.md](CATALOG_STATE_2026-08-03.md) | **How many exercises ship, how many play a clip, and what is still missing.** Start here for any catalog-coverage question. CSV twin beside it; the clipless list is `CLIPLESS_FOR_REVIEW.csv` |

Also here: `context_baseline.csv` — measured AI-context cost over time, appended by
`scripts/dev/measure_context.ps1`.

## Plans — `core/plans/`

| Doc | What it answers |
|---|---|
| [ROADMAP_2026_V2.md](plans/ROADMAP_2026_V2.md) | Sequenced P0/P1/P2 + the 7 Tier-X features |
| [NEXT_TICKETS.md](plans/NEXT_TICKETS.md) | Concrete, ready-to-pick-up tickets |
| [IMPLEMENTATION_PLAN.md](plans/IMPLEMENTATION_PLAN.md) | Live phase/sequence roadmap |
| [PLAN_AI_RESTRUCTURE_2026-07-28.md](plans/PLAN_AI_RESTRUCTURE_2026-07-28.md) | This restructure: gates, baseline, progress tracker |

> Roadmap docs deliberately name files that do not exist yet (`lib/features/rehab/`,
> `web_trainer_studio/`, ...). That is intentional — `scripts/dev/audit_doc_links.ps1` classifies
> those as PLANNED rather than BROKEN. Do not "fix" them by creating empty directories.

## Business / strategy — `core/business/`

Positioning, fundraising and market material. **No engineering facts live here** — skip this tier
entirely for code work.

| Doc | What it answers |
|---|---|
| [COMPETITIVE_ASSESSMENT.md](business/COMPETITIVE_ASSESSMENT.md) | Canonical competitor analysis — 20-competitor matrix, moats, threats |
| [AGE_COHORT_STRATEGY.md](business/AGE_COHORT_STRATEGY.md) | "Age Mode" offers per cohort (teens through 60+) |
| [NONPROFIT_PLAN.md](business/NONPROFIT_PLAN.md) | 501(c)(3) / fiscal-sponsor strategy, subscriptions-as-donations |
| [USER_GROWTH_PLAN.md](business/USER_GROWTH_PLAN.md) | 5-stage growth plan, testnet users to paying donors |
| [PITCH_2026.md](business/PITCH_2026.md) | Seed-round investor deck |

---

## Docs that live outside `core/`

| Doc | Where | Why there |
|---|---|---|
| `CLAUDE.md` | repo root | Claude Code entry point — auto-loaded every session |
| `AGENTS.md` | repo root | Tool-agnostic conventions for any other agent sharing this checkout |
| `FITNESS_APP_TASK_LIST.md` | repo root | Master 75-feature list |
| `docs/` | repo root | Emulator screenshots — index + naming convention in [docs/README.md](../docs/README.md) |
