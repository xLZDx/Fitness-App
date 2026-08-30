# Session handoff — HUD/Figma redesign follow-up, 2026-08-30

**From:** the session that closed `FORM_COACH_HUD_ALIGNMENT` + the week-strip gate and ran the
dark-theme/Figma comparison pass
**To:** the next Claude Code session on this repo
**Written:** 2026-08-30 04:30 local (Europe/Chisinau) / 01:30 UTC; state line below corrected
2026-08-30 08:45 UTC (see `core/DECISION_LOG.md` for why)
**State at handoff:** `origin/master` = `846d04e` — this file's own commit (originally made as
`329cb69`, then amended, landing as `846d04e`) is **already pushed**. Nothing to push. The commit
that had been local-only when this file was first drafted was pushed by the following session
after the earlier `review.js` "Gate C" error turned out not to block push for this repo at all —
see `core/DECISION_LOG.md` for the full diagnosis and the exact hook condition that applies.
Working tree otherwise clean except pre-existing untracked files in `reports/` that are not this
session's work (see `concurrent-sessions-in-workspace` auto-memory — do not touch or stage them
blind).

Everything below is either the one thing you need to act on, or context you need to not repeat
work that is already done.

---

## 1. Act on this: send two design questions to GPT-PM

This session could not do it. `pm_bridge_mode_status` returned, verbatim:

> PM Bridge mode is ON (pid 15436, port 8765) and the daemon is current. THIS SESSION is the stale
> one: this process loaded build `6235b685292c51d3` but the code on disk is now `cefcc53824dd3d17`.
> The DAEMON is fine — this session is the stale one, and it still owns project → conversation
> routing, so letting it send could deliver one project's content into another project's chat.
> Restarting the daemon will NOT help. Start a new session to pick up the change.

That is exactly what you are: a new session. Your `gpt_send_and_await` / `pm_bridge_session_start`
tools should work normally — confirm with `pm_bridge_mode_status` first, and if it still reports
itself stale, this is now a recurring PM Bridge defect worth its own investigation, not something
to route around.

Two open items, both already scoped and evidence-checked — you do not need to re-derive them,
just send them:

### 1a. Nav icons (Finding #4) — re-check whether it's still deferred, don't just resend blind

GPT-PM already ruled on this once (`core/DECISION_LOG.md:34959-34987`, 2026-08-29): kept stock
Material icons, classified `REFERENCE_BLOCKED_DEFERRED` (not "accepted final design"), explicitly
rejecting a blind 5-icon redesign as *"exactly the kind of subjective change that can consume time
and still leave the operator saying they are wrong."* Reopens only when the operator supplies a
reference, or a deliberate icon-design exercise is separately authorized. **Do not re-litigate this
with GPT-PM as if it were new** — check with the operator first whether a reference now exists;
only send it to GPT-PM if something material has changed since that ruling.

### 1b. Profile header layout/emphasis (new finding, already corrected once)

This is the one that actually needs a GPT-PM design call. Full evidence trail:
`core/DECISION_LOG.md:35285-35316` (original, since-corrected finding), `:35317-35361` (the
correction — GPT-PM's own code review caught that the original "no name" framing was factually
wrong), `:35363-35397` (the review-transport workaround, not relevant to the design question
itself).

**Current, corrected framing to send** (already fact-checked against
`mobile/lib/features/profile/profile_page.dart`, do not re-verify unless the code has changed):
Profile already renders a name (line 32: `displayName = user?.displayName ?? l10n.profileGuest`,
line 65: unconditional `Text(displayName)`) and already has a Membership/subscription section
(`_SectionLabel(l10n.profileSectionMembership)`, ~line 199). The real deltas against the Figma
reference (`docs/Redisign/reference/prototype/p_186.jpg`, `p_189.jpg`) are:
1. avatar treatment — gradient icon vs. the reference's circular avatar-initial;
2. subtitle content — onboarding status ("Анкета пройдена"/"Анкета не пройдена") vs. the
   reference's level/session-count subtitle;
3. no Premium upsell card at the top — Membership exists, but lower on the page among other
   settings, not as an accent card by the header.

