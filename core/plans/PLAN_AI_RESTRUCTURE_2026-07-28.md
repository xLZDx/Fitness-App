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
| `D:\Repo\CLAUDE.md` | 1,401 | 24,816 | 48.4% |
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

### G4 outcome

The original complaint — "agents are called manually, cadence is not defined" — is addressed
**without** making review automatic, because the operator's standing rule is that multi-agent review
is opt-in and panels on small changes are expensive and low-yield. So the cadence answers *which*
agent for *which* surface, and says explicitly that the default is self-review.

Added `.claude/agents/fitness-flutter-reviewer.md`: a project-scoped reviewer that knows what the
generic `flutter-reviewer` cannot — the feature layout, Riverpod/go_router conventions, the
iOS-portability seam at `lib/core/health/health_service.dart`, the glass design system, the fact
that there is no `integration_test/`, and that exercise lists must pass through the injury filter
(a safety rule, not a style one).

Added two commands for the repeatable loops that were previously re-explained every session:
`/fitness-verify` (analyze, test, doc audit, UI verification, with the `-Integration` trap called
out) and `/fitness-feature <name>` (scaffold in the exact convention, wire the route, update the
CODEMAP in the same commit). `/fitness-debug-daemon` already existed.

`AGENTS.md` carries the cadence table so it applies to any agent sharing the checkout, not just
Claude Code.

### G5 outcome

`CLAUDE.md` is now a router: 60 lines to 43, 772 to 578 est. tokens on every turn. Detail moved to
`core/CONVENTIONS.md` (new) — the single source for feature layout, Riverpod/go_router rules, the
iOS-portability principle, the design system, the injury-filter safety rule and testing rules. Those
rules had been duplicated across `CLAUDE.md`, the reviewer agent and the feature command; all three
now point at CONVENTIONS.md and say it wins on conflict. Toolchain paths moved to `core/TECHSTACK.md`.

**Measurement correction made here.** `measure_context.ps1` was counting `AGENTS.md` as always-on.
It is not: Claude Code auto-loads only `CLAUDE.md` files into each turn's system prompt, while
`AGENTS.md` is what Codex-style agents read automatically and is on-demand here. It is now its own
layer. Corrected always-on baseline is **50,501 est. tokens across 3 files**, of which this repo
owns 578 (**1.1%**).

The global `fitness-app-helper` skill was rewritten (backup at `SKILL.md.bak-20260728`). It had
drifted badly and would have actively misled: it claimed 7 features (there are 33), "15 competitors"
(the doc says 20), that the task list lives in the trading-assistance dir (it does not), that
`mobile/integration_test/` exists (it does not), a stale "315+ tests passing as of 2026-05-10" pass
count, pre-split `core/` paths, and the D-drive-only policy that was retired on 2026-07-28.

Honest accounting for G0–G5 on the always-on layer: it moved from 50,694 to 50,501 — about **-193
tokens/turn**, ~0.4%. These gates bought correctness, navigation and cadence, not always-on
reduction. That reduction is G6's job.

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
| G3 | Real CODEMAP (feature to purpose to entrypoint) + `docs/README.md` index | DONE | `c522e5c` | 33/33 features listed; 22/22 route entry files verified; audit PASS 217 refs / 0 broken |
| G4 | Agent cadence: `.claude/agents/` + slash commands | DONE | `5ad373b` | Cadence in AGENTS.md; audit PASS 233 refs / 0 broken |
| G5 | `CLAUDE.md` to thin router; `core/CONVENTIONS.md`; sync global skill | DONE | `c6a85d0` | Audit PASS 256 refs / 0 broken; project always-on 772 to 578 tok |
| G6 | Dedup duplicated rules across global + volume CLAUDE.md | DONE | _(outside git — see note)_ | 0 of 32 MANDATORY rules unreachable; both files backed up; always-on 50,694 to 37,010 tok |

### Per-gate exit protocol

1. Build only the approved gate scope.
2. Verify — run the relevant check (`flutter analyze`/`flutter test` for code, link-audit for docs,
   parse-verify for `.ps1`, re-run `measure_context.ps1` where the number should move).
3. **Contradiction sweep** — grep the repo for references to anything the gate moved, renamed or
   deleted; zero dangling references allowed.
4. Local commit, atomic, one gate per commit.
5. Summary reported to operator.
6. Next gate. **No push** without a separate `push` command.

### G6 outcome — the actual token win

`D:\Repo\CLAUDE.md` and `~/.claude/CLAUDE.md` are **both** loaded into every session's system
prompt. 24 rule headings existed in both, occupying **923 of the volume file's 1,401 lines** — so
~22 MANDATORY rules were sent to the model twice per turn while carrying the same meaning once.

Mirroring had also failed at its own goal. The two copies had drifted into different wordings —
similarity as low as **0.15** on "Forced Articulation Before State-Changing Actions" — so there were
effectively two competing versions of several rules, which is worse than either one alone.

**What changed.** The volume file now carries a pointer index naming the shared rules, plus only
what is genuinely volume-specific: the agent routing table, Agents-First routing, Aider
configuration, Approval Gate, Git Lifecycle, Release Manager, project bootstrap. Two shared rules
were **kept verbatim** in the volume file because they carry `D:\Repo`-specific tooling detail
absent from global — Windows Script File Encoding (sanitizer + verifier script paths) and Diagram
Generation Defaults (BPMN reference implementation paths).

The Rules Sync Policy in the global file was amended in the same pass to say **point, do not
mirror**. Without that, the next session would have "restored consistency" by copying everything
back and undone the gate.

