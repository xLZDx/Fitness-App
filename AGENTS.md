# AGENTS.md — Fitness App

Tool-agnostic conventions for any coding agent operating in this checkout — Claude Code, OpenAI
Codex/ChatGPT, Aider, or anything else. `CLAUDE.md` is the Claude Code entry point; this file is for
everyone else, and for the parts that apply regardless of which agent is reading them.

## Build / test / run

```powershell
cd "D:\test 2\Fitness App\mobile"
flutter analyze
flutter test
flutter test integration_test
```

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

`mobile/test/` (unit + widget) and `mobile/integration_test/` are the canonical suites. 0 failures
required before claiming a change complete. Do not report a pass count without having actually run the
suite after the current changes.

## Where everything else lives

| Need | Go to |
|---|---|
| Layout, stack, cross-platform (iOS) principle, Stripe test mode | `CLAUDE.md` |
| Debug daemon runbook (read first for any bug report) | `core/DEBUGGING.md` |
| Roadmap / competitive assessment / nonprofit plan / implementation plan | `core/` |
| Master 75-feature task list | `FITNESS_APP_TASK_LIST.md` |
