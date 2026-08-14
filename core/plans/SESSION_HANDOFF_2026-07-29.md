# Session handoff — Fitness App (paste this whole file as the prompt)

You are picking up mid-stream on `D:\Repo\Fitness_App`. Read this file fully before touching
anything — it replaces re-discovering repo state via Glob/Grep. **Do not start any state-changing
action; the operator has not given a `GO` for new work yet.** Report back what you see, ask what's
next.

## Where things actually are (verified, not from memory)

```
git log --oneline -1        -> a97ae2e (docs: mark NEXT_TICKETS #6 done)
git log @{u}..HEAD --oneline -> a97ae2e   (1 commit, LOCAL ONLY, not pushed)
git status --short          -> ?? mobile/coverage/   (harmless leftover from a test run, untracked, safe to ignore or rm)
```

Before any `push`, re-run `git log @{u}..HEAD --oneline` yourself — do not trust this file's
snapshot, state moves. If it still shows only `a97ae2e` and the operator gives a literal `push`,
push exactly that commit (`git push origin a97ae2e:refs/heads/master`), not the branch tip blindly.

## What was done this session, in order

### 1. AI-friendly repo restructure — 7 gates, DONE + PUSHED

Full writeup: `core/plans/PLAN_AI_RESTRUCTURE_2026-07-28.md` (+ CSV twin). Read that file for the
complete rationale; short version:

