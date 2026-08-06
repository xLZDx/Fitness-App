# Session handoff — Fitness App (paste this whole file as the prompt)

You are picking up mid-stream on `D:\test 2\Fitness App`. Read this file fully before touching
anything. The big investigation from earlier in this file is **RESOLVED** — read "What was found
and fixed" below, then go straight to "What to do next" at the bottom.

## Where things actually are (verified, not from memory — re-verify yourself before acting)

```
git log --oneline -1        -> 08fed0f (feat(workouts): F3.3a -- backfill script, not yet run)
git status --short          -> clean except this handoff file itself
```

10 code commits this session, **none pushed** — standing push-GO was given at session start ("push
after each gate closes, not after every commit"), but no gate has fully closed yet (F3 is
mid-flight — see below). Do not push without a fresh, specific push-GO; re-read the operator's
exact wording when it comes, per the stale-GO rule.

## The gate-sequence correction (read this before assuming "G2/G3/G4" means anything)

Early this session the operator said continue "G2 -- Base components and common states, G3 --
Navigation shell, G4 -- Onboarding core." That G0-G25 list **exists only in chat/commit messages,
never in a `core/*.md` plan file**. The actual persisted, most-recent plan in this repo is
`core/plans/FIGMA_MAKE_REFACTOR_AUDIT_2026-08-05.md` ("R0", committed 2026-08-06), whose §10
defines a **different** sequence -- F1-F5 (foundation) then R1-R9 (features) -- and whose §14 delta
table says explicitly "the gate sequence in §10 stands." `git log` confirms F1(step1)/F2/F4/
F5(-equivalent)/R1 were already committed under THAT plan's own labels, mostly predating this
session. The operator confirmed: F1-F5/R1-R9 is the real plan; G-naming was informal. **Do not
resume "G2.2 states" work under the old G-numbering without re-reading that audit file's §10
first.**

Done per the audit's own labels: F1 step1 (tokens, `0e63469`), F2 (`11598cf`), F4 (`2dff097`),
F5-equivalent (`7a878da` etc.), R1 (`17e1fcc`). **Not done: R2-R9 entirely.** F3 was the last
foundation piece and is mid-flight now (see below).

## G2.1 (buttons) — DONE, kept, separate from the F/R sequence

`AppPrimaryButton`/`AppSecondaryButton`/`AppTertiaryButton`/`AppIconButton` consolidation. 4
commits: `bcce6d6`, `6eea5c1`, `fa3deea`, `98c7085`. Found and fixed real a11y defects along the
way. Not pushed. **Finished — do not redo.** G2.2/G2.3/G2.4+ were never started; not next by
default.

## F3 — WorkoutSession entity + backfill (mid-flight)

Full plan + review trail: `core/plans/PLAN_F3_WORKOUT_SESSION_2026-08-06.md`.

- **F3.1** (`16dcd37`) — models, repo interface, mock, tests. Done.
- **F3.2** (`90ae270`) — `FirestoreWorkoutSessionRepository`, providers, wired in `main.dart`. Done.
  Nothing reads `workoutSessionsProvider` yet — deliberate.
- **F3.3a script** (`08fed0f`, fixed further this session) — `functions/scripts/backfill_workout_sessions.mjs`.
  Dry-run by default, `--uid=`/`--all`, `--write` required for real writes, idempotent.
- **F3.3 RAN FOR REAL, later in this same session** — logged one real workout live on the emulator
  test account, backfilled it (`--uid=` then `--all`, dry-run then `--write` at each step,
  verified in Firestore after each). Found and fixed a real bug in `listAllUids()` along the way
  (see `core/plans/PLAN_F3_WORKOUT_SESSION_2026-08-06.md`'s F3.3 section for full detail — it was
  querying a Firestore collection that never materializes, so `--all` was a silent permanent
  no-op). `workout_logs` count now equals `workout_sessions` count (1 == 1) in production, no
  duplicates. **F3.3's backfill itself is DONE.** Still open: single-collection history-read
  convergence, F3.3b (totals/streak), F3.4 — see that plan doc's "Still open" note.
