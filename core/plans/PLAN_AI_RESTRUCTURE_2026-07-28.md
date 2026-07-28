# Plan — AI-Friendly Repo Restructure (2026-07-28)

**Goal:** cut the tokens an AI agent burns per session in this checkout, and give agents a defined
cadence instead of being invoked ad-hoc.

**Authorisation:** operator GO `го g0-g6 автономно` (2026-07-28). Implementation GO only — every gate
commits **locally**; pushing requires a separate `push` command per the Gate-Based Development rule.

**Scope discipline:** this plan does **not** restructure `mobile/lib`. That tree is already
feature-first and internally consistent (158 Dart files, `features/<name>/{data,state,widgets}`);
moving code would be a large risky diff for ~zero token benefit. Docs, navigation and agent
configuration are the actual problem surface.

---

## Baseline (measured 2026-07-28 19:27 local / 16:27 UTC)

Produced by `scripts/dev/measure_context.ps1`; raw rows in `core/context_baseline.csv`.
Token figures are estimates at ~4 chars/token — valid as a **relative** before/after signal, not as
an absolute billing number.

| Layer | Files | Lines | Est. tokens | Notes |
|---|---:|---:|---:|---|
| 1. ALWAYS-ON (CLAUDE.md chain) | 4 | 2,971 | **51,288** | Re-sent on *every* turn |
| 2. DOC SURFACE (core/ + root md) | 17 | 4,775 | 57,684 | Read while orienting |
| 3. CODE SURFACE (mobile/lib) | 158 | 18,851 | 152,650 | Read while working |

### Always-on breakdown — where the tax actually is

| File | Lines | Est. tokens | Share |
|---|---:|---:|---:|
| `C:\Users\koros\.claude\CLAUDE.md` | 1,459 | 25,106 | 49.0% |
| `D:\test 2\CLAUDE.md` | 1,401 | 24,816 | 48.4% |
| `Fitness App\CLAUDE.md` | 58 | 772 | 1.5% |
| `Fitness App\AGENTS.md` | 53 | 593 | 1.2% |

**Headline: the Fitness App owns 2.7% of its own always-on context tax. 97.3% is inherited.**
That is why G6 (dedup of the inherited pair) is worth more than G0–G5 combined on the always-on
layer, while G3 (navigation) is worth the most on the per-task layer.

---

## Findings that drove the plan

