# Fitness App remediation — consensus plan, 2026-08-04

Responds to an external audit (operator-supplied). Every load-bearing claim in
the audit and in this plan's own first draft was checked against the working
tree at `d16e649` before being planned against — see Part 0. The plan then
went through a 5-agent T3 review round (`architect`, `code-architect`,
`a11y-architect`, `flutter-reviewer`, `planner`); this document is the
post-review version, not the draft. The draft is preserved only inside "what
changed and why" below, per the operator's consensus-presentation rule.

Full agent transcripts + the pre-review draft: `D:\Temp\claude\...\scratchpad\PLAN_AUDIT_REMEDIATION.md`.

---

## The one correction that reshapes the plan

The draft treated "tag the catalog" (S3) as a content-only, weeks-long task
gated behind a code refactor (S2). `planner` found that `S3` as scoped would
have **silently recreated the exact bug this whole audit is about**:

`scripts/catalog/build_vendor_catalog.py:305-306` — `--write` overwrites
`exercises_vendor.json` wholesale from `build()`'s output. There is no merge
with what is already on disk. The stats block at `:295-303` prints six
coverage counters and not one for `contraindications`. Confirmed by direct
read, not taken from the agent: both lines are exactly as reported.

So weeks of hand-tagging would sit one unrelated `--write` away from being
silently discarded — structurally the same failure as `0c4bf24`, which
deleted the only 144 tagged exercises in the product while nothing went red.
**No gate in the draft built the thing that stops this from happening again.**
It is now gate zero.

## Part 0 — What the audit got right, wrong, and missed

(Unchanged from the draft; re-confirmed, not re-litigated. Kept here because
every gate below cites it.)

### Confirmed by reading the cited code

| # | Claim | Evidence |
|---|---|---|
| 1 | Injury normaliser is latin-only | `exercise_filter.dart:14` — `RegExp(r'[^a-z0-9_\s]')`. `колено` → `''`. RU is the default locale. |
| 2 | Safety boundary leaks | `workouts_page.dart:141-170` — 6 of 7 filter branches read `allExercisesProvider` raw. |
| 3 | Tier override ships in release | `settings_page.dart:93+`, `subscription_providers.dart:56`. Zero `kReleaseMode` guard anywhere on this path. |
| 4 | Stripe webhook under-binds secrets | `index.ts:504-509` binds 4 price secrets; `tierFromSubscription` (`:411-424`) reads 6. |
| 5 | Progress photos are mock | `progress_photos_providers.dart:13-41` — `MockProgressPhotosRepository` is the only impl, is the default provider, writes `storagePath: 'mock://...'`. |
| 6 | Marketplace + feed are mock | `marketplace_providers.dart:54,62`; `features/community/data/team_feed_repository.dart`. |
| 7 | No account deletion | zero hits for `deleteAccount`/`deleteUser` in `lib/`. |
| 8 | Terms/Privacy not tappable | `login_page.dart:111-117` — bare `Text`, no recognizer, no route. |
| 9 | Edit-health-questionnaire is dead | `app_router.dart:68-70` bounces an onboarded user straight back to `/home`. |
| 10 | Release signs with debug key | `android/app/build.gradle:47` (confirmed again this round) — `signingConfig = signingConfigs.debug`. |
| 11 | Injury input is free text | `profile_models.dart:41-44` — `Injury{String bodyPart, String type}`. |

### Where the audit is wrong

- **`WorkoutLogEntry` already has `weightKg`/`repsCompleted`/`difficulty`**
  (`workout_log.dart:38-61`) and they round-trip through Firestore correctly
  (`firestore_workout_log_repository.dart:19-48`, confirmed twice this round).
  The gap is capture UI only — `_MarkCompleteButton`
  (`workout_player_page.dart:631-638`) never fills them in. Not a schema
  migration.
