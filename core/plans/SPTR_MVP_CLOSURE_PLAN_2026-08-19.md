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

## MVP BLOCKER — MVP-1, CLOSED (`workoutSessionTotalsProvider` and 5 siblings)

**Auth-restore window renders false state as truth, on every cold start, for every returning
user.** Six leaf providers read `ref.watch(authUserProvider).valueOrNull` and collapsed "auth
still resolving" and "genuinely signed out" into the same branch, returning a hard default. Not
a timing race requiring adversarial ordering — `authUserProvider` provably sits in `AsyncLoading`
on every cold start until Firebase finishes restoring the persisted session, so the default
branch is reachable on every launch.

Fixed (test-first: each reproduced with a failing test against the live bug, then fixed, then
confirmed passing — see `core/DECISION_LOG.md`'s MVP-1 entry for the full list): `workoutSessionsProvider`,
`workoutSessionTotalsProvider`, `currentProfileProvider`, `programmesProvider`,
`generatedPlanProvider`, `scheduledSessionsProvider` (`mobile/lib/features/workouts/state/workout_session_providers.dart`,
`profile_providers.dart`, `programme_providers.dart`, `ai_planner_providers.dart`,
`scheduled_session_providers.dart`). Pattern: `await ref.watch(authUserProvider.future)` instead
of sampling `.valueOrNull` — already proven 3x elsewhere in this codebase before this gate
(`screeningProfileProvider`, `currentSubscriptionProvider`, the photo-store providers).

**Correction to the type-design-analyzer review round**: it flagged `workoutLogsProvider`/
`workoutTotalsProvider`/`logWorkoutActionProvider` (`workout_log_providers.dart`) as also live,
citing an `ref.invalidate(workoutTotalsProvider)` call — that call is `LogWorkoutAction`'s own
internal self-reference inside the same dead file, not evidence of an external caller. Verified
directly (`grep -rn` across `mobile/lib`, zero external references): this file is genuinely dead
code, superseded by `workout_session_providers.dart` per that file's own doc comment. Left
untouched — fixing dead code would be wasted, risk-adding work, not a "smallest safe fix".

**MVP NEED**: blocker — violates the north-star flow's own "auth path must not show false state
as truth" point directly and reproducibly.
**User failure without it**: every returning user with real workout/programme/scheduled-session
history sees it apparently wiped, every single time they open the app, until the async gap closes.
**Cheapest alternative considered**: none — an existing screen lying about existing data cannot be
hidden or deferred like an unbuilt claim. Must fix.

## MVP REQUIRED — found during MVP-1's own review, not yet started

Independent review of MVP-1 (flutter-reviewer + type-design-analyzer) surfaced two further real,
evidenced gaps in the same "auth/session path lies to the user" criterion. Both are genuine
(verified myself, not taken on the reviewer's word alone) but are their own properly-scoped
gates, not folded into MVP-1's already-large diff — each touches a different layer.

**MVP-2 — RECLASSIFIED to POST-MVP after MVP-3 closed (explicit scope decision, not a silent
drop).** `workoutSessionHistoryProvider`, `activeProgrammeProvider`, `_sessionsOf`
(`progress_page.dart:117-118`), and at least 10 more call sites across
`home_dashboard_providers.dart`, `programme_providers.dart`, `recovery_providers.dart`,
`offline_video_providers.dart`, `session_screening_providers.dart`, `workout_player_page.dart`,
`form_check_providers.dart`, `setup_note_card.dart`, `exercise_reference.dart`,
`set_timer_providers.dart`, `equipment_detail_page.dart` all read a now-correctly-loading provider
via `.valueOrNull ?? default` — a plain (synchronous) `Provider` or a raw UI read cannot itself
stay "loading", so in isolation this still silently renders a false default one hop downstream of
MVP-1's fix.

**Why POST-MVP now, when it was REQUIRED at the time it was found**: it was scoped against a
codebase where the splash screen navigated on a fixed timer, so a user could reach these screens
*while `authUserProvider` was still genuinely `AsyncLoading`* — that was the reachable "confident
lie" window. MVP-3 (closed above) makes `/splash` wait for `authUserProvider`'s real first
emission before ever navigating to `/home`, and a `StreamProvider` that has emitted once stays
`AsyncData` for every later watch (Riverpod caches the last value; it does not spontaneously
re-enter `AsyncLoading` mid-session). So by the time a user can reach Progress, Home, Programmes,
or any of the other call sites, `authUserProvider` — and every MVP-1-fixed provider built on it —
has already resolved. Confirmed structurally, not assumed: `app_router.dart`'s redirect only
allows past `/login` when `isSignedIn` (`authRepo.currentUser != null`), and MVP-3's own review
verified there is no OS-level deep-link/state-restoration entry point anywhere in this app that
bypasses `/splash` (`initialLocation` is hardcoded to `/splash`; no `uni_links`/`app_links`/
`RestorationMixin` found). The remaining `.valueOrNull ?? default` reads are therefore bounded to
ordinary Firestore-fetch latency (the network round-trip *after* auth resolves) — normal
loading-flicker every app has, not the auth-restore truthfulness defect the north-star criterion
names. Verified concretely on Progress, the one call site with a passing regression test written
against the actual bug (`deriveProgress`'s two "no logs" branches, `progress_stats.dart:66-78`):
that test exercised the pre-MVP-3 world where splash navigated on a fixed timer regardless of
auth; it does not describe the post-MVP-3 reachable state.
**MVP NEED (re-scored)**: was required, now POST-MVP — the truthfulness gap it was required to
close is already closed transitively by MVP-1 + MVP-3 together.
**Cheapest alternative, deferred rather than applied**: gate the affected screens' rendering on
`.isLoading` (matching the codebase's own existing correct pattern at `entitlementStatusProvider`
and `workout_player_page.dart:505-507`) — worth doing for UX polish (a skeleton beats a flashed
zero during a real fetch), but that is a POST-MVP improvement, not an MVP truthfulness fix.

**MVP-3 — CLOSED.** The auth-restore race also reached app navigation itself. `app_router.dart`'s
`redirect` reads `authRepo.currentUser` — a synchronous Firebase getter with the identical
cold-start ambiguity (null until session restore completes, even for a returning signed-in user)
— not through any resolved-stream contract; if reached before restore completes, a real signed-in
user would have been redirected to `/login`.

Fixed (test-first, same reproduction pattern as MVP-1 — see `core/DECISION_LOG.md`'s MVP-3 entry
for the full trail, including a self-caught false-pass in the first draft of the reproduction
test): `splash_page.dart` now waits for `authUserProvider`'s real first emission (raced against
the existing minimum-dwell timer, `Future.wait`, so normal-path timing is unchanged) before ever
leaving `/splash`, bounded by a 5s safety timeout so a broken/hung stream cannot strand the user.
Both the timeout and a genuine stream-error path are logged (`debugPrint` +
`FirebaseCrashlytics.instance.recordError`, non-fatal), matching this codebase's own established
boot-time-guard logging convention — a silent-failure-hunter and flutter-reviewer finding, fixed
in this gate rather than deferred. The fix's core premise (that `authRepo.currentUser` is already
synchronized by the time `authUserProvider`'s stream fires) was independently verified against the
pinned `firebase_auth_platform_interface` 8.1.9 source, not left as an assumption, and recorded as
a doc comment on `FirebaseAuthRepository.currentUser`.

`questionnaireDraftProvider` (`questionnaire_notifier.dart:14-23`) has the same defect shape in a
synchronous `Notifier.build()` and is entangled with this same router path (onboarding is only
reachable after `isSignedIn` resolves) — decided below (accept as mitigated), not folded into
this gate.
**MVP NEED**: required — this is literally the "authentication/session path" the criterion names.
**Cheapest alternative applied**: made the splash screen wait for `authUserProvider`'s actual first
emission instead of a fixed timer, rather than restructuring the router's redirect contract.

## `questionnaireDraftProvider` — decided: accept as mitigated by MVP-3, not separately fixed

`questionnaireDraftProvider`'s `build()` (`questionnaire_notifier.dart:16-18`) reads
`ref.watch(authUserProvider).valueOrNull`, the same collapse shape as MVP-1's leaf providers, but
inside a synchronous `Notifier.build()` where `await ref.watch(authUserProvider.future)` doesn't
drop in as-is (a `Notifier.build()` cannot be `async`). type-design-analyzer flagged it MINOR
during the MVP-1 review.

Checked directly, same reasoning as the MVP-2 reclassification above: `app_router.dart`'s redirect
only routes to `/onboarding` when `isSignedIn` is true (`authRepo.currentUser != null`,
`app_router.dart:62-92`), and MVP-3 guarantees `authRepo.currentUser` is already synchronized to
`authUserProvider`'s stream by the time `/splash` hands off. So by the time
`QuestionnaireDraft.build()` can run at all, `authUserProvider`'s `.valueOrNull` is no longer null
for a signed-in user — the window this provider's shape is vulnerable to is structurally
unreachable via the only path that reaches it. **Decision: accept as mitigated, no separate code
change.** Not the same call as MVP-2 (which is deferred UX polish for a still-real, just
lower-priority gap) — here the specific defect this shape enables is not reachable at all given
the current router gating, so there is nothing left to fix.

## POST-MVP (evidence preserved, not started)

- **MVP-2 (reclassified) — downstream `.valueOrNull ?? default` reads** on Progress, Home,
  Programmes, and ~10 more call sites (full list above). Gate on `.isLoading` for a skeleton
  instead of a flashed zero during real Firestore-fetch latency — genuine UX polish, not a
  truthfulness fix now that MVP-1 + MVP-3 close the actual auth-restore window these screens can
  ever be reached during.
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

1. **MVP-1** — CLOSED. Auth-restore false-state collapse at the provider layer, 6 leaf providers,
   test-first, full suite + `flutter analyze` clean, independent review (flutter-reviewer +
   type-design-analyzer), findings fixed, committed, **pushed**, remote SHA verified.
2. **MVP-3** — CLOSED. The router-redirect instance of the same defect, structurally closed (the
   splash screen now waits for the real auth emission instead of a fixed timer), test-first, full
   suite + `flutter analyze` clean, independent review (flutter-reviewer), findings fixed,
   committed, **pushed**, remote SHA verified. (Done ahead of MVP-2 in the original numbering —
   closing the navigation gate first is what let MVP-2 be reclassified below instead of built.)
3. **MVP-2** — RECLASSIFIED to POST-MVP. Once MVP-1 + MVP-3 both closed, the reachable
   "auth-restore truthfulness" window they were required to fix no longer exists for any of
   MVP-2's downstream call sites — see the reasoning under MVP-2 above. `questionnaireDraftProvider`
   decided the same way (accept as mitigated, no code change). No MVP work remains from this item.
4. **Release gate** — IN PROGRESS, real-device pass started (`emulator-5554`, Pixel API 34, debug
   APK). See checklist below and `core/DECISION_LOG.md`'s release-gate entry for full evidence.
   Not yet complete — several items still need coverage before this step can close.
5. **Final dream-team review** — MVP-only question: does anything block a minimal, honest,
   safe release? Not "what could be better." Not started — waits on the release gate closing.
6. **MVP READY** — report to operator and stop. Do not auto-start POST-MVP.

## Release gate checklist (MVP-only bar)

- [x] **Install/build** — `flutter build apk --debug` succeeded, installed cleanly via `adb`.
- [x] **First launch** — correct RU welcome screen, no crash.
- [x] **Auth, including the just-fixed restore window** — the one check this gate exists for,
  confirmed directly: anonymous sign-in works; a true cold start (`am force-stop` then relaunch)
  restored the same session straight to Home with no `/login` bounce and no MVP-3 timeout/error
  log — the real fix, not just its unit test, verified live.
- [ ] **Scan (known / ambiguous / unknown equipment)** — screen loads, ambiguity + privacy
  disclaimers render correctly, system photo-picker opens without error. Full recognition
  round-trip **not exercised** — this AVD has no camera passthrough and no gym-equipment photo was
  available. Needs a real device or a seeded test image.
- [x] **Exercise/instruction path** — Library → exercise detail loads correctly: level,
  equipment, type tags, muscle diagram, "why this matters" copy. Video asset was unavailable on
  this AVD and the app said so honestly ("Ссылка на ролик недоступна") rather than failing
  silently or showing a broken player.
- [x] **Injury/safety filtering** — the real editable surface (`/injuries`, the "Травмы" tile)
  loads correctly with an honest empty state and working explanatory copy. (The separate "Анкета
  о здоровье" tile dead-ends back to `/home` — confirmed pre-existing/documented in
  `injuries_page.dart`'s own doc comment, not a regression from this session.)
- [x] **Persistence** — the same anonymous session and its state survived a full process kill and
  relaunch.
- [ ] **Account isolation** — not exercised; needs a second real account.
- [~] **EN + RU critical flow** — RU confirmed live, on-device, throughout this pass. EN not
  confirmed live: Android's per-app-locale command reported `en-US` applied
  (`cmd locale get-app-locales`) but the app kept rendering Russian after a force-stop + relaunch,
  most likely a locale-propagation timing quirk of this AVD/launch method
  (`deviceLocalesProvider` reads `PlatformDispatcher.instance.locales` once at provider-container
  creation) rather than an app defect — not chased further given the cost/value here. Indirect
  evidence stands in for a live check: the full suite's default (`kTestLocale = Locale('en')`,
  `test/helpers/test_app.dart:15`) already runs and passed 2508/2508 in English, including every
  test touched this session (`splash_page_test.dart`). EN visually on a real device remains open.
- [x] **Offline/network failure behavior** — Home and Scan both render cleanly with wifi+data
  disabled via `svc`; no crash, no infinite spinner, no misleading state. (Used service-level
  toggles, not the OS airplane-mode UI path — close enough for this check, not identical.)
- [x] **Privacy truth** — the scan screen's own disclosure (photo sent to Gemini, on-device
  fallback, bystanders may be captured) matches what the plan doc already established.
- [x] **Marketing truth** — already established pre-MVP (`claim_lint.py` clean); not re-checked
  this pass, no marketing-facing code changed.
- [x] **No critical console/runtime failures** — no `FATAL`/`AndroidRuntime` crash at any point.
  Environment-only noise (TLS trust-anchor / Play-Services Phenotype failures) attributed to this
  bare AVD image, not the app — see decision log.