| # | Finding | Evidence |
|---|---|---|
| F1 | 24 rule headings exist in **both** global and volume CLAUDE.md; 267 lines byte-identical after whitespace normalisation | `comm` over normalised `## ` headings |
| F2 | `CLAUDE.md:41` claimed the master task list "lives in trading-assistance dir" — it does not; `ls` there returns *No such file*. File is at this repo root, tracked. | `ls` + `git ls-files` |
| F3 | `core/COMPETITIVE_ASSESSMENT - Copy.md` is a 605-line divergent superset of the 424-line canonical — 180 extra lines of a *different* assessment. Gitignored, but Glob/Read still surfaces it. | `diff` |
| F4 | `core/` was 4,360 md lines, of which 2,771 (64%) are business docs (nonprofit 776, roadmap 762, growth 572, competitive 424, pitch 237) with no engineering value to a coding agent | `wc -l` inventory |
| F5 | `core/CODEMAP.md` is 34 lines for 158 files and already stale (`core/ (10)` vs git's 14). No feature to purpose to entry-point mapping. | CODEMAP vs `git ls-files` |
| F6 | `docs/` = 67 PNG screenshots with opaque names, no index; 118M untracked `logs/`; 2.8MB untracked `.mp4` at repo root | `ls`, `du -sh` |
| F7 | Zero project agents (`.claude/agents/` absent); exactly one slash command | `find .claude -type f` |
| F8 | **Found during G1** — `mobile/integration_test/` does not exist, yet `AGENTS.md` listed `flutter test integration_test` as a canonical command and `CLAUDE.md` documented it as a test location. Any agent following the documented build sequence hits an error. | `ls mobile/integration_test` = No such file; 71 test files all in `mobile/test/` |

### G1 outcome

`scripts/dev/audit_doc_links.ps1` was built to make this class of bug a gate rather than a
discovery. It resolves each reference against the doc's own dir, the repo root, `mobile/` and
`mobile/lib/`, then by basename, and separates two verdicts: **BROKEN** (an engineering doc names
something absent — fails the gate) vs **PLANNED** (a roadmap doc names a future artefact — reported,
allowed). It also skips references on lines that describe an *absence*, so a doc saying "there is no
`foo/`" is not itself flagged.

Result: 107 references checked, **0 broken**, 15 forward-looking (all in roadmap docs).

### G2 outcome

`core/` now has three tiers, because they serve different readers and were previously interleaved:

| Tier | Holds | Read for a coding task? |
|---|---|---|
| `core/*.md` | CODEMAP, TECHSTACK, DEPENDENCIES, DEBUGGING, Firebase/Stripe setup | **Yes** |
| `core/plans/` | ROADMAP, NEXT_TICKETS, IMPLEMENTATION_PLAN, this plan | Only when picking up new work |
| `core/business/` | COMPETITIVE_ASSESSMENT, AGE_COHORT_STRATEGY, NONPROFIT, USER_GROWTH, PITCH | **No** — zero engineering facts |

`core/INDEX.md` is the router and states that tiering explicitly, so an agent knows which docs to
*skip* rather than discovering their irrelevance by reading them. `CLAUDE.md` now points at the
router instead of listing individual docs, so moving a doc no longer invalidates `CLAUDE.md`.

All cross-tier references were rewritten (6 docs) — the audit initially passed while still hiding
stale core-relative paths inside the PLANNED bucket, which is exactly the kind of false-green this
plan exists to remove. The checker also gained one-line look-back so prose that wraps between a
negation and the path it describes is not falsely flagged.

### G3 outcome

`core/CODEMAP.md` went from 34 lines of directory counts to a navigation document: a **route to
feature to entry-file table** (22 routes), a **feature table** for all 33 features with file counts,
line counts and purpose, and a "Start here" table mapping intents ("change the theme", "add a Cloud
Function") straight to files. Descriptions of the 12 logic-only modules are quoted from their own
doc-comments — the code carries ticket IDs (`MK.6`, `TX.3`) and was already self-describing; nothing
here is inferred prose.

Corrected along the way: the old CODEMAP called those 12 modules "single-file stubs". They are not
stubs — each is a documented domain module.

`docs/README.md` indexes the 67 screenshots by phase prefix (`fb_`, `p1_`, `p2c_`, `p3d_`, `p4b_`)
and, more usefully, tells agents **not** to open them — they are historical verification artefacts,
not a UI spec, and images are expensive to read.

Honest note on measurement: the DOC SURFACE number barely moved (57,684 to 56,709 est. tokens)
because CODEMAP/INDEX/docs-README additions roughly offset the deleted `- Copy.md`. That layer's
size was never the point — the point is that finding a file is now one Read of a table instead of
several Glob/Grep rounds plus opening large files to identify them. That saving shows up per task,
not in a static byte count, and is not claimed as measured.

---

## Progress tracker

Status: `DONE` / `IN PROGRESS` / `PENDING` / `BLOCKED`.
Every gate must satisfy its **exit check** before the next gate starts — no outstanding work, no
contradictions left behind.

| Gate | Scope | Status | Commit | Exit check |
|---|---|---|---|---|
| G0 | Progress tracker + CSV twin + `measure_context.ps1` baseline | DONE | `a476955` | Script parses, runs live, emits CSV; baseline recorded above |
| G1 | Kill contradictions: task-list path, integration_test, Copy fork, stray `.mp4` | DONE | `bc0a527` | `audit_doc_links.ps1` PASS: 107 refs, 0 broken |
| G2 | Split `core/` into engineering / plans / business; add `core/INDEX.md` router | DONE | `437cb74` | Audit PASS 132 refs / 0 broken; every doc reachable from INDEX |
| G3 | Real CODEMAP (feature to purpose to entrypoint) + `docs/README.md` index | DONE | _(this commit)_ | 33/33 features listed; 22/22 route entry files verified; audit PASS 217 refs / 0 broken |
| G4 | Agent cadence: `.claude/agents/` + slash commands | PENDING | | Cadence documented in AGENTS.md; every command references a real script/path |
| G5 | `CLAUDE.md` to thin router; sync global `fitness-app-helper` skill | PENDING | | Router points only at files that exist; skill matches repo reality |
| G6 | Dedup 24 duplicated rules across global + volume CLAUDE.md | PENDING | | No MANDATORY rule lost; both files backed up; re-measure shows the cut |

### Per-gate exit protocol

1. Build only the approved gate scope.
2. Verify — run the relevant check (`flutter analyze`/`flutter test` for code, link-audit for docs,
   parse-verify for `.ps1`, re-run `measure_context.ps1` where the number should move).
3. **Contradiction sweep** — grep the repo for references to anything the gate moved, renamed or
   deleted; zero dangling references allowed.
4. Local commit, atomic, one gate per commit.
5. Summary reported to operator.
6. Next gate. **No push** without a separate `push` command.

---

## Expected outcome (honest split)

- **Measured / certain:** G6 removes roughly half of one of the two ~25k-token inherited files by
  collapsing duplicated rules — the single largest always-on lever available. G0–G5 move the
  always-on layer by only ~1–2k tokens.
- **Estimated / not yet measured:** G3 is the per-task lever. Today a "where does X live" question
  costs several Glob/Grep calls plus full-file Reads (`subscription_page.dart` alone is 976 lines,
  ~12k tokens). A feature-level codemap should collapse most of that into one targeted Read. This
  will be re-measured after G3 rather than asserted.
- **Not claimed:** no reduction in the CODE SURFACE layer — that is what it is, and shrinking it
  would mean deleting features.