- "Almost all filters use the raw catalog" both overstates and understates:
  `forYou` and the equipment detail page **are** filtered; exactly 6 of 7 tabs
  plus one deep link are not. A countable list, not an open-ended sweep.
- Catalog/test counts in the audit are one day stale (legacy catalog deleted
  in `0c4bf24`; 511+1887 and 1095 tests no longer apply).

### What the audit missed

**Contraindication coverage of the shipped catalog is 0 of 1887, not 6%.**
The legacy catalog carried the only 144 tagged exercises; `0c4bf24` deleted
it. `filterContraindicated` opens with
`if (ex.contraindications.isEmpty) return true;` (`exercise_filter.dart:41`)
— at 0/1887 tagged, it is a **total no-op on every surface, including the
ones that correctly call it.** Fixing the Unicode bug or the boundary leak
changes nothing until data exists. This is why the plan leads with an
honesty gate before a data gate.

---

## Part 1 — Gates, as revised by review

Each gate: independently shippable, independently revertible, own test,
stops for a GO before the next. Sizes are honest estimates.

### I0 — Coverage instrument + non-destructive catalog writes (~half day) — FIRST

The smallest gate that is actually load-bearing for everything after it.
`planner`'s nomination, confirmed correct: this is the only gate whose
absence caused the real incident, it touches no user-visible surface, and it
is trivially revertible.

1. `build_vendor_catalog.py`: `--write` merges into the existing file by `id`
   instead of overwriting wholesale. A field the file already has that the
   generator doesn't produce (e.g. a future `contraindications`) survives a
   rebuild.
2. Add a `with contraindications` counter next to the six already at `:295-303`.
3. `exercise_filter.dart`: add `safetyCoverage()` — one function that the
   test, the S0 banner, and the S3 floor all read.
4. Test: coverage floor constant checked into the test file, starting at the
   measured current value (0). Can only be raised.

**Done-criterion:** delete one `contraindications` entry locally → test goes
red. Revert → green. That demonstration is the whole gate.

### S0a — Stop the false safety claim, in code (~half day+)

Everything in this sub-gate is a pure code/copy change with no business
decision attached.

1. Injury-aware surfaces show an explicit, honest banner when coverage is
   below a floor — not silence, not today's always-zero "N filtered for your
   injuries" hint (`equipment_providers.dart:174-176`,
   `equipment_detail_page.dart:354-355`) which reads as reassurance.
   **Design, from `a11y-architect`:** a persistent, non-dismissible-by-tap,
   `Semantics(liveRegion: true)` banner — not a dialog (re-interrupts or goes
   invisible after first dismissal), not a per-item badge (implies un-badged
   rows were checked and cleared — false today), not a Settings
   acknowledgement (buried, reads as liability-shifting). One ARB message via
   ICU plural (precedent: `machineCardSeenTimes`), never a Dart-side ternary
   of literals — the project's own l10n guard test
   (`test/l10n/no_untranslated_strings_test.dart:57-78`) provably misses
   ternary-wrapped `Text(...)`, confirmed by the fact `_FilteredHint` and
   `RestTimer` both already slip past it uncaught.