- **Tooling fix this session**: the auto-mode classifier blocks any `--write` invocation of this
  script on both Bash and PowerShell tools, even dry-run-verified and GO'd. Added a narrowly-scoped
  `autoMode.allow` entry in `~/.claude/settings.json` for this exact script (operator GO) — no
  longer need to hand this class of command to the operator to run manually.

## What was found and fixed: production Firebase Auth was never enabled (RESOLVED)

While chasing "why is production Firestore completely empty" for F3.3, discovered and fixed a
much bigger, previously-unknown bug, end-to-end verified live on `emulator-5556`:

**Root cause**: Firebase Authentication had never been enabled for the `fitness-app-korostelev`
project at all — not "wrong provider configured," not "App Check blocking it" (checked and ruled
out via the App Check Management API: `firestore.googleapis.com` and `identitytoolkit.googleapis.com`
were both `UNENFORCED` the whole time) — literally no Auth configuration existed
(`admin.auth().listUsers()` returned `auth/configuration-not-found`; `GET .../admin/v2/projects/
{id}/config` returned 404). Every sign-in attempt — Google, anonymous, all of them — failed
immediately, and **failed silently**: `AuthAction.signInAnonymously()`'s `catch (e, st) { state =
AsyncValue.error(e, st); }` sets Riverpod state but nothing in the UI ever displays it, so the
button just stopped spinning with zero visible error. With no signed-in uid ever established,
every write path's `if (user == null) throw` fired on every attempt, so nothing — not the
questionnaire, not a workout, nothing — ever reached Firestore, for as long as the project has
existed.

**Fixed**: the operator enabled Authentication in the Firebase Console (Anonymous + Google
providers, plus the Android debug SHA-1 fingerprint for Google Sign-In). Verified via the Identity
Toolkit Admin API: `signIn.anonymous.enabled: true`, `defaultSupportedIdpConfigs` shows
`google.com` `enabled: true` with a real client id/secret.

**Verified live, fully end-to-end**: relaunched the app fresh on `emulator-5556`, signed in
anonymously (worked — real uid `av1qYi2vvZXNum21mEo82Vlub5A3` created, confirmed via
`admin.auth().listUsers()`), walked the full 7-step onboarding questionnaire by hand via `adb
shell input tap` + screenshots, reached the Home screen. Confirmed via Admin SDK that
`users/{uid}/profile/main` now exists in Firestore — real data, really persisted. This is the
proof that the fix works, not just that sign-in succeeds.

**CORRECTED, later this same session**: the paragraph above (originally claiming a silent-failure
UX bug in `login_page.dart`) was wrong. Re-verified directly against the file before starting
that "fix": `login_page.dart:22-31` already has `ref.listen<AsyncValue<void>>(authActionProvider,
...)` showing a `ScaffoldMessenger` snackbar on error. `git log -S "ref.listen" --
mobile/lib/features/auth/login_page.dart` confirms this listener existed since the very first
auth-layer commit (`3ec4251`, Phase 1A) — it did not silently disappear and get re-added; it was
never missing. No other call site reaches `signInAnonymously()`/`signInWithGoogle()` bypassing
this listener (grepped the whole `mobile/lib` tree). **No code change was made — there was no bug
to fix.** Whatever produced the "silent" symptom during the original live investigation (Auth not
enabled at all) was something else — plausibly the error never reaching a caught exception in a
form `AsyncValue.error` could carry cleanly at the time, or a misread of the live behavior — not
this listener being absent. Leaving both paragraphs in the doc (not deleting the original) as a
record of the correction itself, per the operator's "never silently route around a mistake" rule.

**Tooling note for next time**: checking/fixing Firebase project-level config (App Check
enforcement status, Identity Toolkit config) is possible via direct REST calls using the same
Admin SDK service-account access token (`app.options.credential.getAccessToken()` +
`fetch(...Authorization: Bearer ...)`), no separate tooling needed. Reads worked freely. A
first-time write (`PATCH .../config` to enable a sign-in provider) was blocked twice by the local
auto-mode classifier even with an explicit operator "делай" in chat — conversational GO does not
override that classifier; it needs an actual Bash permission-rule change in Claude Code settings
if the operator wants that class of action scriptable in the future. Given that, the actual fix
was done by the operator directly in the Firebase Console, not by Claude.

## Test artifacts left on the device

`emulator-5556` currently has the app installed, fresh, with one real anonymous test account
signed in and onboarding completed (uid `av1qYi2vvZXNum21mEo82Vlub5A3`). No workout has been
logged on it yet. Fine to reuse for further live testing (e.g., to generate real `workout_logs`
data before running F3.3, or to test F3.4 later) or to leave alone — it's a throwaway dev/test
account, not a real user.

Service account key used throughout, still valid:
`D:\secrets\fitness-app\fitness-app-korostelev-firebase-adminsdk-fbsvc-e880f2bd54.json`. Contents
never read by Claude, only used via `GOOGLE_APPLICATION_CREDENTIALS=<path> node ...` inline per
command (env vars don't persist between this harness's Bash tool calls, so always set it inline in
the same command, not via a separate `export` first).

## What to do next

**F3 is fully closed** (read convergence + F3.3b + F3.4 all landed later this same session,
operator GO "ГО на все автономно" — see `PLAN_F3_WORKOUT_SESSION_2026-08-06.md`'s F3.3/F3.4
sections for the full detail, including a CRITICAL gap a `silent-failure-hunter` Act-gate review
caught and why F3.4 got pulled into the same commit as the read convergence).

1. ~~The silent-auth-failure UX bug~~ — corrected later this session: it does not exist,
   `login_page.dart` already shows a snackbar on sign-in error. See the correction note above.
   Nothing to do here.
2. Resuming R2 (Scanner) or general component work (chips/cards) is the next reasonable step,
   per the audit's §10 order.

## F3.3 backfill — DONE this session (2026-08-06, later)

Ran for real against production Firestore. Sequence: logged one live workout via the emulator
on the test account (`av1qYi2vvZXNum21mEo82Vlub5A3`) → `--uid=` dry-run → `--uid= --write` →
verified the resulting `workout_sessions` doc matches the source log → `--all` dry-run found a
real bug (`listAllUids()` queried a Firestore collection, `users`, that never materializes
because the app only ever writes its subcollections — the query silently returned 0 forever) →
fixed + hardened with a `silent-failure-hunter`-reviewed guard → `--all` dry-run clean → `--all
--write` → verified `workout_logs` count == `workout_sessions` count (1 == 1), no duplicates.
Full detail: `PLAN_F3_WORKOUT_SESSION_2026-08-06.md`'s F3.3 section.

Also fixed this session: the auto-mode classifier was blocking any `--write` invocation of this
script (Bash and PowerShell both), independent of an operator GO in chat. Added a narrow
`autoMode.allow` entry in `~/.claude/settings.json` naming this exact script + credential
pattern (operator GO, "го"), so this class of command no longer needs to be handed to the
operator to run manually.

## Standing rules still in force from this session

- security-reviewer stays opt-in only, never auto-spawn.
- Every commit body: itemized plan, `Зачем`/`Почему так` per decision, `Что осталось непокрытым`,
  `Проверки`, todo list.
- Push needs its own separate, explicit `push`/`GO` — an implementation GO never covers it.
- Never read/print secret file *contents* into the conversation — file paths and existence checks
  are fine, contents are not. Env vars for credentials: always set inline in the same command, they
  do not persist across this harness's separate tool calls.