Ask GPT-PM: should any of these three move toward the reference, and if so which (all three are
independent — a partial answer is useful, don't force an all-or-nothing verdict). This is a
product/design call, not a code-review pass — use `gpt_send_and_await` with the framing above, not
`review.js` (that's for code diffs, per §15 of `~/.claude/CLAUDE.md`).

**If GPT-PM approves a change**, it's a self-contained gate the same shape as the week-strip fix
(`437338f`) — small, testable, its own `review.js` round before push. Don't fold it into an
unrelated commit.

---

## 2. Already done — do not redo

Two gates shipped and pushed this session, each through genuine multi-round GPT-PM `review.js`
code review to `VERDICT: APPROVE`:

- **`FORM_COACH_HUD_ALIGNMENT`** (`10dc992`) — `HudSkyBackground` added to all 4 Form Coach phases
  (was missing on live/summary), `HudChip` semantics fix (nullable 3-state `enabled`, not a bool
  regression), build-script exit-code fix with a real deterministic test harness. 4 review rounds.
  Physically verified on S23 for launch/preparation/live. **Open tail, not this session's to close
  without a human at the device**: the summary phase was verified by widget test + code only, not a
  live camera session — needs a person physically running Form Coach to trigger a real rep and
  reach the summary screen.
- **Week strip on Home** (`437338f`) — dots replaced with `AspectRatio(aspectRatio: 1)` colour-coded
  squares matching the Figma reference (round 1 of review caught that the first attempt used
  `width: double.infinity` inside `Expanded`, which is a rectangle, not a square — fixed, round 2
  APPROVE). Regression test added (`home_page_test.dart`, `'week strip'` group), confirmed to
  actually fail pre-fix via `git stash`.
- **Library default on Workouts** — shipped inside `10dc992` per the operator's explicit
  instruction ("и библиотека должна быть дефолт на тренировках"). Verified with a test, not just
  code inspection.
- **Docs correction** (`67e630d`, `e0bc94d`, `568a73a`) — the Profile "no name" misdiagnosis above,
  caught and fixed via GPT-PM's own review of the docs commit. Also recorded a `review.js`
  transport quirk worth knowing if you run a multi-file review round yourself: a diff spanning
  `core/` + `reports/` repeatedly showed GPT only the alphabetically-first file
  (`core/DECISION_LOG.md`) across 3 rounds; the fix was embedding the missing file's patch as
  literal text in `--scope-note-file` rather than relying on the raw diff paste. Full detail:
  `core/DECISION_LOG.md:35363-35397`.

Nav-bar structure (5 tabs, order, dot-indicator, photographic background) was separately checked
against the prototype and confirmed matching — not an open item.

Report for all of the above, with before/after evidence: local
[reports/FORM_COACH_HUD_ALIGNMENT_2026-08-30.ru.html](../../reports/FORM_COACH_HUD_ALIGNMENT_2026-08-30.ru.html),
published at `https://claude.ai/code/artifact/02c8919c-b377-4b40-b9db-594af147e5ef`.

---

## 3. Context you'll want

- **PM mode is ON** (`/pm-bridge-mode` → orchestrator pid 15436). Per `~/.claude/CLAUDE.md` §18,
  a report is a checkpoint, not a stop — after you get GPT-PM's answer on §1b, act on it and keep
  going rather than waiting for the operator, unless the answer itself needs an operator call
  (it won't — a Profile layout tweak is squarely inside GPT-PM's product-decision authority per
  §16/§17, not the operator's irreversible-class carve-out in §4/§14).
- **Reference-frame coverage**: Home (`p_153-171.jpg`), Workouts (`p_174-183.jpg`), Profile
  (`p_186.jpg`, `p_189.jpg`) are covered by `docs/Redisign/reference/prototype/`. Progress, Scanner,
  Exercise page, Workout Player, Rest Timer, Technique Coach, Progress Photos, Paywall are
  explicitly NOT — don't go looking for a reference that doesn't exist for those screens.
  The reference's flat/solid-dark card backgrounds are a known, already-adjudicated divergence from
  the app's own deliberate photographic-sky `HudSkyBackground` language — not a discrepancy to fix.
- **`adb`** is at `/d/android-sdk/platform-tools/adb.exe` (not on Bash's default `PATH`). For exact
  tap coordinates, use `adb shell uiautomator dump` and parse `bounds="[x1,y1][x2,y2]"` — do not
  eyeball coordinates from a screenshot thumbnail, this session mis-tapped twice that way before
  switching.
- **Bash tool cwd drift**: chaining `cd /d/Repo/pm-bridge && node ...` in one call leaves the tool's
  persistent cwd at `pm-bridge` for every subsequent call in the turn, which then makes
  `decision_log_gate.py` evaluate against the wrong repo and block. Always `cd /d/Repo/Fitness_App`
  (and verify with `pwd`) before a `git`/`DECISION_LOG.md` operation that follows a `pm-bridge` CLI
  call.