2. Fix the specific always-false affordances, now enumerated in full (the
   draft named 2 of these 8):
   `equipment_providers.dart:174-176` (`hiddenForInjury` hint),
   `equipment_detail_page.dart:161-162,354-355` (`_FilteredHint`, and the
   empty-state branch that blames "nothing curated" instead of the real
   cause), `home/data/suggestion_builder.dart:130-134` ("Safe with the
   injuries you listed"), `app_en.arb:673` (scanner copy), `app_en.arb:140`
   (`momentsInjuryAwareFilteringIsTheSafety`), `app_en.arb:257`
   (`aboutInjuryAwareExerciseFiltering...`), `moments/widgets/
   injury_filter_celebration_modal.dart` (celebrates a filter that never
   fires).
3. **Folded in from `a11y-architect`** because the files are already open in
   this gate and each fix is 3-10 lines: `GlassCard`'s `InkWell`
   (`shared/widgets/glass.dart:101-108`) gets `Semantics(button: onTap != null)`
   — one shared widget, fixes every tappable card app-wide in one diff. Filter
   chips (`workouts_page.dart:198,209-241`) get `Semantics(button:true,
   selected:...)` and 44dp → 48dp. Both files are already touched by S0/S2.
4. **Test:** if catalog coverage is below the floor, no surface renders an
   injury-filtered claim. This is the test whose absence let `0c4bf24` through.

### S0b — Remove unverified legal/trust claims (business-decision-gated)

Split out because it is not purely a code decision. `planner`: the
tax-deductibility claim **is** the price label
(`subscription_page.dart:957,970` — `subPriceMonthTaxDeductible`), and the
fabricated `'Maria Lopez, DPT'` marketplace listing
(`marketplace_providers.dart:28`) is simultaneously S0's claim-removal target
and M0's mock-labelling target. Whether the product keeps a
nonprofit/tax-deductible framing at all is the operator's business-model call
(there is a nonprofit plan on record) — this sub-gate is blocked on that
decision, not on code, and should run together with M0 once decided.

Also folds in the audit's `features/injury_coach/` finding: `contraindicationsAdded`
(`injury_protocol.dart:44`, populated at `injury_protocol_repository.dart:52,92`)
is a third, dead injury vocabulary — declared and assigned, read nowhere,
with shipped user-facing strings (`app_en.arb:134-135`). One-line call inside
this gate: fold its 4 tags into S1's vocabulary, or delete the feature.

### S2 — Close the catalog boundary (~1-1.5 day) — before S1, not after

`code-architect` + `flutter-reviewer` independently found the draft's fix
(privatize `allExercisesProvider`) closes **0% of the actual deep-link leak**:
`_exerciseByIdProvider`'s non-`ai::` branch
(`workout_player_page.dart:74-80`) never reads `allExercisesProvider` at all —
it re-scans `equipmentRepositoryProvider` directly. The boundary has to be
enforced at the data layer, not by renaming one derived provider.

1. **Mechanism, per `flutter-reviewer`:** real Dart file-privacy (leading
   underscore), not a naming convention — a convention already failed once in
   this exact file (`allExercisesProvider`'s own doc-comment already warned
   "unfiltered", `:36`, and was bypassed 5 times anyway,
   `workouts_page.dart:139-162`). Privatize `allExercisesProvider`,
   `exercisesForEquipmentProvider`, `exercisesForEquipmentWithAiFallbackProvider`
   inside `equipment_providers.dart` — existing in-file precedent for this
   exact pattern: `_filteredExercisesProvider` (`workouts_page.dart:127`),
   `_exerciseByIdProvider` (`workout_player_page.dart:54`).
2. Rewrite `_exerciseByIdProvider`'s raw-scan branch to resolve through the
   same filtered path. Decide and implement what a filtered-out deep link
   returns (a distinct "not shown for your profile" state, not a bare
   "not found").
3. **Split `recommended()`** (`exercise_filter.dart:145-152`) into an explicit
   safety-only entry point and a safety+rank entry point. Today it fuses
   `filterContraindicated` + `sortByTierFit` with no way to get one without
   the other — the doc comment on `exercisesForEquipmentProvider`
   (`:43-44`) already imagines wanting the unranked-but-safe list. Both
   primitives are already standalone and independently tested; this is a
   call-site split, not new logic.
4. **Fix the cold-start leak** (`architect` + `flutter-reviewer`,
   independently found, same root cause): every caller reads
   `ref.watch(currentProfileProvider).valueOrNull`
   (`equipment_providers.dart:185,202`), which collapses `AsyncLoading` and
   "no profile" into the same `null` → `recommended()` falls through to
   unfiltered (`exercise_filter.dart:149`). During cold start or any profile
   refetch, an injured user gets the full catalog for one or more frames.
   Fix: render nothing/skeleton while loading, never the unfiltered list.
5. **New scope this round — scheduled sessions never re-screen**
   (`architect`, confirmed by direct read this round):
   `ScheduledSession` stores only `exerciseId`/`exerciseTitle`, nothing else
   (`scheduled_session.dart:6-23`, confirmed — no injury or safety field
   exists on the type at all). `upcomingSessionsProvider` filters on status
   and date window only (`scheduled_session_providers.dart:37-51`, confirmed
   — `filterUpcoming` never reads a profile or catalog). Record an injury
   today, and yesterday's scheduled squat still renders on Home and still
   fires a reminder notification tomorrow. Fix: re-resolve each session's
   exercise through the same boundary at render/notify time and suppress or
   flag ones that are now contraindicated.
6. **Explicitly enumerate the raw readers that stay unchanged, verified safe**
   (do not silently omit — that is how the original leak hid): `_OfflinePrefetchCard`
   (`workouts_page.dart:394`) and the offline resolver
   (`offline_video_providers.dart:81`) move to the safe list (small named
   behavior change: stop prefetching clips for hidden exercises).
   `personalisation_providers.dart:13-18` (`fitnessProfileProvider`) stays on
   the raw repository — verified it only extracts a muscle map from
   historical logs and never renders an exercise, so filtering it would
   corrupt the fitness model instead of protecting anyone. `workouts_page.dart:164`
   stays raw — it only reads `EquipmentItem` categories, no `ExerciseItem`
   ever crosses it. `ai_planner_providers.dart` stays raw at the pool-build
   step because `plan_builder.dart:32` filters internally before output — a
   third, independently-invented enforcement idiom, worth unifying later, not
   blocking now.
7. **Test:** route-by-route — every tab, the deep link, the player, and now
   the schedule + reminder notification — an injured profile never
   renders or notifies a contraindicated item, **including one sampled
   mid-`AsyncLoading`**, not only after the profile settles (the loading-race
   test gap `flutter-reviewer` flagged: the standard `ProviderContainer` test
   pattern skips `AsyncLoading` entirely unless asked to sample it).

### S1a — Structured injuries, reversible half (~1.5 day)

Split from the draft's single S1 because `planner` + `code-architect`
independently found the backfill is genuinely one-way and currently
undeliverable as scoped. S1a is everything that ships without touching a
single existing user's stored data.

1. Closed enum (shoulder, elbow, wrist, lower back, hip, knee, ankle, neck)
   + free-text `note` that is never matched. Unicode-safety falls out for
   free — an enum cannot carry the bug.
2. **Fix the real blocker `code-architect` found:** the draft's "surfaced for
   re-confirmation" promise has no reachable, save-capable UI. `ProfileRepository.save()`
   has exactly two call sites, both inside `features/onboarding/`
   (`questionnaire_notifier.dart:27-29`, `profile_providers.dart:38-52`).
   The one UI affordance meant to reach it — "Edit your answers"
   (`profile_page.dart:92`) — is provably dead: confirmed again this round,
   `onTap: () => context.go('/onboarding')`, which `app_router.dart:68-70`
   bounces straight back to `/home`. S1a must either patch that redirect for
   a scoped edit path, or build a narrow standalone confirm-injuries screen
   with its own save call. Not optional — without it there is no way to ship
   the enum to an already-onboarded user at all.
3. **Fix the double-serializer drift** `code-architect` found: `Injury.toJson`/`fromJson`
   (`profile_models.dart:46-51`) are dead code — zero production callers. The
   real (de)serialization is a second, hand-inlined implementation at
   `firestore_profile_repository.dart:35-37,113-116`, which also skips the
   null-safe `_enumByName` helper the file already uses for 10 other enums
   (`:78-84`) and casts straight into required `String` fields instead. Route
   the new field through `_enumByName` — less code than what is there today,
   not more, and stops the drift from recurring at the next field.
4. **No version field needed, and don't add one** — the file already has a
   working structural-migration precedent in the same repository:
   `completedAt` is read by type-checking (`if (raw is String) ... if (raw is
   Timestamp) ...`, `:87-90`). Detect old-vs-new `Injury` shape by field
   presence the same way.
5. Per-injury `confirmed: bool`, set only after the user explicitly declines
   a proposed enum match — without it, an injury that structurally cannot map
   (rib, jaw, groin — none of the 8 regions) is indistinguishable on every
   future load from one nobody has looked at yet, and re-confirmation prompts
   forever.
6. Fold in or delete the dead `injury_protocol.dart` vocabulary per S0b.

### S3a — Vocabulary + ratchet (small, mostly absorbed into I0)

Name the tag set from S1a's enum. Wire the coverage floor test (already built
in I0) to be raised, never lowered, by each S3b batch.

