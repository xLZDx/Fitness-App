# 24 - Programme generation quality

## BLOCKER - the "built from your answers" programme is an alphabetical filler

Four of seven enrollable programmes have a `ProgrammeSpec` (`programme_specs.dart:116-160`:
`strength_base`, `hypertrophy`, `gym_start`, `injury_comeback`). Three do not - `shred_endurance`,
`shoulders_arms`, and **`from_answers`**, which is the questionnaire-built programme and the one
surface that claims to be personalised.

For those three, `programmeSpecFor` returns null and enrolment falls through to
`buildProgrammeSchedule` -> `_fillDay` (`programme_schedule.dart:183-197`). Confirmed by direct read:
`_fillDay` takes `pool[startAt]` and then walks **consecutive** indices `(startAt + step) %
pool.length`. The pool is sorted by id.

Every row in the shipped catalogue is `durationMinutes: 10`, so a 45-minute session yields exactly
four alphabetically adjacent rows. Day 0 of a full-body enrolment is `ea_180_jump_turns`,
`ea_3_4_sit_up`, `ea_3_leg_chatarunga_pose`, `ea_3_leg_dog_pose` - two yoga poses, a sit-up and a
plyometric jump, for any goal, any level, any focus.

`programme_builder.dart:5-16` documents this exact defect as fixed. It is fixed for the four
templates that have a spec, and the sharper reading is that the fix never reached the default path.

## BLOCKER - the same path bypasses the whole-person safety gate

Two independent reviewers reached this finding separately. `programme_providers.dart:199-206` calls
`buildProgrammeSchedule(programme:, catalogue:, sessionMinutes:, preferredWeekdays:)` - **confirmed
by direct read: no `SafetyContext` argument exists on that function at all.** Its catalogue is
`safeCatalogProvider`, which applies the injury filter only.

`buildPlan` refuses on `!safety.allowsAnyTraining` (`plan_builder.dart:46-48`) and `buildProgramme`
refuses identically (`programme_builder.dart:318-320`). This path does neither. A user whose PAR-Q+
answers refuse them training, or who reported a clinician advised against exercise, or who is under
unexpired post-operative restrictions, is refused by the AI planner and by the spec programmes - and
can still enrol here and receive 24 scheduled sessions written to storage.

This is the failure mode `eligibility.dart:1-16` was written to end: a rule added to one call site
and absent from another.

## HIGH - the fallback repeats three of four exercises between consecutive days

`programme_schedule.dart:118` uses `startAt: (week + slot) % pool.length`. Week 0 slot 0 gives items
0-3; slot 1 gives items 1-4. `week + slot` also collides across weeks, so an eight-week programme
draws on a window of roughly ten exercises. `_fillDay`'s doc promises only "never repeats within a
day" - true, and not the property that matters.

## HIGH - level is stored, never enforced

Neither `programme_builder.dart:315-417` nor `programme_schedule.dart:62-197` references
`ExerciseDifficulty`. `Programme.level` is used for labels. The eight `advanced` rows - including
`ea_headstand`, `ea_hand_stand_hold` and `ea_tyre_flip` - are withheld from nobody. A self-declared
beginner can be scheduled a headstand, and no mechanism exists that would stop it.
