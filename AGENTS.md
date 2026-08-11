# AGENTS.md — Fitness App

Tool-agnostic conventions for any coding agent operating in this checkout — Claude Code, OpenAI
Codex/ChatGPT, Aider, or anything else. `CLAUDE.md` is the Claude Code entry point; this file is for
everyone else, and for the parts that apply regardless of which agent is reading them.

## Build / test / run

```powershell
cd "D:\test 2\Fitness App\mobile"
flutter analyze
flutter test
```

`mobile/test/` (214 test files) is the suite `flutter test` runs on the host, and the one a change is
expected to keep at 0 failures.

`mobile/integration_test/app_test.dart` also exists. It drives the real app on a device or emulator
and is the only thing that can see the native ML Kit bridge and what actually ships in the APK —
`flutter test` does not run it, and it needs hardware.

*(Corrected 2026-08-12. This said "There is **no** `mobile/integration_test/` directory" and "71
files". The directory is there, and 71 was a third of the real count. An agent reading this would
have been told not to run the one suite that can see the device, on the grounds that it does not
exist. `CLAUDE.md` had it right the whole time, which is how the contradiction was found.)*

```powershell
cd "D:\test 2\Fitness App"
.\scripts\dev\debug_daemon.ps1     # captures logs/errors/touches/screencaps to logs/sessions/<latest>/
```

For UI changes: build the APK and install on the `Pixel_API_34` emulator, then visually verify — `flutter
analyze` + `flutter test` passing does not prove a UI change renders correctly.

## Git safety — MANDATORY for any agent touching this repo

1. **Never push without the operator's explicit push authorization for that specific commit list.** A
   local commit does not imply permission to push.
2. **Never `git commit --no-verify` / `git push --no-verify`** without the operator explicitly asking for
   it in that message.
3. **Read `git log @{u}..HEAD --oneline` before every push attempt** and compare it against what was
   actually authorized — state can advance between authorization and push, including from a different
   agent sharing this checkout.
4. **Before any push from a checkout that might be shared** (multiple agents, multiple sessions): confirm
   no other git-capable process is active, or push the exact authorized SHA rather than the branch tip
   (`git push origin <sha>:refs/heads/<branch>`) so a concurrent commit from another agent cannot ride
   along.
5. Remote: `github.com/xLZDx/Fitness-App`, branch `master`.

## Testing requirement

`mobile/test/` (unit + widget, 214 files) is the canonical suite. 0 failures required before claiming a
change complete. Do not report a pass count without having actually run the suite after the current
changes.

## Agent cadence

Reviews here are **opt-in, not automatic.** Do not fan out a panel of reviewers on every change —
that is expensive and low-yield. Default: do the work, self-review it, and say what you think is
most likely wrong. Escalate to a specialist only when the operator asks, or when the change is
genuinely high-stakes (payments, auth, injury filtering, a migration) and an outside read would
change the outcome.

**Roster source:** the machine-wide agents (`security-reviewer`, `database-reviewer`, etc.) and
skills come from `D:\test 2\agents-skills-repo`, installed into `~/.claude/agents/` and
`~/.claude/skills/` per that repo's own README — add or update an agent there, not inside this
project. **`/rosetta`** is available as an on-demand deep-workflow mode (Prepare → Research → Plan →
Act → Validate) for larger tasks; it composes with the cadence below, it does not replace it —
approval is still only the literal `GO` / `ГО`.

When you do reach for one, pick by surface:

| Surface being changed | Agent |
|---|---|
| Any Dart/Flutter code in this repo | `fitness-flutter-reviewer` (project-scoped — knows the layout, Riverpod/go_router conventions, iOS-portability rule, injury-filter requirement). Prefer it over the generic `flutter-reviewer`. |
| Build/analyze/pub failures | `dart-build-resolver` |
| Cloud Functions (`functions/src/index.ts`), auth, Firestore rules, secrets | `security-reviewer` |
| Firestore data model / query shape | `database-reviewer` |
| Error handling and fallback paths | `silent-failure-hunter` |
| Tracing an unfamiliar flow across files | read `core/CODEMAP.md` first; only use `code-explorer` if the map is insufficient |

Rules that always apply, agent or not:

- **Read `core/CODEMAP.md` before searching the tree.** It maps all 33 features, all 22 routes, and
  the intent-to-file table. Globbing to rediscover that is wasted work.
- **Skip `core/business/` for code tasks.** It holds positioning and fundraising material and
  contains no engineering facts.
- **Read the debug-daemon session log before theorising about a bug** (`core/DEBUGGING.md`).

## Slash commands

| Command | Use it for |
|---|---|
| `/fitness-verify` | The canonical done-check: analyze, test, doc audit, UI verification |
| `/fitness-feature <name>` | Scaffolding a new feature in the repo's exact layout + wiring its route |
| `/fitness-debug-daemon` | Capturing logs/errors/touches/screencaps for a bug report |

## Where everything else lives

| Need | Go to |
|---|---|
| **Which file do I open?** — features, routes, entry points | `core/CODEMAP.md` |
| The rules a change is reviewed against | `core/CONVENTIONS.md` |
| Index of all documentation, tiered by who reads it | `core/INDEX.md` |
| Stack versions + local toolchain paths | `core/TECHSTACK.md` |
| Router / quick facts | `CLAUDE.md` |
| Debug daemon runbook (read first for any bug report) | `core/DEBUGGING.md` |
| Roadmap / next tickets / implementation plan | `core/plans/` |
| Positioning, competitors, nonprofit, pitch — **not needed for code** | `core/business/` |
| Master 75-feature task list | `FITNESS_APP_TASK_LIST.md` |
| Screenshot index (and why not to open them) | `docs/README.md` |