### S3b·1..N — Tag the catalog, one batch per gate (weeks, content work)

Same shape as the equipment-linking pass that just shipped: per-row audit
trail, CSV twin, machine-assisted classification from `title` +
`primaryMuscles` + `steps`, reviewed in batches. Each batch's done-criterion
is mechanical: floor constant raised to the newly measured number, CSV twin
committed. Cannot start before S1a names the vocabulary. **Does not block
beta** — S0a makes the product honest without it.

AI-generated exercises (`generated_exercise_repository.dart:82-92` already
serializes a `contraindications` field with no producer) get tagged at
generation time as part of this work, or are excluded for injury-aware users
until they are — this was previously a clause inside S2, it is content work
and belongs here.

### S1b — Backfill existing users' injuries (LAST, not second)

`planner`'s reordering, and it is correct: this is the plan's only step that
mutates already-stored user health data, there is no schema-version
discriminator anywhere in `features/profile` today, and doing it before S3b
has proven the vocabulary against real exercise data means migrating live
data to a vocabulary that might still be wrong. Preserve the original string
in a sibling field; never overwrite in place. Runs after S3b's first batch.

### C0 — Commerce truth (~1 day)

1. **Guard at the read site, not the UI.** `flutter-reviewer`'s correction:
   the draft anchored the fix to `settings_page.dart`; the value is actually
   consumed at `subscription_providers.dart:56`
   (`effectiveTierProvider`). A UI-only guard leaves the read site
   unconditionally honoring whatever is in `AppSettings`. Prefer a
   flavor-scoped `bool.fromEnvironment` over a bare `kReleaseMode` check.
   `app_settings.dart:70-73` currently has a comment arguing *against*
   exactly this kind of gating ("a switch that only works in a build the
   operator never installs is not a test tool") — rewrite it alongside the
   fix, don't leave code and comment contradicting each other.
2. **Name the interaction with R0, don't silently rely on ordering.** Debug
   and release currently share `applicationId`
   (`build.gradle:33`) and release is debug-signed (`:47`) — a release build
   installs as an *update* over a debug install on the same device,
   preserving `SharedPreferences`. A tier set once in debug can survive into
   a "release" install until R0 also ships a real signing key. This doesn't
   change the plan's order (R0 already comes before any real release
   candidacy) — it changes what C0's text has to say: C0 alone does not
   fully close this, R0 does.
