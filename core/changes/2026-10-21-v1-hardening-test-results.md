# 2026-10-21 - v1 hardening: test results

Worktree: D:\tmp\scratch_worktrees\hardening, branch chore/v1-hardening-2026-10-21, base head b89a9225 (tests added on top, uncommitted until this commit). Not pushed. Product code (mobile/lib, scripts) was not changed.

## Tests changed
- `mobile/test/features/subscription/tier_override_guard_test.dart`: the test asserting the default is true was replaced. New: default is false (skipped when any define is set); a default build (no provider override) ignores a stored celebrity override end to end; store profile test (runs only under `=false`); personal profile test (runs only under `=true`). Existing tests for allowed=true (override answers, off = real subscription) and allowed=false (stored override ignored, all values ignored) are kept and still cover explicit-true behaviour.
- `mobile/test/features/voice/voice_command_test.dart`: new group "parseCommand whole-word matching": 11 accepted phrases (Go, go!, ok go now, Start set!, Set done., rest now, skip rest, what's next?, curly-apostrophe what's next, stop, help), "log 40 kg" (40.0), "10 reps" (10.0); 11 near-miss phrases that must parse as unknown and not the old command (good, ago, mango, gone, undone, stopped, nonstop, helpful, interest now, timer started, catalog 40 kg); one KNOWN GAP test.
- Grep of mobile/test for allowTierOverride/tierOverride/TierOverride: only tier_override_guard_test.dart and tier_override_test.dart (the latter overrides the provider with true; no change needed). No other test relied on the old default.

## Commands (cwd D:\tmp\scratch_worktrees\hardening\mobile, PATH has /d/flutter/bin; no pub get needed)
1. Files written/changed plus every test file importing subscription_providers.dart or voice_command.dart (10 files: form_check/coach_intro_cards, progress_photos/scan/scan_access, safety/age_boundary, subscription/entitlement_status, subscription/subscription_providers, subscription/tier_override_guard, subscription/tier_override, voice/voice_command, workouts/state/offline_video_providers, workouts/state/prefetch_outcome):
   - `flutter test <10 files>` -> +195 ~2, All tests passed
   - `flutter test --dart-define=ALLOW_TIER_OVERRIDE=false <10 files>` -> +194 ~3, All tests passed
   - `flutter test --dart-define=ALLOW_TIER_OVERRIDE=true <10 files>` -> +194 ~3, All tests passed
2. Per file: voice_command_test.dart -> +32 passed; tier_override_guard_test.dart -> default +7 ~2, `=false` +6 ~3, `=true` +6 ~3 (skips are the define-dependent tests by design).
No analyzer, build or full suite was run.

## Findings
- KNOWN GAP (operator product decision): "let's go home" still parses as startSet (standalone word "go"). Pinned by a test named KNOWN GAP; a stricter grammar (short-utterance or exact match) would change accepted phrases.
- Related pre-existing quirk, unchanged and not tested: "go again" / "go back" resolve to startSet because 'go' is checked first.
- First compile of the voice test failed from a quoting error in my own test (fixed before any result above).

## Not verified
- Mutation sensitivity not run (operator rule); by reading, the near-miss tests fail under the old substring matcher and the default test fails under default true.
- Dart analyzer, PowerShell scripts (run_with_debug.ps1 splat), CI workflow, Firestore rules: not run.
- The curly-apostrophe case relies on a non-ASCII character in the test source.
