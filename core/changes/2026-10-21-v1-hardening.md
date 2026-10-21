# 2026-10-21 - v1 hardening: tier override off by default, voice parser whole-word matching

Branch: chore/v1-hardening-2026-10-21 (based on origin/master dc124bbc). Not pushed.

## What changed

### 1. ALLOW_TIER_OVERRIDE defaults to false
- `mobile/lib/features/subscription/state/subscription_providers.dart`: `kAllowTierOverride` default changed from `true` to `false`; doc comment rewritten. The comment states the truth: release builds are still debug-signed while no `key.properties` exists, so this is not a security boundary; the default only guarantees an unconfigured build does not grant a paid tier.
- `mobile/lib/core/settings/app_settings.dart`: the comment on `TierOverride` said the default was TRUE; updated.
- `scripts/dev/run_with_debug.ps1`: new optional switch `-AllowTierOverride` that appends `--dart-define=ALLOW_TIER_OVERRIDE=true` to `flutter run`. This is the documented dev opt-in (the dev run previously relied on the old default).
- `scripts/dev/build_release_profile.ps1` (comment only) and `.github/workflows/flutter.yml` (comment only): they described the default as "override allowed".

Why: with the old default, every build that did not pass an explicit define (plain `flutter run`, `flutter build`, any new wrapper) could grant a paid tier from the on-device switch.

Callers found (grep of the whole worktree for `ALLOW_TIER_OVERRIDE|kAllowTierOverride|allowTierOverrideProvider`):
- Production code: `subscription_providers.dart` lines 77 and 151 (both read `allowTierOverrideProvider`), the constant (~line 127) and the provider (~line 138). `app_settings.dart` only mentions it in a comment. No other lib file reads the constant.
- Build scripts: `scripts/dev/build_release_profile.ps1` passes `ALLOW_TIER_OVERRIDE` explicitly per profile (personal/test = true, store = false) and refuses a store build without exactly one `=false`, so profiled builds are unaffected. `scripts/dev/build_release.ps1` has no direct mention (it uses the profile defines). `scripts/dev/run_with_debug.ps1` and `scripts/dev/run_tests.ps1` passed no define and relied on the default: run_with_debug now has the opt-in switch; run_tests needs none (tests override the provider where they need `true`).
- CI: `.github/workflows/flutter.yml` runs the full suite with the default (now false) and a second run with `=false`.
- Tests that touch it (not edited here): `mobile/test/features/subscription/tier_override_test.dart` (overrides the provider with true; unaffected), `mobile/test/features/subscription/tier_override_guard_test.dart` (the test "the default is on, so the operator keeps the switch" asserts `kAllowTierOverride` is true when no define is set - it WILL FAIL with the new default and must be rewritten to assert false), `scripts/dev/build_release_profile.tests.ps1` (explicit defines; unaffected).
- Docs/history only, left untouched as dated records: `core/review/CODE_REVIEW_2026-10-07.md`, `reports/code_review_status_2026-10-07.ru.html`, `docs/phase2/s03/S03_CODE_MAP.md`, `core/state/TAIL_CLOSURE_REGISTRY.json`.

Operator impact: a bare `flutter run` or an unprofiled build no longer has a working tier override. To turn it on use `--dart-define=ALLOW_TIER_OVERRIDE=true` or `run_with_debug.ps1 -AllowTierOverride`. Personal/test release profiles are unchanged.

### 2. Voice command parser: whole-word matching
File: `mobile/lib/features/voice/data/voice_command.dart`.
- The helper `any` used `raw.contains(needle)`, so "go" matched inside "good", "ago" and "mango", and the same defect applied to every phrase ("done" in "undone", "stop" in "stopped", "help" in "helpful", "rest now" in "interest now").
- `any` now calls `_containsPhrase`, which normalises transcript and phrase (every run of characters outside `a-z0-9'` becomes a space; apostrophes survive only inside a word; the curly apostrophe is mapped to `'`; whitespace collapsed) and checks `" text ".contains(" phrase ")`. This applies to ALL phrase lists (start, done, rest, skip, next, previous, whatsNext, cancel, help).
- The `log ... kg` regex got a leading `\b` (it previously matched inside "catalog 40 kg"). The reps regex already had `\b`.
- Phrase lists and their order are unchanged, so the set of accepted phrases does not change. A pre-existing precedence quirk is kept on purpose: "go again" and "go back" still resolve to startSet because 'go' is checked first (as a whole word now; as a substring before).

Accepted (still; case-insensitive, punctuation tolerant) - from reading the code, not run:
- "Go", "go!", "GO.", "ok go now", "Start set", "start, set!", "begin set please"
- "done", "Set done.", "finished set", "rep done"
- "start rest", "rest now", "timer start", "skip rest", "cancel rest"
- "next exercise", "move on", "next one", "previous exercise", "last exercise"
- "what's next", "what's next?", "whats next", "what is next", "tell me next" (curly apostrophe too)
- "stop", "Cancel", "help", "commands"
- "log forty kilos", "log 40 kg", "10 reps"

Now rejected (were substring false positives; they fall through to a later rule or unknown):
- "good", "ago", "mango", "gone", "gopher" (no longer startSet)
- "undone", "abandoned", "condone" (no longer doneSet)
- "stopped", "nonstop", "unstoppable" (no longer cancel)
- "helpful", "helpless" (no longer help)
- "interest now", "forest now", "timer started" (no longer startRest)
- "catalog 40 kg" (no longer logWeight)

Open product question: "let's go home" contains the whole word "go", so a whole-word matcher still treats it as startSet. Closing that needs a different grammar (exact or short-utterance matching), which would change which phrases are accepted and is outside this task. Not fixed here.

## Affected paths
mobile/lib/features/subscription/state/subscription_providers.dart, mobile/lib/core/settings/app_settings.dart, mobile/lib/features/voice/data/voice_command.dart, scripts/dev/run_with_debug.ps1, scripts/dev/build_release_profile.ps1, .github/workflows/flutter.yml, this record, core/DECISION_LOG.md, core/LESSONS_LOG.md.

## Rollback
`git revert` of this commit. Reverting restores default true and substring matching.

## Verification state
- No tests, analyzer or build were run by the author (operator rule). Everything above is from reading the code.
- Owed by the test agents: (a) rewrite the default test in `tier_override_guard_test.dart` to assert false, and add a run under `--dart-define=ALLOW_TIER_OVERRIDE=true`; (b) voice parser tests for the accepted and rejected lists above, covering every phrase list; (c) check any other voice test that relied on substring behavior; (d) Firestore negative security-rules tests - a separate later task, not part of this change.
- Not verified: Dart analyzer cleanliness of the new helper, behavior of the lookbehind regex on the Dart VM, and the PowerShell array splat in `run_with_debug.ps1` (an empty splat is expected to pass nothing).

## Review round 1 (flutter-reviewer, 0 BLOCKER, 0 MAJOR, 5 MINOR)
- Fixed: typographic apostrophe variants U+2018 and U+02BC now normalise to an ASCII apostrophe (two pinned cases added to `voice_command_test.dart`).
- Accepted, not changed: Settings "Test access" section stays visible when the override flag is off (hiding it would change settings tests and UI outside this task; recorded for a later UI pass); "starts set"/"finished sets" falling to unknown is intended whole-word behaviour pending the stricter-grammar product decision; "go again"/"go back" priority defect and the missing phrase-list cases in the accepted map stay with that same decision; stale line reference in this record is cosmetic.