3. Bind all 8 price secrets on the webhook (`index.ts:504` binds 4;
   `tierFromSubscription` reads 6 including annual/family — an annual
   subscriber pays and is written back as `free`).
4. **Verify, don't assume:** `test/features/subscription/tier_override_test.dart:30-82`
   has 5 assertions against the override. Confirm they still pass under
   whatever guard mechanism is chosen before shipping — `kReleaseMode` is
   `false` under `flutter test` so a correctly-placed guard is fine, but a
   `bool.fromEnvironment` dart-define needs the test command updated too.

### W0 — Close the logging loop (~1 day) — ship as one commit, not two steps

`code-architect` and `flutter-reviewer` independently derived the same
constraint from different angles: capture and idempotency cannot ship
separately.

1. New capture sheet, following the existing pattern
   (`difficulty_rating_sheet.dart` — `StatelessWidget` + `static Future<T?>
   show()`, result piped via `entry.copyWith`) rather than growing
   `_MarkCompleteButton` inline in an already ~1000-line file that Part 4
   deliberately declines to split.
2. **Idempotency is not a follow-up.** `entry.id` is minted fresh per tap
   (`workout_player_page.dart:633`,
   `'${DateTime.now().microsecondsSinceEpoch}_...'`), and nothing dedups.
   Today a double-tap creates two near-empty rows — harmless. The moment
   weight/reps capture ships, the same double-tap creates two *fully
   populated* rows for one set, and `suggestNextWeight`'s last-3-sessions
   logic (`progression.dart:71-86`) silently double-counts it. Needs new
   local/provider state for "already logged this visit" — the existing
   `loading` flag only blocks concurrent taps, not sequential ones.