- **G0-G5**: added `core/CODEMAP.md` (feature/route/entrypoint map — read this before globbing),
  `core/CONVENTIONS.md` (the rules a change is reviewed against — single source now, the reviewer
  agent and `/fitness-feature` both point here), `core/INDEX.md` (doc router, tiered:
  `core/*.md` engineering / `core/plans/` roadmap / `core/business/` positioning-skip-for-code),
  `docs/README.md` (screenshot index — says NOT to open them, historical artefacts), a project
  agent `.claude/agents/fitness-flutter-reviewer.md`, commands `/fitness-verify` and
  `/fitness-feature`, and two new scripts: `scripts/dev/audit_doc_links.ps1` (fails if any doc
  names a path that doesn't exist — run before trusting any doc) and
  `scripts/dev/measure_context.ps1` (tracks AI-context token cost, appends to
  `core/context_baseline.csv`).
- **G6 + Rosetta follow-up**: deduplicated rules between `~/.claude/CLAUDE.md` (global) and
  `D:\Repo\CLAUDE.md` (volume) — they were BOTH loaded every turn with 24 duplicated rule
  sections. Volume file now points at global instead of mirroring. Then found + removed 2 more
  redundant rules from global itself (GRAB-FIRST + 10-MINUTE-SSH-TIMEOUT — verified the trading-bot
  project's own CLAUDE.md already had fuller versions; RunPod/AWS-spot mentioned there were never
  actually used anywhere, grepped to confirm). **Result: always-on context 50,694 -> 36,372 est.
  tokens/turn (-28%).**
- **CRITICAL: neither global (`~/.claude/CLAUDE.md`) nor volume (`D:\Repo\CLAUDE.md`) is under
  git.** Both are plain directories, not repos. The ONLY rollback path is the backup files sitting
  next to them:
  - `C:\Users\koros\.claude\CLAUDE.md.bak-20260728-g6` (pre-G6 dedup state)
  - `C:\Users\koros\.claude\CLAUDE.md.bak-20260728-ab-pre` (pre-A+B-cleanup state, post-G6)
  - `D:\Repo\CLAUDE.md.bak-20260728-g6` (pre-G6 dedup state)
  - `C:\Users\koros\.claude\skills\fitness-app-helper\SKILL.md.bak-20260728` (pre-resync — that
    global skill had drifted badly: claimed 7 features when there are 33, referenced
    `mobile/integration_test/` which doesn't exist, cited a stale test-pass count, etc.)
  **Do not delete these backups without being asked.** Do not "restore consistency" by copying
  rules back from volume into global or vice versa — that undoes G6 on purpose; the amended Rules
  Sync Policy inside global CLAUDE.md itself says point-don't-mirror now.

### 2. A real bug found + fixed: `run_tests.ps1 -Integration`

`mobile/integration_test/` does not exist in this repo (confirmed repeatedly — do not create it
speculatively). `scripts/dev/run_tests.ps1 -Integration` used to silently attribute this to "emulator
not running" (masked the real cause whenever no emulator happened to be up) instead of saying the
directory doesn't exist. Fixed to check directory existence first. This is documented everywhere
now (`CLAUDE.md`, `AGENTS.md`, `core/CONVENTIONS.md`, `core/CODEMAP.md`, the reviewer agent) — if
you ever see integration-test content proposed, the directory genuinely does not exist yet.

### 3. NEXT_TICKETS.md #6 — DONE, verified independently, pushed

A *different* agent session did the actual fix (commit `366fd58`, prompted via a handoff prompt
similar in spirit to this one). Verified live, not just trusted the commit message:
- `flutter test`: 369/369 passed (confirmed by actually running it, matched the commit's claim).
- `flutter analyze`: commit said "clean" — actually exit 1 with 4 pre-existing warnings, verified
  they predate this commit and are in files it never touched (minor overclaim, not a real defect).
- No import cycle (commit's claim) — verified by reading the actual import chains.
- `audit_doc_links.ps1`: PASS, confirmed live.
- Found and fixed one real gap myself: `NEXT_TICKETS.md` still described #6 as open even after the
  fix landed — that file's own convention says "mark items done by editing this file." Fixed in
  `a97ae2e` (the one unpushed commit).

**Takeaway for you: verify agent-reported claims against the actual repo, don't just read the
commit message and move on. This session found real value doing that (the NEXT_TICKETS.md gap,
the analyze-clean overclaim).**

### 4. Unrelated commits from a parallel operator initiative (already reviewed, fine)

`2f22181` and `61afd9b` wire this repo into a separate cross-project initiative
(`D:\Repo\agents-skills-repo` roster + an on-demand `/rosetta` workflow for Copilot/Codex). Not
part of this session's own work, but checked: the referenced path is real, the new
`.github/prompts/rosetta.prompt.md` content doesn't contradict anything here. No action needed.

## What's NOT done — real open items

### A. Tickets #7 and #10 in `core/plans/NEXT_TICKETS.md` — descriptions are WRONG, need an operator decision before any prompt gets written

This is the important one. Both were verified against actual code this session and found to
describe something smaller/different than what's really there — **do not treat NEXT_TICKETS.md
prose as ground truth without checking the code first**, same lesson as above.

**#7 "AES-GCM swap for the photos page wiring"** — the ticket implies wiring exists and just uses
the wrong cipher. Verified: `mobile/lib/features/progress_photos/state/progress_photos_providers.dart`'s
`MockProgressPhotosRepository.capture()` calls NO cipher at all — it fabricates a fake
`ProgressPhoto` (`storagePath: 'mock://N.bin'`) with no real photo, no camera, no encryption, no
Storage upload. `XorPhotoCipher` and `AesPhotoCipher`
(`mobile/lib/features/progress_photos/data/photo_encryption.dart` and `aes_photo_cipher.dart`) are
each used ONLY in their own unit tests — grepped, confirmed, zero production references. The real
task is building the FIRST production repository (camera -> `AesPhotoCipher.encrypt` -> Firebase
Storage -> Firestore doc), which requires an open architecture decision the ticket itself flags but
doesn't resolve: key storage via SharedPreferences vs platform Keystore. This touches user body
photos — per this repo's own agent cadence (`AGENTS.md`), that's exactly the "genuinely high-stakes"
carve-out that warrants `security-reviewer` before implementation, not a quick handoff prompt.
**Ask the operator which they want: (a) scope+build the full pipeline (bigger, needs the key-storage
decision made first), or (b) defer.**

**#10 "ship a real catalog of stock videos via the moderation queue"** — conflates two unrelated
mechanisms under one ticket number:
- `scripts/catalog/seed_stock_videos.ps1 -Apply` edits `assets/data/exercises.json` directly (the
  curated, bundled catalog). Already works. **Zero code needed — this is a one-command operator
  action**, not an engineering task at all.
- The community-video moderation queue (`/contribute`, `/moderate`,
  `mobile/lib/features/catalog/state/catalog_providers.dart`) is wired ONLY to
  `MockCommunityVideoRepository` — grepped for `Firestore` in `lib/features/catalog/`, found only
  doc-comments describing a future intent, zero actual `cloud_firestore` usage. Approving/rejecting
  in `/moderate` right now doesn't persist anywhere — resets on app restart. "Clear the queue" has
  nothing durable to clear yet.
There is no medium-sized "code task" hiding in #10 as originally scoped. **Ask the operator: run the
one-line script yourself (no agent needed), or is building a real Firestore-backed community-video
repo actually wanted as its own separate, properly-scoped task?**

### B. Ticket #9 "Cloud Function tests" — premise verified correct, a ready-to-use handoff prompt exists but was NOT yet run

Confirmed: `functions/` has zero test infrastructure (no jest/mocha/vitest in `package.json`, no
`emulators` block in `firebase.json`, zero test files). NEXT_TICKETS.md's own "~3 days" estimate was
honest about this (unlike #7's undersell). A full, verified, ready-to-paste handoff prompt for this
ticket exists in this conversation's history — if you don't have it, reconstruct it from these
verified facts:
- Target functions + their current line numbers in `functions/src/index.ts`: `startFreeTrial`
  (~141), `createCheckoutSession` (~197), `generateAnnualReceipt` (~616), `bookCoachSession` (~777).
  **Re-grep for `^export const` before trusting these line numbers — this file may have moved since.**
- Needs: jest + firebase-functions-test + ts-jest added to the devDependencies of
  `functions/package.json`, an `"emulators"` block added to `firebase.json`, then tests per
  function (happy path + auth/validation
  failure path), with secrets (`STRIPE_SECRET_KEY` etc.) mocked, not real.
- Flag for `security-reviewer` afterward — this touches billing/auth-adjacent code.
- Scope strictly to these 4; the other 6 exported functions (`stripeWebhook`,
  `createPortalSession`, `optInDonorWall`, `optOutDonorWall`, `startCoachOnboarding`,
  `reportEquipment`) are out of scope — report them as uncovered, don't also fix.

**Ask the operator whether to proceed with #9 now** (premise still holds, just re-verify the line
numbers before starting).

## Standing rules that apply to everything above

- Approval = only literal `GO` / `ГО` / `GO <name>`, or `push` / `push <name>` for pushing. Nothing
  else releases a gate, per this machine's Gate-Based Development rule.
- Before claiming anything is "done": run it live (`flutter analyze`, `flutter test`,
  `scripts/dev/audit_doc_links.ps1`) — don't cite a pass count you didn't just produce.
- `core/CONVENTIONS.md` is the single source for Riverpod/go_router/iOS-portability/injury-filter/
  testing rules — don't re-derive them, and don't let them drift into a second copy anywhere.
- Full restart before re-testing a running app (`scripts/dev/run_app.ps1`) — stale processes give
  false passes and false failures.
- `mobile/test/` (369 tests as of this handoff) is the only suite. There is no `integration_test/`.

## One-line status for whoever reads this

7 gates shipped + pushed. 1 doc-fix commit local, unpushed (`a97ae2e`). Ticket #6 done, verified,
pushed. Ticket #9 ready to hand off, not yet started. Tickets #7 and #10 need an operator decision
before any further work — their written descriptions don't match the actual code.
