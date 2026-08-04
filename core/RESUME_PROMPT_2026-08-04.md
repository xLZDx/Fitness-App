# Resume prompt — Fitness App audit remediation, paste this as the first message in a new session

You are continuing work on `D:\test 2\Fitness App` (Flutter + Firebase fitness
app) exclusively. Per the operator's One-Session-One-Project rule, do not
read, edit, or run anything belonging to another project this session.

## Where things stand

Git: `HEAD = 77d7c99`, pushed, tree clean (three pre-existing untracked dirs
— `data/preflight/`, `data/staging/library/`, `data/staging/video_library.json`
— are not yours, leave them alone).

The operator supplied a full external audit of the app. You (a prior session)
verified its claims against the working tree, wrote a remediation plan, ran
it through a 5-agent T3 design/architecture review round (`architect`,
`code-architect`, `a11y-architect`, `flutter-reviewer`, `planner`), and
produced a consensus plan — not the pre-review draft.

**Read the plan before doing anything else:**
`core/PLAN_AUDIT_REMEDIATION_2026-08-04.md`

Read-only skim of what's in there: 13 gates (I0, S0a, S0b, S2, S1a, S3a,
S3b×N, S1b, C0, W0, L0a-d, R0), a full dependency graph, a Part-0 fact-check
of the audit itself (headline correction: catalog safety-tag coverage is
**0 of 1887 exercises, not the audit's claimed 6%** — the legacy catalog
carrying the only 144 tagged exercises was deleted the day before, in
`0c4bf24`), and a full review audit trail with every BLOCKER cited to
`file:line`.

## Gate progress

**I0 — DONE**, `77d7c99`, pushed. `--write` merges by `id` instead of
overwriting; `CURATED = {equipmentId, contraindications}` and any key the
generator does not produce are the file's; a write that would drop rows is
refused without `--allow-drop`; `safetyCoverage()` lives in
`exercise_filter.dart`; the floor test is pinned from both sides at 0 in
`test/features/equipment/safety_coverage_test.dart`.

One thing that gate found which the plan did not know: the destructive write
was not a future risk to tagging, it was live damage waiting on the next
rebuild. 1,887 rows carry a `poster` the generator never emits and 1,384
carry an `equipmentId` it emits as null — the second of those shipped the
day before, in `d16e649`.

Untested and stated as such: the generator cannot run end to end on this
machine (`D:/Downloads/4K UHD 2160P.zip` and the `.xlsx` are absent), so
`main()` is covered by stubbing `build()`, never by a live `--write`.

**Everything else — not started.** No other gate has an implementation GO.

## What to do first

1. Confirm the plan doc still matches the current tree (git has moved since
   it was written — spot-check a couple of its `file:line` citations before
   trusting them, per the No-Guessing rule). Note the plan is deliberately
   NOT retro-edited as gates land: it is the consensus artifact of
   2026-08-04, and this section is where progress against it is tracked.
2. Ask the operator which gate to build, or wait for them to name one. The
   chain's next link is **S0a** (honest banner + the eight always-false
   safety affordances); **C0**, **W0**, **L0a** and **M0** are independent
   of it and can go first if the priority is different.
3. Do not start building any gate without an explicit `GO` / `ГО` (case-
   insensitive, exact command per the operator's global CLAUDE.md — "yes",
   "sounds good", "approved", "go ahead" do NOT count). Do not push anything
   without a separate, later `push` command.
4. If the operator's message doesn't name a gate and doesn't look like
   authorization, treat it as a normal request and re-state the relevant
   part of the plan, then ask for `ГО` before touching any file.

## Also still open, separately, not part of this plan

**Backlog E4.1** (see `core/BACKLOG_2026-07-31.md`): four equipment pages
with zero video coverage — `recumbent_bike`, `glute_kickback_machine`,
`t_bar_row`, `rotary_torso_machine`. Three options were written up in an
earlier gate; the operator explicitly deferred the decision ("потом будем
решать" — later, we'll decide). Do not pick an option without being asked.

## Standing rules that apply here (already in `~/.claude/CLAUDE.md` + `D:\test 2\CLAUDE.md`, restated because this is the part that's easy to drop across a session boundary)

- Approval is ONLY the literal word `GO` / `ГО`, optionally with a gate name.
  A separate `push` authorizes pushing and nothing else.
- Small scope → verify → local commit → **stop and report** → separate
  push-GO. Never build more than one gate on one GO.
- Every factual claim about the code needs an inline `file:line` or command
  output citation — this project's audit found real, costly drift between
  what a prior pass claimed and what the code actually did (see the plan's
  Part 0 for two examples from this very session).
- Russian in chat, hide nothing, no unstated assumptions.