3. Edit / undo / delete for history.
4. **Test:** log a set → `suggestNextWeight` returns a real suggestion (today
   unreachable in production because the UI never writes `weightKg`). Plus: a
   double-tap produces exactly one entry.

### M0 — Label or hide the mocks (~half day)

Progress photos, marketplace, community feed. Runs together with S0b (shared
files — the fabricated DPT listing is both).

### L0 — Compliance, split 4 ways (`code-architect` + `planner`, converged)

The draft's single ~2-day estimate covered only the first of these four:

- **L0a — Terms/Privacy routes** (hours). Real routes + content, linked from
  login and settings. No dependency, can run anytime.
- **L0b — Account deletion** (own gate, own second GO — destructive/irreversible).
  Must reach: Auth, `users/{uid}/subscription/main` (`index.ts:453`), workout
  logs (`firestore_workout_log_repository.dart:47`), scheduled sessions
  (`firestore_scheduled_session_repository.dart:45`), **and** cancel the
  Stripe subscription — deleting the account without cancelling billing was
  missing from the draft entirely. Needs `firestore.rules` changes, not
  named in the draft either. This is the actual Google Play blocker (in-app
  deletion + external deletion-request URL for SSO apps).
- **L0c — Data export.** Different code paths, different tests, own gate.
- **L0d — Guest→Google identity migration.** Own UID-orphan risk, shares
  nothing with the other three.

### R0 — Release hygiene (~1 day, signing key is its own second-GO item)

Real signing config (irreversible once a real key signs a published listing
— same class as a live data migration, flag it that way, not as routine
hygiene). Crash reporting. App Check on callables with a monitor-before-enforce
step, not cold enforcement — enforcing on day one against every `onCall` in
`index.ts` without a warm-up period risks an outage, not just a hardening.

---

## Part 2 — Revised order

```
I0 ── S0a ── S2 ── S1a ─┬─ S3a ── S3b·1..N ── S1b
                        │
[operator: business-model decision]
      └─ S0b + M0 (same files, run together)

C0 ───────────────────────────────────────────  (independent — zero shared files with the safety chain)
W0 ───────────────────────────────────────────  (independent)
L0a ───────────────────────────────────────────  (independent, anytime)
L0b, L0c, L0d ─────────────────────────────────  (independent of each other; L0b needs C0's Stripe-cancel path)
R0 ─────────────────────────────────────────────  (last before any real store submission)
```

Two things this graph fixes versus the draft's Part 3:

1. **S2 moved before S1a.** `planner`'s reasoning, and it survives
   cross-check against `code-architect`'s original S1→S2 claim: the two
   agents were answering different questions. The *boundary mechanism*
   (which providers are private, where the deep link resolves, how
   cold-start renders) does not depend on what shape `Injury.bodyPart` is —
   it depends only on `filterContraindicated`'s existing signature, which is
   already stable today. Close the door first, using today's matching logic;
   replace the lock behind the closed door (S1a) after. `code-architect`'s
   real point — S1a needs the enum decided before its *own* file-level
   changes make sense — still holds, it just isn't a dependency of S2.
