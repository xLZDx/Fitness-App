# SPTR MVP Closure Plan

2026-08-19. Operator course change: MVP FIRST, then POST-MVP. Supersedes the open-ended
Gate-D-H-style "close every real seam" mode for now. Source of truth for what ships before
release and what waits. Short by design — see `core/DECISION_LOG.md` for full evidence trails.

## Minimal MVP definition

A user can install/open the app, do a short onboarding, point the camera at gym equipment,
get an honest identification (or an honest "don't know"), see what exercises it supports and
the content needed to use them, safety/injury filtering never fails open, no data leaks or
lies between accounts or across the auth-restore window, and the app can actually be built and
handed to a real tester. Public claims match what's actually shipped.

## Recon method

Four parallel read-only agents swept the current working tree (not old reports) against the
10-point north-star flow: onboarding, scan→recognition→content, safety-critical gating,
account isolation, auth/session honesty, buildability, and marketing truth. Full findings in
each agent's transcript; verified myself where noted below.

## Existing state — what's already solid (no MVP work needed)

- **Onboarding**: minimal skip-through path works end-to-end; state persists across a kill
  except unsaved keystrokes on the in-progress screen (bounded, cosmetic).
- **Scan → recognition → content**: three-way outcome handling (confident/ambiguous/unknown)
  is honest, no dead ends; offline/timeout paths degrade to on-device fallback or a retryable
  error, never a silent misclassification.
- **Safety-critical gating**: injury filtering and the pose-check gate are both genuinely
  enforced and fail closed by trace, with prior bugs of exactly this class already fixed and
  documented in-code. Catalog contraindication tagging is 81% complete (1,527/1,887) and the
  gap is disclosed live (`SafetyScreeningLevel`), not hidden.
- **Account isolation**: `firestore.rules` correctly uid-scopes every per-user collection; no
  over-permissive path found. Local sensitive storage is uid-keyed
  (`profile.sensitive.$uid`). Riverpod profile/screening providers correctly re-resolve on a
  uid change (switching accounts), not just null↔non-null.
- **Buildable today**: real release signing (`key.properties` + keystore both present on
  disk), real `applicationId`, real committed Firebase config, working build script
  (`scripts/dev/build_release.ps1`) and CI (`.github/workflows/flutter.yml`). Android only —
  iOS is a stated, documented scope decision (`core/PLATFORM_SCOPE.md`), not a gap.
- **Marketing truth (allowed-gate claims)**: every publicly-showable claim spot-checked against
  code is true. `claim_lint.py` passes clean.

## MVP BLOCKER

**Auth-restore window renders false state as truth, on every cold start, for every returning
user.** `workoutSessionTotalsProvider` / `workoutSessionsProvider`
(`mobile/lib/features/workouts/state/workout_session_providers.dart:23-29,43-48`) read
`ref.watch(authUserProvider).valueOrNull` and collapse "auth still resolving" and "genuinely
signed out" into the same branch, returning a hard zero. This is not a timing race requiring
adversarial ordering — `authUserProvider` provably sits in `AsyncLoading` on every cold start
until Firebase finishes restoring the persisted session, so the zero branch is reachable on
every launch. `deriveProgress` renders it as **"0 workouts, 0-day streak"** for a real user with
real history — the exact false-state-as-truth condition the MVP definition rules out.

Same root cause, same reach, additional confirmed instances: `currentProfileProvider`
(`profile_providers.dart:31-36`, shows "Sign in to sync" to an already-signed-in user),
`programmesProvider`, `generatedPlanProvider`. The legacy `workoutLogsProvider`/
`workoutTotalsProvider` (`workout_log_providers.dart`) have the same shape but are confirmed
dead code — no UI references them — out of scope.

This is not a hypothesis: reproducibility is provable from the code shape alone (a
synchronously-reachable branch, not a suspected race). The fix pattern already exists and is
proven three times elsewhere in this exact codebase (`screeningProfileProvider`,
`currentSubscriptionProvider`, the photo-store providers) — `await ref.watch(authUserProvider.future)`
instead of sampling `.valueOrNull`.

**MVP NEED**: blocker — violates the north-star flow's own "auth path must not show false state
as truth" point directly and reproducibly.
**User failure without it**: every returning user with real workout history sees their progress
apparently wiped, every single time they open the app, until the async gap closes.
**Cheapest alternative considered**: none — this isn't a claim that can be hidden or an optional
feature that can be cut; it's an existing screen lying about existing data. Must fix.

## MVP REQUIRED

None found beyond closing the blocker above. The recon deliberately looked for gaps across all
ten north-star points and found the rest already correctly built.

## POST-MVP (evidence preserved, not started)

- **Gate I — gym-scoped workout memory** (full evidence already gathered this session,
  see the prior turn's recon). Equipment-TYPE memory (Gate D) already covers the honest minimal
  claim; gym-scoping is retention/correctness polish, not required to ship truthfully.
- **No rate-limit/cooldown on manual recognition taps** — cost-exposure risk, not a
  correctness/safety gap; no evidence of an automatic loop that could trigger it. Add a cheap
  cooldown post-MVP if billed-call cost becomes a real concern.
- **Catalog contraindication tagging beyond 81%** — content work, already honestly disclosed
  live; not a blocker.
- **SharedPreferences not wiped on sign-out** — retention hygiene, not a mixing bug (storage is
  uid-keyed, so a second account can't read the first's cached data). Add a wipe-on-sign-out
  post-MVP.
- **Marketing site qualify-disclaimers only render under `?debug=1`** — a real overclaim-by-omission
  *if the site were shown publicly today*, but the site is explicitly an internal R&D prototype,
  never the MVP's launch surface (see Gate A/B/C decision-log entries: "ships as an R&D
  instrument, not a launch asset"). Not an app-MVP blocker. **Hard pre-condition before the site
  is ever made public**, tracked separately from the app release gate below.
- **`mobile/README.md`** still Flutter boilerplate; real build docs live only in
  `scripts/dev/build_release.ps1`'s header comment. Cosmetic, fix opportunistically.

## FULL PRODUCT

Everything else already logged as shipped-or-deferred across Gates D-H (MRD-01 through
MRD-07), plus any future personalization/moat work. No new items added here.

## Execution order

1. **MVP-1** — reproduce the auth-restore false-state collapse with a test first (no fixing on
   hypothesis), then apply the proven `await authUserProvider.future` pattern to the confirmed
   live instances, full suite + mutation proof, independent review (flutter-reviewer +
   type-design-analyzer), commit, **push immediately**, verify remote SHA.
2. **Release gate** — device/emulator pass over: install/build, first launch, auth, scan flow
   (known/ambiguous/unknown machine), exercise/instruction path, injury filtering, EN+RU,
   offline behavior, no console/runtime failures.
3. **Final dream-team review** — MVP-only question: does anything block a minimal, honest,
   safe release? Not "what could be better."
4. **MVP READY** — report to operator and stop. Do not auto-start POST-MVP.

## Release gate checklist (MVP-only bar)

Install/build · first launch · auth (including the just-fixed restore window) · scan (known /
ambiguous / unknown equipment) · exercise/instruction path · injury/safety filtering ·
persistence/account isolation · EN + RU critical flow · offline/network failure behavior ·
privacy truth · marketing truth (allowed-gate claims only — the site itself stays internal) ·
no critical console/runtime failures.
