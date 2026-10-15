# Phase 1 / Phase 2 split: repository, folders and synchronisation plan (planning only)

Date: 2026-10-15 (revision 2 after GPT-PM planning review round 1: F-02, F-03, F-05, F-06). Status: DRAFT FOR GPT-PM VERIFICATION, then operator approval. Nothing here has been executed. Every step needs the operator's approval of this plan first. Creating a branch, tag or worktree is reversible routine work once approved; deleting any ref, branch or worktree stays a separate operator approval (global contract section 3).

## 1. Goal

Two clearly separated lines of work, locally and on GitHub:

- **Phase 1** = the first production MVP (pre-2026-10-10 scope). Only fixes, security, store/legal readiness.
- **Phase 2** = the development line (post-2026-10-10 scope), cloned from Phase 1, fed continuously by Phase 1 fixes.
- A post-2026-10-10 feature found in the Phase 1 code line is an **experiment** (flag OFF, in `docs/EXPERIMENTS.md`, frozen in Phase 1). Provenance of every existing feature folder: `01_PROJECT_REASSESSMENT` section 4.1.

`phase1-baseline` is a historical Git cut used as the split point. It is NOT a production-ready certificate (F-04).

## 2. Options (the operator picks one; recommendation first)

| Option | Layout | For | Against |
|---|---|---|---|
| **A (recommended): one repository, two long-lived branch families, two local worktree folders** | Repo `xLZDx/Fitness-App`. Branches `phase1/main`, `phase2/main`; work branches `phase1/<topic>`, `phase2/<sprint>`; tag `phase1-baseline`. Local worktrees `D:\Repo\Fitness_App_Phase1`, `D:\Repo\Fitness_App_Phase2`. Docs split into `docs/phase1/` and `docs/phase2/` (navigation indexes) | Shared history; real merges; no duplicated code; matches the existing worktree workflow | Branches can drift unless the sync gate (section 5) is enforced |
| B: two repositories | New repo for Phase 2 | Hard isolation | Manual cherry-picking; two pipelines |
| C: two top-level directories `phase1/` and `phase2/` in one repo | Code duplicated | Looks tidy | Every fix applied twice; hash-pinned and generated files assume one tree |

The rest of this plan assumes **Option A**. Approving Option A is NOT permission to change branches, retarget PR #5 or remove worktrees: those are the controlled actions of section 4.

## 3. Target state