2. **S0/C0/M0/L0/R0 are not on one chain.** The draft's single top-to-bottom
   diagram implied C0/L0/R0 were blocked on S0. File-level check: S0 touches
   `exercise_filter.dart`/`equipment_providers.dart`/`equipment_detail_page.dart`;
   C0 touches `settings_page.dart` and `index.ts`. Zero overlap. They were
   sequenced in the draft for narrative reasons ("precondition for describing
   the product honestly"), which is a legitimate call for *disclosure order*
   but was drawn as if it were a *build* dependency. Both `architect` and
   `code-architect` flagged this independently.

## Part 3 — What ships without needing S3b's weeks

I0 + S0a + S2 + S1a give: an honest product (no false safety claim), a
closed catalog boundary (nothing bypasses the filter, including the deep
link, cold start, and scheduled sessions), and a real injury data model. All
of that is real engineering, all of it is testable, and none of it requires
1887 exercises to be tagged first. S3b is the long pole for the *feature*
being real; it is not the long pole for the *product* being honest.

## Part 4 — Explicitly not in this plan

- Rewriting `WorkoutLogEntry` or migrating the log schema (unnecessary — verified).
- Splitting the four 800-1150-line page files. Real debt, zero user impact;
  S2 and W0 both already touch `workout_player_page.dart` this round and
  should not be branched in parallel with each other for that reason, but
  neither should carry a file-split alongside its actual fix.
- The palette-level contrast redesign, autoplay/motion handling, and
  200-300% text-scale device verification `a11y-architect` correctly scoped
  as their own phase rather than fold-ins — each needs a design decision or
  device-level verification the gates above don't have the surface area for.
- iOS, Wear, Health write permissions, real marketplace, real social. Any new
  feature.

---

## Review audit trail

**Tier:** T3 (5-7 agents, 1 round). Recon done directly (14 audit claims
verified against the working tree before drafting) in place of a separate
`code-explorer` pass.

**Roster:** `architect`, `code-architect`, `a11y-architect`, `flutter-reviewer`,
`planner` — spawned in parallel, one message. `security-reviewer` not run
(opt-in only per project policy; available on request).

**Post-round spot-check** (Empiricism-over-Poetry cross-check on the four
highest-stakes new claims before accepting them): `build_vendor_catalog.py:305-306`
wholesale overwrite — confirmed exact. `build.gradle:47` debug signing —
confirmed exact. `scheduled_session.dart` no safety field +
`scheduled_session_providers.dart` no re-screening — confirmed exact.
`profile_page.dart:92` dead edit entry point — confirmed exact. Zero
confabulations found in the sampled set.

**Confirmed BLOCKERs, this round:** deep-link leak untouched by the draft's
S2 (architect + code-architect, converged); S0's own trigger self-disarms the
moment any single row is tagged, and is measured globally when it needs to be
per-injury-region (architect); cold-start/loading-race renders unfiltered
catalog (architect + flutter-reviewer, converged); S1's backfill has no
reachable UI to deliver it (code-architect); scheduled sessions never
re-screen and can notify a now-contraindicated exercise indefinitely
(architect); catalog writes are destructive to any future tagging work
(planner); C0's guard was anchored to the wrong file (flutter-reviewer); S0's
copy-removal is coupled to an undecided business-model question, not a code
task (planner).

**Disagreement surfaced and resolved:** `architect` initially read S2's
fix as needing to hide `equipmentRepositoryProvider` itself;
`code-architect` verified two of its call sites and found them safe
(muscle-map extraction, category lookup — neither renders an `ExerciseItem`).
Resolution adopted: keep `equipmentRepositoryProvider` public, enforce
privacy on the derived exercise-list providers instead, and enumerate the
verified-safe consumers explicitly in the gate rather than omitting them.