**Safety.** Both files were backed up to `CLAUDE.md.bak-20260728-g6` before any edit, and a
mechanical check confirmed every one of the 40 pre-edit volume sections is still reachable (present
in the new volume file, present in global, or named in the pointer index) — **0 of 32
MANDATORY-titled rules unreachable**.

| File | Before | After | Delta |
|---|---:|---:|---:|
| `~/.claude/CLAUDE.md` | 25,106 tok | 25,464 tok | +358 (the amendment) |
| `D:\Repo\CLAUDE.md` | 24,816 tok | 10,967 tok | **-13,849** |
| `Fitness App/CLAUDE.md` | 772 tok | 578 tok | -194 |
| **ALWAYS-ON total** | **50,694** | **37,010** | **-13,684 (-27%)** |

> **Not under version control.** `D:\Repo` is not a git repository, so neither CLAUDE.md change is
> committed anywhere. The `.bak-20260728-g6` files beside each are the only rollback path — do not
> delete them until the new arrangement has been lived with for a few sessions.

---

## Final result

| Layer | Baseline | After G6 | Delta |
|---|---:|---:|---:|
| ALWAYS-ON (every turn) | 50,694 | **37,010** | **-27%** |
| AGENT ENTRY (`AGENTS.md`, on demand) | 593 | 1,196 | +603 (new cadence content) |
| DOC SURFACE | 57,684 | 59,336 | +1,652 (CODEMAP, CONVENTIONS, INDEX) |
| CODE SURFACE | 152,650 | 152,650 | unchanged — no code touched |

The doc surface grew on purpose: `CODEMAP.md`, `CONVENTIONS.md` and `INDEX.md` are read *selectively*
and replace unbounded exploration. Trading ~1.6k tokens of on-demand docs for a 13.7k/turn always-on
saving, plus far cheaper navigation, is the whole trade.

---

## Post-G6 follow-up (Rosetta mode, same day)

G6 closed the cross-file mirroring gap but left the global file's own internal bulk unexamined.
Two further items were worked through `/rosetta` (Prepare -> Research -> Plan -> Act -> Validate,
gated behind explicit `GO`):

**Item 1 — pushed the 8 gate commits.** `git log @{u}..HEAD --oneline` matched the authorized list
exactly (8 commits, `a476955`..`f237280`); pushed the exact SHA (`git push origin
f237280:refs/heads/master`) per the shared-checkout rule rather than a bare branch push. Fast-forward
`13195d7..f237280`.

**Item 2 — global `~/.claude/CLAUDE.md`, Option A+B.** Research found there was **no G6-shaped lever
left** — no internal self-duplication of comparable size (only a 1-line footer repeated 14x). The
two real findings:

- **GRAB-FIRST** and **10-MINUTE SSH TIMEOUT** (both tagged "ALL PROJECTS") were verified to be
  triple-redundant: the trading-bot project's own `CLAUDE.md` already carried fuller, more detailed
  versions (74 lines, with real script/data paths) that the generic global copies lacked. RunPod and
  AWS-spot — named in the global "ALL PROJECTS" framing — were grepped across every project file and
  found to have **zero real usage anywhere**. Removed from global; canonical text now lives only in
  the trading-bot project file, with a pointer left behind. Hetzner was checked too: it has no
  competitive marketplace-race dynamic (unlike Vast.ai's Reserved tab), so GRAB-FIRST's rationale
  doesn't transfer to it, and no Hetzner-specific rule was invented to fill a gap that doesn't exist.
- The 14x-repeated boilerplate footer ("This rule is non-negotiable...") was replaced by one blanket
  statement near the top of the file. One of the 14 occurrences was embedded mid-sentence inside a
  real "Reason (2026-05-18)" paragraph (not a standalone line) — a blind whole-line delete would have
  destroyed that paragraph's actual content; it was trimmed surgically instead.

**Safety.** Fresh backup (`CLAUDE.md.bak-20260728-ab-pre`, reflecting current post-G6 state, not the
stale pre-G6 one) taken before any edit. Mechanical verification (same technique as G6, generalised
to handle titles with internal hyphens like "GRAB-FIRST" and "10-MINUTE" that broke the naive
section-key parser on the first pass — fixed and re-run): every one of the 37 pre-edit sections is
either still present, or one of the 2 explicitly-verified-superseded removals, or the boilerplate
cut. **0 of 34 MANDATORY-titled rules lost.** A content-loss sweep additionally confirmed every
>60-char line from the pre-edit backup is either still present verbatim or traceable to one of the
two known cuts.

`~/.claude` is also not a git repository — same situation as `D:\Repo`. The `.bak-20260728-ab-pre`
file is the only rollback path for this edit.

**Measured result:**

| File | Before A+B | After A+B | Delta |
|---|---:|---:|---:|
| `~/.claude/CLAUDE.md` | 25,464 tok | 24,826 tok | -638 |
| **ALWAYS-ON total** | 37,010 | **36,372** | **-638** |

**Self-correction made while writing this section up:** four lines in this very document had the
`D:` drive path silently corrupted by a stray tab character, introduced by an earlier non-raw-string
escape-sequence bug during the G6 write-up. Caught before appending further content, fixed with a
raw string, verified zero tab characters remain in this file. **Second occurrence caught in the same
pass:** describing that bug by literally retyping the corrupted form re-triggered it a second time,
in both this file and its CSV twin — fixed by describing the defect in prose instead of reproducing
the exact trigger sequence. No other file was affected (checked both CLAUDE.md files — clean).

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
