# Fitness expert-team / recommendation-engine pack v2.3.1

Installed 2026-08-15. Source archive: `fitnessapp-expert-team-recommendation-engine-v2.3.1.zip`,
supplied by the operator. Provenance manifest kept beside this file as
`FILE_MANIFEST_SHA256.json` — all 131 entries verified on arrival.

## What went where, and why it is not where the installer wanted it

| What | Installed to | Count |
|---|---|---|
| Agent definitions | `.claude/agents/` (repo root) | 29 |
| Skills | `.claude/skills/` | 7 |
| Delegation hook | `.claude/hooks/validate_fitness_child_agent.py` | 1 |
| Policies | `.claude/policies/` | 4 |
| Evals, runtime JSON, contract and audit docs | here | — |

`INSTALL/install.py` puts the agents and skills in the **global** `~/.claude/`. They are project
scoped here instead, on three pieces of evidence:

1. `AGENTS.md` — *"the machine-wide agents … come from `D:\Repo\agents-skills-repo` … add or update
   an agent there, **not inside this project**."* The installer bypasses that source entirely.
2. `D:\Repo\agents-skills-repo/README.md` describes itself as *"project-agnostic … no binding to any
   specific project."* These 29 agents are bound to this app — the orchestrator names it, the
   policies carry its repo map — so they do not belong there either.
3. `fitness-flutter-reviewer.md`, the project's existing project-scoped agent, already lives in
   `.claude/agents/` under version control. That is the working precedent.

A global install would also have grown the machine-wide roster from 25 to 55 agents in **every**
repository on the machine, which `D:\Repo\CLAUDE.md` forbids.

## `install.py` was not run, and must not be

It crashes. `INSTALL/install.py:22` reads

```python
m = re.match(r"^---\\n(.*?)\\n---\\n(.*)$", text, re.S)
```

In a raw string `\\n` is two characters — an escaped backslash and the letter `n` — so the pattern
looks for a literal `\n` sequence rather than a newline. Real frontmatter has real newlines, `m` is
`None`, and line 24 raises `RuntimeError("orchestrator missing YAML frontmatter")`. Verified by
reading the file's bytes, not its rendering. The same regex is written correctly one directory away
in `evals/run_static_gates.py:18`, so this is a transcription slip rather than a decision.

It matters because of *where* in the sequence it dies: steps 1-3 (global agents, global skills,
project hook and policies) have already been written by then, and steps 5-6 — the five hook
self-tests and the `INSTALL PASS` line — are never reached. Running it leaves a **fail-closed
delegation hook installed and never validated**, with no error that says so.

What was done instead: files placed by hand, the interpreter pinned as step 4 intended, and the
five self-tests executed manually. All five pass.

## The interpreter pin

The shipped hook declares `command: python3`. On this machine `python3` resolves to
`C:\Users\koros\AppData\Local\Microsoft\WindowsApps\python3`, the Microsoft Store alias — not an
interpreter. The orchestrator's frontmatter is therefore pinned to `C:/Python314/python.exe`.

This is the one edit made to any shipped file. Everything else is byte-identical to the archive.
Re-pin it if Python moves.

## Running the three suites

From `core/agent-engine-v2.3.1/`:

```bash
python evals/run_reference_policy_gate.py                                    # 33/33
python evals/run_safety_evals.py --adapter evals.adapters.reference_policy_adapter:recommend  # 33/33
```

`run_static_gates.py` resolves its target as `parents[1]/.claude/agents`, which was the repo root in
the pack's own layout and is `core/agent-engine-v2.3.1/.claude/` here. It therefore finds nothing
from this location. Run it against the pack's own tree, or point `ROOT` at the repository root.

**A pass here is not an app pass.** The evals' own README: *"The runner does not pretend to test the
app without the app."* `evals/adapters/app_adapter_template.py` deliberately raises until someone
bridges it to a real runtime seam, and exit code 0 from *that* adapter — not the reference one — is
what the pack requires before calling the 33 cases satisfied. No such bridge exists: the
recommendation engine the cases describe has not been built.

## What this pack asserts about this repository

Its audit was checked claim by claim: **96 of 99 concrete assertions true, 1 false, 2 evaluative**.
All 39 cited paths exist, every cited symbol exists, and the numeric constants match line for line.
It is anchored to `5b7c9acc7acdd00db502e1934afd2c75983eaeb9`, which is genuinely this repository's
`origin/master`.

The one false claim: `00_G0_REAL_REPO_AUDIT.md:233` says progression results are *"all rounded to
2.5 kg"*. Rule 5 (`progression.dart:95-101`) returns `lastKg` unrounded. It does not weaken the
finding it supports.

Two things the audit gets wrong by omission, recorded here so the next reader does not inherit them:

- **RE-B01 is under-scoped.** It attributes the personalisation sign inversion to
  `for_you_ranker.dart:24` alone. The identical formula also sits at `plan_builder.dart:41`. A
  migration scoped from `findings.json` would fix one of two copies.
- **The repo's loudest stale claim is not in the register.** `core/CODEMAP.md:87` still tells every
  reader the injury filter *"currently gates **nothing** … 0 of 1,887"*. The catalog actually carries
  1,527 tagged rows of 1,887, pinned by a ratchet at
  `test/features/equipment/safety_coverage_test.dart`. The docs are stale; the filter works.

## What was NOT installed

The recommendation engine itself. `mobile/lib/features/recommendation/` and the 17 files under it do
not exist, and building them is a multi-gate programme the pack lays out in `04_GATE_PLAN.md` — not
a change that belongs in an installation commit. The pack's own conclusion is the right one and is
worth quoting before anyone starts: *"Do not build a second recommendation stack … migrate existing
consumers one by one."*