| Ref / folder | Meaning | Rules |
|---|---|---|
| tag `phase1-baseline` | `origin/master` at `42d1b849` (merge of PR #4, 2026-10-14), before PR #5 | Immutable record of the split point |
| `master` | Default branch, kept pointing at the Phase 1 line during transition; its fate is D-3 and is not blocking | No direct pushes |
| `phase1/main` | Production MVP line from `phase1-baseline` | Fixes, security, release readiness only; one PR per independently reviewed change set; GPT-PM gate as today |
| `phase2/main` | Development line from `phase1/main` | One PR per sprint; new product surface flagged OFF |
| `phase2/<sprint-id>`, `phase1/<topic>` | Work branches | Short-lived |
| `D:\Repo\Fitness_App_Phase1`, `D:\Repo\Fitness_App_Phase2` | Worktrees of the two main lines | Real git root, branch and HEAD verified on entry |
| `D:\Repo\Fitness_App` | Existing main checkout; contains uncommitted edits of other sessions (documents modified) | NOT touched until the operator decides; its dirty state is snapshotted first (section 4 step 1) |

Documentation layout (created by documentation changes after approval):

```
docs/phase1/            navigation index of production-MVP documents (links to core/ originals; no moves without operator-approved renames)
docs/phase2/            vision (blueprint as Markdown), roadmap, sprint files, UI direction, decision register
docs/phase2/sprints/    one file per sprint: scope, epics, stories, DoD, evidence links
docs/EXPERIMENTS.md     experiments register (flag, folder list, owner, frozen since, Phase 2 home)
docs/SYNC_LOG.md        one entry per Phase 1 -> Phase 2 sync (see section 5)
docs/DOCUMENT_REGISTRY.md   derived listing written by a small generator added in S00 (workspace contract); never hand-edited
core/INDEX.md           stays the canonical hand-maintained entry point; core/CURRENT_STATE.md stays generated and untouched
```

F-05: the canonical document entry point is `core/INDEX.md` today; no registry generator exists in the repository (FACT, search of the tree). The derived registry only lists files; decisions stay in `core/DECISION_LOG.md`.

## 4. Migration protocol (bootstrap operations, distinct from sprint PRs; F-02)

The split is one controlled migration with its own record, executed only after approval. It is not a sprint and does not use the sprint PR flow, but every step is recorded in `core/DECISION_LOG.md` and has a change record.

1. **Snapshot** (read-only): write the list of all refs with tips, all worktrees with HEAD and dirty state (including the uncommitted edits in `D:\Repo\Fitness_App`), and the open PR list into `docs/phase2/split/SNAPSHOT.md`. This is the recovery map.
2. **Tag and branches** (additive, reversible): tag `phase1-baseline` at `42d1b849`; create `phase1/main` from the tag; create `phase2/main` from `phase1/main`; push tag and branches. Nothing is deleted or force-pushed.
3. **PR #5 decision (D-2), separate from step 2**: recommended path is to retarget PR #5 to `phase2/main`. Retargeting changes the merge base and therefore the diff the reviewer sees, so the GPT-PM approval on head `cd9d7c3a` is NOT assumed to carry over: after retarget, the exact diff range is re-verified once by GPT-PM (narrow check: conflicts and merge base effects) before merge. If the operator prefers merging PR #5 into the Phase 1 line unchanged, it lands behind flags and is registered as an experiment; the approval stays valid because the base is the same.
4. **Local worktrees**: create the two worktrees; verify git root, branch and HEAD in each.
5. **Documentation PR per line**: one documentation PR into `phase2/main` (`docs/phase2`, `docs/EXPERIMENTS.md`, `docs/SYNC_LOG.md`, registry generator and its first output) and one into `phase1/main` (`docs/phase1` index). Each goes through the normal GPT-PM gate on its exact head.
6. **Sync check**: run the first sync gate (section 5) from `phase1/main` into `phase2/main`; record in `docs/SYNC_LOG.md`.
7. **Backend separation gate** (section 7) passes before any Phase 2 cloud write.

Stop conditions: a failing step stops the migration; the snapshot lets any additive step be undone by an operator-approved ref deletion.

## 5. Synchronisation protocol ("Phase 1 is continuously synchronised with Phase 2"; F-03)

- Direction: `phase1/main` into `phase2/main` by merge commit. Backport from Phase 2 only by explicit decision, as a cherry-pick with its own PR into `phase1/main`.
- **Owner**: the Phase 2 sprint coordinator owns every sync (single named owner per sprint, recorded in the sprint file). The session that merged into Phase 1 only records the "sync due" line in `docs/SYNC_LOG.md`; it does not leave the sync to chance.
- **Trigger**: every merge into `phase1/main`, and always before a Phase 2 sprint PR is opened and before any release train cut. Maximum lag allowed: one Phase 1 merge older than the last sync, enforced by a check in the sprint DoD (the sprint cannot close if the log shows an unsynced Phase 1 merge).
- **Sync gate (mandatory content of each `SYNC_LOG.md` entry)**: base SHA of Phase 1, target SHA of Phase 2 before and after, list of conflicted files with the classification of each (security fix, rules, behaviour fix, doc, other), the rule applied, and focused regression evidence for every conflicted path or security fix (tests written and run by the named test agents). Phase 1 changes labelled security, privacy, data-deletion, Firestore/Storage rules or release-guard are never resolved "Phase 2 wins": the Phase 1 invariant must be re-expressed in the Phase 2 code and proved by a test before the sync entry is closed.
- Firebase rules and indexes: one file per line; a diff of `firestore.rules`, `storage.rules` and `firestore.indexes.json` between the two lines is part of every sync entry.
- Experiments: a post-2026-10-10 feature in Phase 1 code receives no new commits on `phase1/*` except removal or harm-preventing fixes.
- Evidence rule: tests, reviews and GPT-PM approval identify the exact head they prove, per line.

## 6. Branch and worktree retirement list (proposal; nothing is deleted without operator approval)

| Ref / folder | State (FACT from `git worktree list` and the whole-program report) | Proposal |
|---|---|---|
| `sprint/coach-form-fixes-2026-10` (22 commits, not pushed) | Scan screen and form-coach fixes, review pending | Phase 1 fix work: own PR into `phase1/main` after rebase; its own gate |
| `sprint/scan-mapping-fixes-2026-10` (1 commit, not pushed) | Maps scan results to the right equipment page | Own PR (separate evidence), not merged into the coach-fix PR |
| `sprint/full-project-qa-2026-10-13`, `sprint/tail-closure-2026-10-13`, `sprint/product-hardening-2026-10`, `sprint/hardening-followups-2026-10` | Merged by PRs #2-#4 or equal to merged commits | Candidates for deletion after the snapshot records their tips |
| `formcoach/gates-a-c` (585 commits behind) | Old branch | Review once for unique value, then archive as a tag |
| `docs/add-english-readme-20261010` (PR #1 draft) | English reports and plan companions | Decide: merge into `phase1/main` docs or close |
| `marketing/site-prototype-2026-08-19` | Marketing prototype | Out of scope; keep |
| worktrees `_wt-master-sync`, `Fitness_App_basecheck`, scratchpad `wt_c585dfa` | Detached helper worktrees | Remove after the split; the prunable one first |

Rule: a ref is deleted only after the operator confirms, with the recovery command (tag at the old tip) recorded before deletion.

## 7. Backend separation gate (S00 exit; F-06)

The Firebase project, Firestore rules, indexes, Cloud Functions, Storage bucket, secrets, App Check and CI deploy permissions are shared today. Before any Phase 2 cloud write the following must be true and proved by a configuration check plus a release-guard test, not only by branch names:

| Item | Required state |
|---|---|
| Firebase project or alias | Phase 2 uses a separate project alias (decision D-4, S00 ENTRY) for emulator, test and beta data; production Phase 1 project untouched |
| Deploy allowlist | `firebase deploy` (functions, rules, indexes, storage) is allowed only from `phase1/main` to the Phase 1 project; from `phase2/*` only to the Phase 2 alias; enforced by a release-guard script added in S00 and a test that fails on a mixed configuration |
| Rules and indexes | Phase 2 additions are additive and flagged; a Phase 2 collection never changes a Phase 1 rule; the diff is part of the sync entry |
| Secrets and App Check | Separate secret sets and App Check apps per alias; no secret printed or committed |
| CI | CI jobs are named by line; deploy jobs require the line's protected branch; (CI itself is not a merge requirement per operator rule; this is about deploy permissions only) |
| Data | No production data copied into the Phase 2 project; test accounts only |

## 8. Risks of the split itself

| Risk | Mitigation |
|---|---|
| CI, generated registries or hash-pinned files assume `master` | Keep `master` valid during transition; run only the focused checks of touched generators |
| Sessions working in the wrong tree | Per-line banner in `AGENTS.md`/`CLAUDE.md`; workspace rule "resolve the real git root first" |
| Drift between lines | Sync gate, maximum lag rule, sprint DoD check |
| Experiments creeping into Phase 1 | `docs/EXPERIMENTS.md` plus the per-flag default-OFF release guard |
| One-PR-per-sprint rule vs bootstrap | The migration protocol is declared a bootstrap with its own record; every later change follows the sprint PR rule |

## 9. Decisions for this document (see the decision register in `03_ROADMAP_AND_SPRINTS` section 10)

S00 ENTRY: D-1 phase-rule interpretation (incl. D-1b boundary cases and D-1c experiment delivery), D-2 PR #5 target, D-4 separate Firebase alias, D-5 Option A/B/C. Not blocking: D-3 name of `master`.
