# Claude Code prompt — Recommendation Engine v1.1 / G1 ONLY

Repository: `D:\Repo\Fitness_App`
Expected remote baseline from audit: `5b7c9acc7acdd00db502e1934afd2c75983eaeb9` on `master`.

You are implementing **G1 only** of Recommendation Engine v1.1.

## Mandatory first action

Read:
- `CLAUDE.md`
- `AGENTS.md`
- `core/CODEMAP.md`
- `core/CONVENTIONS.md`
- this bundle's `00_G0_REAL_REPO_AUDIT.md`
- `01_IMPLEMENTATION_MAP.md`
- `04_GATE_PLAN.md`

Then verify the **local** repository, because the audit only saw GitHub remote:
- current branch;
- HEAD;
- upstream;
- `git status`;
- unpushed commits;
- untracked files;
- active/concurrent work.

If local HEAD or working tree makes the G0 mapping stale/conflicted, STOP and report.
Do not reset, stash, discard or overwrite another session's work.

## Scope — G1 only

Create the smallest domain skeleton under:
`mobile/lib/features/recommendation/`

Allowed G1 responsibilities:
- RecommendationContext model;
- RecommendationResult/status/reason-code primitives;
- provenance/freshness primitives;
- interfaces for SafetyGate / Eligibility / Prescription / Load / Progression / Validator;
- Riverpod context provider that composes existing sources;
- tests for context/loading/provenance;
- CODEMAP update required by project convention.

### Reuse, do not duplicate

Use existing:
- `UserProfile`
- `ExerciseItem`
- `WorkoutSession`
- `ScheduledSession`
- `Programme`
- `HealthSnapshot`
- `screeningProfileProvider`
- existing repositories/providers.

The new feature must not introduce:
- another profile repository;
- another catalog repository;
- another workout repository;
- another router/state framework;
- a new backend schema.

## Absolutely out of scope in G1

Do NOT:
- change current user-visible recommendation behavior;
- fix `progression.dart` yet;
- change Firestore models;
- change AI Coach prompt;
- change AI Planner;
- change Home suggestions;
- change programme schedule;
- implement clinical rules as invented constants;
- push.

G1 is the seam and contract only.

## Required tests

At minimum:
1. context waits for safety-critical profile loading rather than interpreting loading as no restrictions;
2. optional health missing remains missing;
3. context uses canonical WorkoutSession data, not only flattened last-set history;
4. provenance identifies which inputs are present/stale/missing;
5. no duplicate domain source models are introduced.

Run targeted tests, then `flutter analyze`, then full `flutter test`.

Do not claim pass counts you did not actually execute.

## Finish

Self-review scoped diff.
One local commit only if all required checks pass.
Then STOP.

**No push. Push requires a separate explicit push-GO.**
