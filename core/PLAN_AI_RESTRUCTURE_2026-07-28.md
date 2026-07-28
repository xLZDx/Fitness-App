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

---

## Progress tracker

Status: `DONE` / `IN PROGRESS` / `PENDING` / `BLOCKED`.
Every gate must satisfy its **exit check** before the next gate starts — no outstanding work, no
contradictions left behind.

| Gate | Scope | Status | Commit | Exit check |
|---|---|---|---|---|
| G0 | Progress tracker + CSV twin + `measure_context.ps1` baseline | DONE | _(see CHANGELOG)_ | Script parses, runs live, emits CSV; baseline recorded above |
| G1 | Kill contradictions: `CLAUDE.md:41`, `- Copy.md` divergence, stray `.mp4` | PENDING | | No doc claims a path that does not exist; one canonical competitive assessment |
| G2 | Split `core/` engineering vs business; add `core/INDEX.md` router | PENDING | | Every moved doc reachable from INDEX; no dangling references anywhere in repo |
| G3 | Real CODEMAP (feature to purpose to entrypoint) + `docs/README.md` index | PENDING | | Every `lib/features/*` dir appears in CODEMAP; counts match `git ls-files` |
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
