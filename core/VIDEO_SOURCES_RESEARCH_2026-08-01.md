# Exercise Video Sources — Research Report

**Date:** 2026-08-01 16:31 local (Europe/Chisinau) / 13:31 UTC
**Scope:** read-only research. No video was downloaded. No repo file was modified except this report and its CSV twin.
**CSV twin:** `core/video_gap_168.csv` (the 168-row gap list, machine-readable)

**Question asked:** 168 of 511 catalog exercises have no demo video. Can @WorkoutAnimation99 (free), ready-made full workout videos, or the exerciseanimatic.com paid pack close that gap?

**Answer in one line:** the paid pack is the only one of the three whose licence provably permits what this app needs — and I can quote the sentence that makes it so. The YouTube channel states no licence at all and is structurally the wrong shape (168 muscle-group compilation reels, not per-exercise clips). Full workout videos do not fit the app's per-exercise data model except for 15 cardio rows.

---

## Contents

1. [A. The 168 gap](#a-the-168-gap)
2. [B. @WorkoutAnimation99](#b-workoutanimation99)
3. [C. Ready-made full workout videos](#c-ready-made-full-workout-videos)
4. [D. The exerciseanimatic paid pack](#d-the-exerciseanimatic-paid-pack)
5. [Comparison table](#comparison-table)
6. [Recommendation](#recommendation)
7. [Draft: question to send @WorkoutAnimation99](#draft-question-to-send-workoutanimation99)
8. [Method and verification log](#method-and-verification-log)

---

## A. The 168 gap

**Source file:** `D:\Repo\Fitness_App\mobile\assets\data\exercises.json` — 511 entries, 718,135 bytes (measured `wc -c`, 2026-08-01).

### Headline counts

| Metric | Count | How measured |
|---|---|---|
| Total exercises | 511 | `len(json.load(...))` |
| Have a non-empty `video` map | 343 | `sum(1 for e in d if e.get('video'))` |
| **Have no `video` key at all** | **168** | `sum(1 for e in d if 'video' not in e)` |
| Have a `video` key that is empty | 0 | `sum(1 for e in d if 'video' in e and not e['video'])` |

So the gap is clean: 168 rows are simply missing the key. There is no partial/broken-video case to untangle.

### Shape of the videos that DO exist

Of the 343 with video: **310 have both `girl` and `men`**, 28 are `girl`-only, 5 are `men`-only.

They are self-hosted, not hotlinked to a third party. Example (`barbell_guillotine_bench_press`):

```
girl: https://storage.googleapis.com/traidingbot-b4061-videos-eu/exercises/girl/Chest/Barbell%20Bench%20Press.mp4
men:  https://storage.googleapis.com/traidingbot-b4061-videos-eu/exercises/men/chest/Barbell%20Bench%20Press.mp4
```

Two things follow from this, and both matter for the recommendation:

- The delivery pipeline already exists — GCS bucket, per-gender folders, per-muscle subfolders. Adding 168 more clips is a content problem, not an engineering problem.
- Whatever licence question applies to the 168 **also applies retroactively to the 343 already shipped**. Per the project memory note (`reference_fitness_exercise_video_sources.md`), the current library is unlicensed scaffolding from a Drive collection. Closing the gap with a licensed source while leaving 343 unlicensed clips in the bucket does not make the app shippable. See [Recommendation](#recommendation).

### The gap is not evenly spread

**By equipment class** (my grouping of `equipmentId`; the raw per-equipment counts are in the full table below):

| Class | Missing | Note |
|---|---|---|
| Free weight (barbell/dumbbell/kettlebell/plates/benches/rack) | 61 | |
| Selectorised & cable machines (incl. Smith, cable, T-bar) | 59 | |
| Bodyweight + rig (pull-up bar, dip station, plyo box, bands) | 21 | |
| Cardio machine (treadmill, rower, ski erg, air bike, etc.) | 15 | see below — these are the odd ones |
| No equipment (`equipmentId: null`) | 12 | |

**Most-affected single equipment IDs** (missing / total in catalog) — these are near-total blackouts, not thin spots:

| equipmentId | Missing / total | Coverage |
|---|---|---|
| `kettlebell` | 12 / 13 | 8% |
| `rowing_machine` | 2 / 2 | 0% |
| `foam_roller` | 2 / 2 | 0% |
| `stair_climber` | 2 / 2 | 0% |
| `air_bike` | 2 / 2 | 0% |
| `ski_erg` | 2 / 2 | 0% |
| `bicep_curl_machine` | 1 / 1 | 0% |
| `punching_bag` | 1 / 1 | 0% |
| `recumbent_bike` | 1 / 1 | 0% |
| `squat_rack` | 7 / 8 | 13% |
| `plyo_box` | 7 / 8 | 13% |
| `lat_pulldown` | 7 / 10 | 30% |
| `treadmill` | 4 / 5 | 20% |
| `chest_press_machine` | 5 / 8 | 38% |
| `medicine_ball` | 5 / 6 | 17% |

By contrast `dumbbell` is 7/72 missing (90% covered) and `resistance_bands` 4/32 (88% covered). **The gap is concentrated in gym machines and kettlebells** — exactly the categories a home-workout-oriented video library tends to skip.

**By primary muscle:** quads 31, chest 24, shoulders 23, core 19, lats 16, biceps 10, triceps 8, back 8, hamstrings 8, lower_back 5, glutes 5, calves 4, adductors 3, forearms 2, traps 2.

**By difficulty:** beginner 99, intermediate 59, advanced 10.

**Stretches:** 0 of the 168 are stretches. All 61 `isStretch: true` entries already have video.

### The `fedb_` pattern — where the gap came from

| id prefix | Total | Missing | Missing % |
|---|---|---|---|
| `fedb_*` | 142 | 106 | **75%** |
| everything else | 369 | 62 | 17% |

Three quarters of the `fedb_`-prefixed rows are missing video, versus one sixth of the rest. `fedb` is almost certainly *free-exercise-db*, a second import that was merged into the catalog after the video-matching pass ran. This is a useful diagnostic: the gap is largely one un-processed import, not 168 individually hard cases.

### Fallback visuals — only 10 rows are truly blank

| | Count |
|---|---|
| Missing video but **have `frames`** (2 local JPGs) | 52 |
| Missing video but **have `imageUrls`** (remote stills) | 106 |
| Have both | 0 |
| **Have neither — no video, no frames, no images** | **10** |

The 10 rows with zero visual assets of any kind:

| id | title | equipment |
|---|---|---|
| `air_bike_intervals` | Air Bike Intervals | air_bike |
| `air_bike_steady` | Air Bike Steady Effort | air_bike |
| `treadmill_incline_walk` | Incline Walk | treadmill |
| `rowing_intervals` | Row Intervals | rowing_machine |
| `treadmill_intervals` | Run Intervals | treadmill |
| `ski_erg_intervals` | Ski Erg Intervals | ski_erg |
| `ski_erg_steady` | Ski Erg Steady Pull | ski_erg |
| `rowing_steady` | Steady Row | rowing_machine |
| `treadmill_steady_run` | Steady-State Run | treadmill |
| `treadmill_warmup_walk` | Warm-up Walk | treadmill |

**All ten are cardio-machine efforts, not discrete exercises.** "Run Intervals" is a prescription (do this for N minutes), not a movement to demonstrate. This is the one place in the catalog where a longer video genuinely fits — and it is the one place an exercise-animation library will *not* help, because these are not exercises. Note also that the 15 cardio rows collapse onto only **8 distinct machines** (treadmill, rower, ski erg, air bike, stair climber, elliptical, exercise bike, recumbent bike), so 8 generic machine loops cover all 15 rows.

**So the gap is really two gaps:**
- **158 rows** need a per-exercise motion demo. They already have a static image, so today they degrade rather than break.
- **10 rows** (15 counting the ones that do have stills) are cardio efforts that need something different — a loop or a timed session, not an exercise demo.

### Full list of the 168

Grouped by `equipmentId`, largest group first, alphabetical within group. `frames` / `imageUrls` = Y if present. Machine-readable twin at `core/video_gap_168.csv`.

| # | id | title | equipmentId | muscles | frames | imageUrls |
|---|---|---|---|---|---|---|
| 1 | `3_4_sit_up` | 3/4 Sit-Up | (none - bodyweight) | core | Y | - |
| 2 | `90_90_hamstring` | 90/90 Hamstring | (none - bodyweight) | hamstrings, calves | Y | - |
| 3 | `air_bike` | Air Bike | (none - bodyweight) | core | Y | - |
| 4 | `all_fours_quad_stretch` | All Fours Quad Stretch | (none - bodyweight) | quads | Y | - |
| 5 | `alternate_heel_touchers` | Alternate Heel Touchers | (none - bodyweight) | core | Y | - |
| 6 | `fedb_bent-knee_hip_raise` | Bent-Knee Hip Raise | (none - bodyweight) | core | - | Y |
| 7 | `fedb_body_tricep_press` | Body Tricep Press | (none - bodyweight) | triceps | - | Y |
| 8 | `fedb_body-up` | Body-Up | (none - bodyweight) | triceps, core, forearms | - | Y |
| 9 | `bodyweight_mid_row` | Bodyweight Mid Row | (none - bodyweight) | back, biceps, lats | Y | - |
| 10 | `bodyweight_walking_lunge` | Bodyweight Walking Lunge | (none - bodyweight) | quads, calves, glutes, hamstrings | Y | - |
| 11 | `fedb_bottoms_up` | Bottoms Up | (none - bodyweight) | core | - | Y |
| 12 | `fedb_butt_lift_bridge` | Butt Lift (Bridge) | (none - bodyweight) | glutes, hamstrings | - | Y |
| 13 | `advanced_kettlebell_windmill` | Advanced Kettlebell Windmill | kettlebell | core, glutes, hamstrings, shoulders | Y | - |
| 14 | `alternating_floor_press` | Alternating Floor Press | kettlebell | chest, core, shoulders, triceps | Y | - |
| 15 | `alternating_hang_clean` | Alternating Hang Clean | kettlebell | hamstrings, biceps, calves, forearms, glutes, lower_back, traps | Y | - |
| 16 | `alternating_kettlebell_press` | Alternating Kettlebell Press | kettlebell | shoulders, triceps | Y | - |
| 17 | `alternating_kettlebell_row` | Alternating Kettlebell Row | kettlebell | back, biceps, lats | Y | - |
| 18 | `alternating_renegade_row` | Alternating Renegade Row | kettlebell | back, core, biceps, chest, lats, triceps | Y | - |
| 19 | `fedb_double_kettlebell_alternating_hang_clean` | Double Kettlebell Alternating Hang Clean | kettlebell | hamstrings, biceps, calves, forearms, glutes, lower_back, quads, traps | - | Y |
| 20 | `fedb_double_kettlebell_jerk` | Double Kettlebell Jerk | kettlebell | shoulders, calves, quads, triceps | - | Y |
| 21 | `fedb_double_kettlebell_push_press` | Double Kettlebell Push Press | kettlebell | shoulders, calves, quads, triceps | - | Y |
| 22 | `fedb_double_kettlebell_snatch` | Double Kettlebell Snatch | kettlebell | shoulders, glutes, hamstrings, quads | - | Y |
| 23 | `fedb_double_kettlebell_windmill` | Double Kettlebell Windmill | kettlebell | core, glutes, hamstrings, shoulders, triceps | - | Y |
| 24 | `fedb_extended_range_one-arm_kettlebell_floor_press` | Extended Range One-Arm Kettlebell Floor Press | kettlebell | chest, shoulders, triceps | - | Y |
| 25 | `alternating_cable_shoulder_press` | Alternating Cable Shoulder Press | cable_machine | shoulders, triceps | Y | - |
| 26 | `bent_over_low_pulley_side_lateral` | Bent Over Low-Pulley Side Lateral | cable_machine | shoulders, lower_back, back, traps | Y | - |
| 27 | `bosu_ball_cable_crunch_with_side_bends` | Bosu Ball Cable Crunch With Side Bends | cable_machine | core | Y | - |
| 28 | `cable_chest_press` | Cable Chest Press | cable_machine | chest, shoulders, triceps | Y | - |
| 29 | `cable_crossover` | Cable Crossover | cable_machine | chest, shoulders | Y | - |
| 30 | `cable_deadlifts` | Cable Deadlifts | cable_machine | quads, forearms, glutes, hamstrings, lower_back | Y | - |
| 31 | `cable_hammer_curls_rope_attachment` | Cable Hammer Curls - Rope Attachment | cable_machine | biceps | Y | - |
| 32 | `fedb_low_cable_crossover` | Low Cable Crossover | cable_machine | chest, shoulders | - | Y |
| 33 | `fedb_single-arm_cable_crossover` | Single-Arm Cable Crossover | cable_machine | chest | - | Y |
| 34 | `fedb_stride_jump_crossover` | Stride Jump Crossover | cable_machine | quads, adductors, calves, hamstrings | - | Y |
| 35 | `barbell_ab_rollout` | Barbell Ab Rollout | barbell | core, lower_back, shoulders | Y | - |
| 36 | `barbell_ab_rollout_on_knees` | Barbell Ab Rollout - On Knees | barbell | core, lower_back, shoulders | Y | - |
| 37 | `barbell_curls_lying_against_an_incline` | Barbell Curls Lying Against An Incline | barbell | biceps | Y | - |
| 38 | `barbell_deadlift` | Barbell Deadlift | barbell | lower_back, calves, forearms, glutes, hamstrings, lats, back, quads, traps | Y | - |
| 39 | `fedb_barbell_glute_bridge` | Barbell Glute Bridge | barbell | glutes, calves, hamstrings | - | Y |
| 40 | `fedb_barbell_hip_thrust` | Barbell Hip Thrust | barbell | glutes, calves, hamstrings | - | Y |
| 41 | `fedb_barbell_incline_shoulder_raise` | Barbell Incline Shoulder Raise | barbell | shoulders, chest | - | Y |
| 42 | `fedb_barbell_rollout_from_bench` | Barbell Rollout from Bench | barbell | core, glutes, hamstrings, lats, shoulders | - | Y |
| 43 | `barbell_walking_lunge` | Barbell Walking Lunge | barbell | quads, calves, glutes, hamstrings | Y | - |
| 44 | `full_range_of_motion_lat_pulldown` | Full Range-Of-Motion Lat Pulldown | lat_pulldown | lats, biceps, back, shoulders | Y | - |
| 45 | `one_arm_lat_pulldown` | One Arm Lat Pulldown | lat_pulldown | lats, biceps, back | Y | - |
| 46 | `rocky_pull_ups_pulldowns` | Rocky Pull-Ups/Pulldowns | lat_pulldown | lats, biceps, back, shoulders | Y | - |
| 47 | `rope_straight_arm_pulldown` | Rope Straight-Arm Pulldown | lat_pulldown | lats | Y | - |
| 48 | `fedb_v-bar_pulldown` | V-Bar Pulldown | lat_pulldown | lats, biceps, back, shoulders | - | Y |
| 49 | `fedb_wide-grip_lat_pulldown` | Wide-Grip Lat Pulldown | lat_pulldown | lats, biceps, back, shoulders | - | Y |
| 50 | `fedb_wide-grip_pulldown_behind_the_neck` | Wide-Grip Pulldown Behind The Neck | lat_pulldown | lats, biceps, back, shoulders | - | Y |
| 51 | `bench_sprint` | Bench Sprint | plyo_box | quads, calves, glutes, hamstrings | Y | - |
| 52 | `fedb_box_jump_multiple_response` | Box Jump (Multiple Response) | plyo_box | hamstrings, adductors, calves, glutes, quads | - | Y |
| 53 | `fedb_box_skip` | Box Skip | plyo_box | hamstrings, adductors, calves, glutes, quads | - | Y |
| 54 | `fedb_box_squat_with_chains` | Box Squat with Chains | plyo_box | quads, adductors, calves, glutes, hamstrings, lower_back | - | Y |
| 55 | `fedb_front_box_jump` | Front Box Jump | plyo_box | hamstrings, adductors, calves, glutes, quads | - | Y |
| 56 | `fedb_lateral_box_jump` | Lateral Box Jump | plyo_box | adductors, calves, glutes, hamstrings, quads | - | Y |
| 57 | `fedb_reverse_band_box_squat` | Reverse Band Box Squat | plyo_box | quads, adductors, calves, forearms, glutes, hamstrings, lower_back | - | Y |
| 58 | `barbell_full_squat` | Barbell Full Squat | squat_rack | quads, calves, glutes, hamstrings, lower_back | Y | - |
| 59 | `barbell_hack_squat` | Barbell Hack Squat | squat_rack | quads, calves, forearms, hamstrings | Y | - |
| 60 | `barbell_side_split_squat` | Barbell Side Split Squat | squat_rack | quads, calves, hamstrings, lower_back | Y | - |
| 61 | `barbell_squat_to_a_bench` | Barbell Squat To A Bench | squat_rack | quads, calves, glutes, hamstrings, lower_back | Y | - |
| 62 | `box_squat` | Box Squat | squat_rack | quads, adductors, calves, glutes, hamstrings, lower_back | Y | - |
| 63 | `fedb_rack_delivery` | Rack Delivery | squat_rack | shoulders, forearms, traps | - | Y |
| 64 | `fedb_rack_pulls` | Rack Pulls | squat_rack | lower_back, forearms, glutes, hamstrings, traps | - | Y |
| 65 | `alternate_hammer_curl` | Alternate Hammer Curl | dumbbell | biceps, forearms | Y | - |
| 66 | `alternating_deltoid_raise` | Alternating Deltoid Raise | dumbbell | shoulders | Y | - |
| 67 | `around_the_worlds` | Around The Worlds | dumbbell | chest, shoulders | Y | - |
| 68 | `fedb_bent_over_dumbbell_rear_delt_raise_with_head_on_bench` | Bent Over Dumbbell Rear Delt Raise With Head On Bench | dumbbell | shoulders | - | Y |
| 69 | `bent_arm_dumbbell_pullover` | Bent-Arm Dumbbell Pullover | dumbbell | chest, lats, shoulders, triceps | Y | - |
| 70 | `fedb_close-grip_push-up_off_of_a_dumbbell` | Close-Grip Push-Up off of a Dumbbell | dumbbell | triceps, core, chest, shoulders | - | Y |
| 71 | `fedb_decline_dumbbell_flyes` | Decline Dumbbell Flyes | dumbbell | chest | - | Y |
| 72 | `barbell_bench_press_medium_grip` | Barbell Bench Press - Medium Grip | bench_press | chest, shoulders, triceps | Y | - |
| 73 | `bench_press_powerlifting` | Bench Press - Powerlifting | bench_press | triceps, chest, forearms, lats, shoulders | Y | - |
| 74 | `bench_press_with_bands` | Bench Press - With Bands | bench_press | chest, shoulders, triceps | Y | - |
| 75 | `bench_press_with_chains` | Bench Press with Chains | bench_press | triceps, chest, lats, shoulders | Y | - |
| 76 | `fedb_dumbbell_bench_press_with_neutral_grip` | Dumbbell Bench Press with Neutral Grip | bench_press | chest, shoulders, triceps | - | Y |
| 77 | `fedb_hammer_grip_incline_db_bench_press` | Hammer Grip Incline DB Bench Press | bench_press | chest, shoulders, triceps | - | Y |
| 78 | `bear_crawl_sled_drags` | Bear Crawl Sled Drags | leg_press | quads, calves, glutes, hamstrings | Y | - |
| 79 | `calf_press_on_the_leg_press_machine` | Calf Press On The Leg Press Machine | leg_press | calves | Y | - |
| 80 | `narrow_stance_leg_press` | Narrow Stance Leg Press | leg_press | quads, calves, glutes, hamstrings | Y | - |
| 81 | `sled_drag_harness` | Sled Drag - Harness | leg_press | quads, calves, glutes, hamstrings | Y | - |
| 82 | `sled_overhead_backward_walk` | Sled Overhead Backward Walk | leg_press | shoulders, calves, back, quads | Y | - |
| 83 | `fedb_bench_jump` | Bench Jump | adjustable_bench | quads, calves, glutes, hamstrings | - | Y |
| 84 | `fedb_decline_close-grip_bench_to_skull_crusher` | Decline Close-Grip Bench To Skull Crusher | adjustable_bench | triceps, chest, shoulders | - | Y |
| 85 | `fedb_flat_bench_cable_flyes` | Flat Bench Cable Flyes | adjustable_bench | chest | - | Y |
| 86 | `fedb_flat_bench_leg_pull-in` | Flat Bench Leg Pull-In | adjustable_bench | core | - | Y |
| 87 | `fedb_incline_bench_pull` | Incline Bench Pull | adjustable_bench | back, lats, shoulders | - | Y |
| 88 | `fedb_incline_cable_chest_press` | Incline Cable Chest Press | chest_press_machine | chest, shoulders, triceps | - | Y |
| 89 | `fedb_leverage_chest_press` | Leverage Chest Press | chest_press_machine | chest, shoulders, triceps | - | Y |
| 90 | `fedb_leverage_decline_chest_press` | Leverage Decline Chest Press | chest_press_machine | chest, shoulders, triceps | - | Y |
| 91 | `fedb_leverage_incline_chest_press` | Leverage Incline Chest Press | chest_press_machine | chest, shoulders, triceps | - | Y |
| 92 | `fedb_standing_cable_chest_press` | Standing Cable Chest Press | chest_press_machine | chest, shoulders, triceps | - | Y |
| 93 | `fedb_backward_medicine_ball_throw` | Backward Medicine Ball Throw | medicine_ball | shoulders | - | Y |
| 94 | `fedb_medicine_ball_chest_pass` | Medicine Ball Chest Pass | medicine_ball | chest, shoulders, triceps | - | Y |
| 95 | `fedb_medicine_ball_full_twist` | Medicine Ball Full Twist | medicine_ball | core, shoulders | - | Y |
| 96 | `fedb_medicine_ball_scoop_throw` | Medicine Ball Scoop Throw | medicine_ball | shoulders, core, hamstrings, quads | - | Y |
| 97 | `fedb_one-arm_medicine_ball_slam` | One-Arm Medicine Ball Slam | medicine_ball | core, lats, shoulders | - | Y |
| 98 | `fedb_barbell_shoulder_press` | Barbell Shoulder Press | shoulder_press_machine | shoulders, chest, triceps | - | Y |
| 99 | `fedb_cable_shoulder_press` | Cable Shoulder Press | shoulder_press_machine | shoulders, triceps | - | Y |
| 100 | `fedb_dumbbell_one-arm_shoulder_press` | Dumbbell One-Arm Shoulder Press | shoulder_press_machine | shoulders, triceps | - | Y |
| 101 | `fedb_leverage_shoulder_press` | Leverage Shoulder Press | shoulder_press_machine | shoulders, triceps | - | Y |
| 102 | `fedb_machine_shoulder_military_press` | Machine Shoulder (Military) Press | shoulder_press_machine | shoulders, triceps | - | Y |
| 103 | `fedb_decline_smith_press` | Decline Smith Press | smith_machine | chest, shoulders, triceps | - | Y |
| 104 | `fedb_smith_incline_shoulder_raise` | Smith Incline Shoulder Raise | smith_machine | shoulders, chest | - | Y |
| 105 | `fedb_smith_machine_behind_the_back_shrug` | Smith Machine Behind the Back Shrug | smith_machine | traps, shoulders | - | Y |
| 106 | `fedb_smith_machine_bench_press` | Smith Machine Bench Press | smith_machine | chest, shoulders, triceps | - | Y |
| 107 | `fedb_smith_machine_bent_over_row` | Smith Machine Bent Over Row | smith_machine | back, biceps, lats, shoulders | - | Y |
| 108 | `treadmill_incline_walk` | Incline Walk | treadmill | glutes, hamstrings, quads, calves | - | - |
| 109 | `treadmill_intervals` | Run Intervals | treadmill | quads, hamstrings, glutes, calves, core | - | - |
| 110 | `treadmill_steady_run` | Steady-State Run | treadmill | quads, hamstrings, glutes, calves, core | - | - |
| 111 | `treadmill_warmup_walk` | Warm-up Walk | treadmill | quads, hamstrings, glutes, calves | - | - |
| 112 | `fedb_cable_preacher_curl` | Cable Preacher Curl | preacher_curl_bench | biceps, forearms | - | Y |
| 113 | `fedb_machine_preacher_curls` | Machine Preacher Curls | preacher_curl_bench | biceps | - | Y |
| 114 | `fedb_two-arm_dumbbell_preacher_curl` | Two-Arm Dumbbell Preacher Curl | preacher_curl_bench | biceps | - | Y |
| 115 | `fedb_zottman_preacher_curl` | Zottman Preacher Curl | preacher_curl_bench | biceps, forearms | - | Y |
| 116 | `fedb_kipping_muscle_up` | Kipping Muscle Up | pullup_bar | lats, core, biceps, forearms, back, shoulders, traps, triceps | - | Y |
| 117 | `fedb_muscle_up` | Muscle Up | pullup_bar | lats, core, biceps, forearms, back, shoulders, traps, triceps | - | Y |
| 118 | `fedb_one_arm_chin-up` | One Arm Chin-Up | pullup_bar | back, biceps, forearms, lats | - | Y |
| 119 | `fedb_pullups` | Pullups | pullup_bar | lats, biceps, back | - | Y |
| 120 | `fedb_back_flyes_-_with_bands` | Back Flyes - With Bands | resistance_bands | shoulders, back, triceps | - | Y |
| 121 | `fedb_box_squat_with_bands` | Box Squat with Bands | resistance_bands | quads, adductors, calves, glutes, hamstrings, lower_back | - | Y |
| 122 | `fedb_cross_over_-_with_bands` | Cross Over - With Bands | resistance_bands | chest, biceps, shoulders | - | Y |
| 123 | `fedb_deadlift_with_bands` | Deadlift with Bands | resistance_bands | lower_back, forearms, glutes, hamstrings, back, quads, traps | - | Y |
| 124 | `fedb_front_plate_raise` | Front Plate Raise | weight_plates | shoulders | - | Y |
| 125 | `fedb_plate_pinch` | Plate Pinch | weight_plates | forearms | - | Y |
| 126 | `fedb_plate_twist` | Plate Twist | weight_plates | core | - | Y |
| 127 | `fedb_reverse_plate_curls` | Reverse Plate Curls | weight_plates | biceps, forearms | - | Y |
| 128 | `fedb_glute_ham_raise` | Glute Ham Raise | back_extension | hamstrings, calves, glutes | - | Y |
| 129 | `fedb_hyperextensions_with_no_hyperextension_bench` | Hyperextensions With No Hyperextension Bench | back_extension | lower_back, glutes, hamstrings | - | Y |
| 130 | `fedb_weighted_ball_hyperextension` | Weighted Ball Hyperextension | back_extension | lower_back, glutes, hamstrings, back | - | Y |
| 131 | `fedb_barbell_seated_calf_raise` | Barbell Seated Calf Raise | calf_raise_machine | calves | - | Y |
| 132 | `fedb_calf_press` | Calf Press | calf_raise_machine | calves | - | Y |
| 133 | `fedb_dumbbell_seated_one-leg_calf_raise` | Dumbbell Seated One-Leg Calf Raise | calf_raise_machine | calves | - | Y |
| 134 | `leverage_high_row` | Leverage High Row | seated_row_machine | back, lats | Y | - |
| 135 | `leverage_iso_row` | Leverage Iso Row | seated_row_machine | lats, biceps, back | Y | - |
| 136 | `fedb_upright_cable_row` | Upright Cable Row | seated_row_machine | traps, shoulders | - | Y |
| 137 | `air_bike_intervals` | Air Bike Intervals | air_bike | quads, hamstrings, shoulders, core | - | - |
| 138 | `air_bike_steady` | Air Bike Steady Effort | air_bike | quads, hamstrings, shoulders | - | - |
| 139 | `fedb_close-grip_ez_bar_curl` | Close-Grip EZ Bar Curl | ez_curl_bar | biceps, forearms | - | Y |
| 140 | `fedb_decline_ez_bar_triceps_extension` | Decline EZ Bar Triceps Extension | ez_curl_bar | triceps | - | Y |
| 141 | `fedb_ab_roller` | Ab Roller | foam_roller | core, shoulders | - | Y |
| 142 | `fedb_wrist_roller` | Wrist Roller | foam_roller | forearms, shoulders | - | Y |
| 143 | `fedb_lying_machine_squat` | Lying Machine Squat | hack_squat_machine | quads, calves, glutes, hamstrings | - | Y |
| 144 | `narrow_stance_hack_squats` | Narrow Stance Hack Squats | hack_squat_machine | quads, calves, glutes, hamstrings | Y | - |
| 145 | `fedb_thigh_abductor` | Thigh Abductor | hip_abductor_adductor | adductors, glutes | - | Y |
| 146 | `fedb_thigh_adductor` | Thigh Adductor | hip_abductor_adductor | adductors, glutes, hamstrings | - | Y |
| 147 | `fedb_cable_rear_delt_fly` | Cable Rear Delt Fly | pec_deck | shoulders | - | Y |
| 148 | `fedb_reverse_machine_flyes` | Reverse Machine Flyes | pec_deck | shoulders | - | Y |
| 149 | `rowing_intervals` | Row Intervals | rowing_machine | lats, back, quads, hamstrings, glutes, core | - | - |
| 150 | `rowing_steady` | Steady Row | rowing_machine | lats, back, quads, hamstrings, glutes, core | - | - |
| 151 | `ski_erg_intervals` | Ski Erg Intervals | ski_erg | lats, triceps, core, shoulders | - | - |
| 152 | `ski_erg_steady` | Ski Erg Steady Pull | ski_erg | lats, triceps, core | - | - |
| 153 | `fedb_stairmaster` | Stairmaster | stair_climber | quads, calves, glutes, hamstrings | - | Y |
| 154 | `fedb_step_mill` | Step Mill | stair_climber | quads, calves, glutes, hamstrings | - | Y |
| 155 | `ab_crunch_machine` | Ab Crunch Machine | ab_crunch_machine | core | Y | - |
| 156 | `fedb_rope_climb` | Rope Climb | battle_ropes | lats, biceps, forearms, back, shoulders | - | Y |
| 157 | `fedb_machine_bicep_curl` | Machine Bicep Curl | bicep_curl_machine | biceps | - | Y |
| 158 | `fedb_hanging_pike` | Hanging Pike | captains_chair | core | - | Y |
| 159 | `fedb_knee_hip_raise_on_parallel_bars` | Knee/Hip Raise On Parallel Bars | dip_station | core | - | Y |
| 160 | `fedb_elliptical_trainer` | Elliptical Trainer | elliptical | quads, calves, glutes, hamstrings | - | Y |
| 161 | `fedb_bicycling_stationary` | Bicycling, Stationary | exercise_bike | quads, calves, glutes, hamstrings | - | Y |
| 162 | `fedb_glute_kickback` | Glute Kickback | glute_kickback_machine | glutes, hamstrings | - | Y |
| 163 | `fedb_seated_band_hamstring_curl` | Seated Band Hamstring Curl | leg_curl | hamstrings | - | Y |
| 164 | `fedb_single-leg_leg_extension` | Single-Leg Leg Extension | leg_extension | quads | - | Y |
| 165 | `fedb_heavy_bag_thrust` | Heavy Bag Thrust | punching_bag | chest, core, shoulders, triceps | - | Y |
| 166 | `fedb_recumbent_bike` | Recumbent Bike | recumbent_bike | quads, calves, glutes, hamstrings | - | Y |
| 167 | `fedb_t-bar_row_with_handle` | T-Bar Row with Handle | t_bar_row | back, biceps, lats | - | Y |
| 168 | `fedb_dip_machine` | Dip Machine | tricep_extension_machine | triceps, chest, shoulders | - | Y |

---

## B. @WorkoutAnimation99

**Verdict: not usable. Two independent reasons, either of which is disqualifying on its own.**

### The channel, by the numbers

All figures below come from YouTube's own `aboutChannelViewModel` JSON, fetched 2026-08-01 from `https://www.youtube.com/@WorkoutAnimation99/about`:

| Field | Value (verbatim from the JSON) |
|---|---|
| Channel name | `"Workout Animation"` |
| Channel ID | `UCYE687iEeF_ONEcmh-vFkag` |
| Video count | `"videoCountText":"168 videos"` |
| Subscribers | `"subscriberCountText":"1.22K subscribers"` |
| Total views | `"viewCountText":"113,270 views"` |
| Created | `"Joined May 15, 2023"` |
| Country | `"country":"India"` |
| External links | **one** — `youtube.com/channel/UCYE687iEeF_ONEcmh-vFkag` (a self-link) |

> **Coincidence warning.** The channel has 168 videos and the catalog has a 168-row gap. **These two numbers are unrelated.** I am flagging it because the coincidence is startling and easy to misread as a match.

**The channel is dormant.** Its RSS feed (`https://www.youtube.com/feeds/videos.xml?channel_id=UCYE687iEeF_ONEcmh-vFkag`) lists 15 entries; the most recent `<published>` is **2023-12-22**. Last upload ~2.5 years ago. Nothing new is coming.

### Reason 1 — wrong content shape (this alone kills it)

I sampled **30 video titles** (15 from the RSS feed, 30 unique from the `/videos` tab HTML). Every one is a **muscle-group compilation reel**, not a single-exercise demo:

```
Best Effective  Chest Workouts #workout_animation
Gym Ball Abs Workouts #workout_animation
Worm  Up  Before   Shoulder  Workouts #workout_animation
4 Types Of Leg Curl Workouts #workout_animation
Triceps Biceps Push pull Workouts #workout_animation
Home Workouts With 2 Dumbell #workout_animation
Cardio Workout At Home #workout_animation
Increase  Shoulder And  Arms Power Exercises #workout_animation
5 Best Shoulder Exercises |3D Shoulder Workout #workout_animation
Big Back  Exercises At Gym #workout_animation
Increase  Man Power Natural Testosterone Boost Exercises #workout_animation
5 Effective Triceps Exercises #workout_animation
5 Best Exercise  For Reduce Belly Fat #workout_animation
Top 5 Quad Muscle  Workouts At Gym|Legs Workout #legsday #workout_animation
Biceps  Length Increase Workouts #workout_animation
Arm Blaster  Vs Normal  Curl  Benifits #workout_animation
Strong  Back  Workouts  or prevent Your Lower Back #workout_animation
Chest Workouts At Home(No Equipment) Home Chest  Workouts |Home Triceps Workouts
Best  3D Shoulder   And Traps  Workouts At Gym  #workout_animation
One Exercise  increase  More Muscles #workout_animation
Shoulder  And Triceps  Workouts #workout_animation
Lats   And  Fore Arms Workouts #workout_animation
Chest Biceps and Abs Workouts  #workout_animation
Thighs  And Calf Workouts #workout_animation
Men And Women Love Handles  Workouts At Home Or Gym #workout_animation
Straight  Bar /Ez Bar Biceps Workouts #workout_animation
Big  Lats   Workouts #workout_animation
Best Legs Workouts At Gym #workout_animation
Beginner Abs Workout  At Home #workout_animation
Upper Traps Workouts |Wide Shoulder  Workouts  #workout_animation
```

### How many of the 168 could this channel cover?

**Confident direct matches: 0 of 168.**

**How I matched:** I compared each of the 30 sampled titles against the 168 gap titles looking for a title that names one specific exercise. Not one does. Every title names a *muscle group plus a count* ("5 Best Shoulder Exercises") or a *theme* ("Cardio Workout At Home"). The catalog needs a clip for `fedb_leverage_incline_chest_press` — a specific machine at a specific angle. No compilation title in this channel resolves to that.

**What I am guessing vs. confident about:**
- **Confident:** 0 videos on this channel are per-exercise demo clips of the kind `exercises.json` expects. This follows from the title format, which I sampled at 30/168 (18%).
- **Guessing, and unverifiable without watching all 168 videos:** some of the 168 gap movements certainly *appear* as segments inside these compilations. A "5 Best Shoulder Exercises" reel plausibly contains a shoulder press. Themewise the channel does overlap the gap's biggest muscle buckets (chest 24, shoulders 23, quads 31, core 19, lats 16).
- **But that overlap is not usable**, because obtaining a per-exercise asset would require *cutting a segment out of a compilation* — creating a derivative work of material you have no licence to. That is a bigger legal problem than copying, not a smaller one.

I did **not** attempt a numeric coverage range, because any number I produced would be an estimate of "how many movements appear somewhere inside 168 videos I did not watch." Stating that as a figure would be false precision. **Could not verify — and the licence question below makes it moot.**

### Reason 2 — licence: nothing stated

This is the load-bearing finding, so it is stated precisely.

**The channel's full About description, verbatim** (from the `aboutChannelViewModel.description` field):

> "Workout Animation Video Regular physical activity can improve your muscle strength and boost your endurance Exercise delivers oxygen and nutrients to your tissues and helps your cardiovascular system work more efficiently. And when your heart and lung health improve, you have more energy to tackle daily chores
>
> Do Subscribe
> Share ,Comment, N like This Video"

**That is the entire text.** There is no licence statement, no usage terms, no attribution request, no contact email, no "free to use" claim, and no "do not reuse" warning. **Nothing is stated.** I am not inferring permission from that silence — silence means the default applies, and the default is all rights reserved.

**No alternative download route exists.** The About panel's `links` array contains exactly **one** entry, and it points back at the channel's own YouTube URL. There is no website, no Gumroad, no Patreon, no store, no Ko-fi. If the channel sold or gave away downloads through another route, that route would be the relevant one to pursue — **it does not exist.**

**Not Creative Commons.** I fetched three individual watch pages (`2E1eBeo33-0`, `xSx23Td3bXY`, `dgneQx50Z-o`) and searched each for the strings `Creative Commons`, `creativeCommon`, and `CREATIVE_COMMONS`. **Zero hits on all three.** (The 108 `licen` substring hits per page are all player configuration flags such as `html5_drm_cpi_license_key` — not the video's licence metadata.) The videos carry YouTube's default Standard License. Each video's description is a one-line copy of its own title, containing no terms.

### And downloading would breach YouTube's Terms regardless

Even if the channel owner said yes in a comment, the download itself is a separate breach. From **https://www.youtube.com/t/terms**, under "Permissions and Restrictions", you are not allowed to:

> "access, reproduce, download, distribute, transmit, broadcast, display, sell, license, alter, modify or otherwise use any part of the Service or any Content except: (a) as specifically permitted by the Service; (b) with prior written permission from YouTube and, if applicable, the respective rights holders; or (c) as permitted by applicable law;"

And immediately above it:

> "You may view or listen to Content for your personal, non-commercial use."

Note the structure: clause (b) requires permission from **YouTube *and*** the rights holder. Channel-owner permission alone does not unlock the download; it only removes one of two barriers. The clean route, if the operator wants this content, is to get the **source files from the creator directly, outside YouTube** — see the [draft message](#draft-question-to-send-workoutanimation99).

**Embedding is the one thing that is allowed** — "You may also show YouTube videos through the embeddable YouTube player." But an embedded player in a fitness app means ads, YouTube branding, network dependency, no offline mode, and no control over the video being deleted. That is a poor fit for a per-exercise demo loop, and it does not match the existing `video.girl` / `video.men` MP4 architecture at all.

---

## C. Ready-made full workout videos

Research on this section was run as a separate parallel investigation. Findings below; sources cited inline.

### The two walls

Most evaluations of free video sources notice only the first of these:

1. **Licence wall** — nearly every general stock licence bans *standalone distribution* of the file. Serving a video to an app user for playback **is** standalone distribution.
2. **Content wall** — even where the licence is permissive, **full-length guided workouts do not exist on general stock sites.** Pexels' own duration filter tops out at "2m+" (https://www.pexels.com/search/videos/workout/, 13.7K results). That content is b-roll of people exercising, not 10–45 minute guided sessions.

### Free / stock sources

| Source | Licence verdict | The clause that decides it |
|---|---|---|
| **Pexels** (https://www.pexels.com/license/) | **Licence OK, content wrong** | Allowed list explicitly names use *"on your website, blog or app"*. The "not allowed" list is: *"Identifiable people may not appear in a bad light..."*, *"Don't sell unaltered copies of a photo or video, e.g. as a poster, print or on a physical product..."*, *"Don't imply endorsement..."*, *"Don't redistribute or sell the photos and videos on other stock photo or wallpaper platforms."*, *"Don't use the photos or videos as part of your trade-mark..."*. **Notably absent: any "standalone file" ban and any "primary feature" ban.** The redistribution ban is scoped to *other stock platforms*; a fitness app is not one. Genuinely usable — but only short b-roll exists. |
| **Pixabay** | **COULD NOT VERIFY** | Six fetch attempts (`/service/license-summary/`, `/service/terms/`, `/service/faq/`, `/service/license/`, the `/de/` variant, the `#license` anchor) all returned HTTP 403 Cloudflare challenges via WebFetch, curl, and urllib with a browser UA. Search-engine extracts consistently surface a clause prohibiting distribution *on a standalone basis* where no creative effort has been applied — **but this was NOT verified against the live page and must not be relied on in either direction.** If that wording is current it is fatal here. **Operator must read the live page in a browser before using Pixabay.** |
| **Mixkit** (https://mixkit.co/terms/, §9) | **NOT SAFE** | Prohibits *"rent, license, sublicense, sell, resell or otherwise commercially exploit or make Mixkit or any Item available to any third party"*. "Make any Item available to any third party" is broad enough to cover serving the clip to your users. |
| **Coverr** (https://coverr.co/license) | **Ambiguous → treat as negative** | Grants *"an irrevocable, non-exclusive, worldwide copyright license to download, copy, modify, perform, and use videos and music"* but prohibits offering them *"as part of services to which providing videos can help"*, naming **mobile app builders** among the examples, and bans compiling to *"create a similar or competing service."* A workout-video app is arguably such a service. |
| **Videvo** | **Comparatively favourable, needs direct verification** | help.videvo.net returned 403; wording surfaced via search from https://help.videvo.net/article/27-license-types-and-usage: publish *"worldwide and on any platform, including web, broadcast, shows, theatre, apps, and games"*, may not *"redistribute the clip(s) in their original form (e.g. making the clip available as a stock clip for download on another website)"*. Apps named as permitted; redistribution ban scoped to stock-for-download. **Verify directly before relying on it.** |
| **Vecteezy** (https://www.vecteezy.com/licensing-agreement) | **NOT USABLE** | Verified verbatim: *"You may not publicly display, sell, license, or otherwise distribute the Content (or modified Content) as a standalone file."* and *"You may not allow the end user of your End Products to extract the Content and use it separately from the End Products."* The standalone-file ban kills it. |

### Creative Commons YouTube channels

**No channel found.** Multiple searches did not identify a single named YouTube channel publishing full workout videos under CC-BY. Stating that plainly rather than estimating: **not found.**

Two traps worth recording even if such a channel turns up later:

- **The CC mark does not clear the soundtrack.** An uploader can mark a video CC-BY while using music they do not own. Workout videos almost always have music. YouTube offers only CC BY (https://support.google.com/youtube/answer/2797468).
- **The ToS still blocks the download channel.** The CC licence is granted by the uploader over *the work*; YouTube's ToS separately governs *access to the Service*. CC-BY content obtained **directly from the creator** would be fine; scraping it off YouTube would not.

### Public domain / archive

- **archive.org**, `subject:"PHYSICAL FITNESS" AND mediatype:movies` → **174 items**. One genuine public-domain full-length hit: *U.S. Army training film "Physical Fitness"* (1967), identifier `TF73856PhysicalFitness1967`, `licenseurl = creativecommons.org/publicdomain/mark/1.0/`, MPEG4 **320×240**, **1754 s (~29 min)**. Genuinely PD, genuinely a full session — and **unusable** at QVGA resolution in a 2026 mobile app.
- **CRITICAL TRAP:** archive.org licence tags are uploader-applied and unreliable. A query for PD-marked fitness films returned 181 items including *"Playboy's Naked Workout"*, *"Insanity Insane Cardio Full Workout"* (a Beachbody commercial product), a *Sid The Science Kid* PBS promo, and commercial DVD rips of THE FIRM and TAEBO II — all plainly copyrighted, all falsely tagged public domain. **Never treat an archive.org `licenseurl` as authoritative.**
- **DVIDS** (https://www.dvidshub.net/about/copyright) — genuinely PD: *"In general, DoW VI that are works of authorship prepared by U.S. Government employees as part of their official duties are not eligible for copyright protection in the United States."* Commercial use allowed with a non-endorsement disclaimer. Content is military PT b-roll, not guided consumer workouts.
- **NIH / NIA (Go4Life)** — killed by their own policy. From https://www.nia.nih.gov/about/policies: text is public domain, **but** *"Photos and illustrations used in NIA materials are a mix of copyrighted and copyright-free materials. ... NIA-produced videos may also contain a mix of copyrighted and copyright-free material. For information about the use of specific graphics and videos, please contact us."* **Go4Life videos are NOT cleanly public domain.**

### B2B fitness-content licensors — the category that actually works

This is where licences *do* expressly bless paid-app embedding.

| Provider | Content | Price (published) | Licence |
|---|---|---|---|
| **Fitscope** (https://www.fitscope.com/b2b/licensing) | *"thousands of high quality classes"* — cycling, treadmill, rowing, yoga, Pilates, bodyweight. **Genuine full-length sessions.** | **$30/mo per video** (6-mo term), **$20** (12-mo), **$15** (24–36 mo); *"min volumes apply"* | Permits *"Monetize through your web, app, social or in-club screens."* |
| **iBodyFit** (https://www.ibodyfit.com/licensing-sales.php) | *"over 500 videos ... from 5 to 60 minutes"* — genuine full-length workouts, plus calendar plans | Contact only; *"short-term and long-term leasing, as well as exclusive sales"* | Not published |
| **YMove** (https://ymove.app/exercise-video-library) | *"970+ white-label HD exercise demonstration videos"*, 720p — **per-exercise demos**, not sessions | Free tier: 25 videos, *"Commercial use allowed"*; API from **$19/mo**; full library on contact | *"White-label ready"*; full terms not published |
| **Hyperhuman** (https://hyperhuman.cc/content-api) | Both *"individual exercise clips"* and *"Fully produced videos ready for immediate use"*. Partners with **Les Mills** | Not published | Not public; Les Mills Signature Classes usable *"through app, web, embeds, and API"* for eligible paid teams; rights/pricing/territory vary |
| **Fitter Stock** (https://fitterstock.com/) | B2B health/fitness content | **Could not verify** — pages returned no substantive content | Could not verify |
| Wellbeats / Grokker | Corporate-wellness platforms selling to **employers**, not app developers | — | No developer licensing offering found |

### My verdict on "full workouts instead of per-exercise clips"

**No — with one narrow, real exception.**

The app's data model is per-exercise. `exercises.json` is a flat list of 511 rows; each row carries `title`, `steps`, `muscles`, `contraindications`, `frames`, and a `video` map keyed by gender. The UI opens a detail page per row and plays that row's demo. **A 30-minute guided workout has nowhere to go in that structure.** You cannot attach one session video to 20 catalog rows and call the gap closed — the user tapping "Zottman Preacher Curl" needs to see a Zottman preacher curl, not minute 14 of a full-body session.

Substituting full workouts would be a **product change, not a content change**: a new "Sessions"/"Classes" content type, its own model, its own list and player screens, its own progress tracking, and its own place in the navigation. That is a feature, and it may well be a good one — Fitscope and iBodyFit exist precisely to supply it. But it is orthogonal to the 168-row gap and does not close it.

**The exception is real and worth taking:** the **15 cardio-machine rows** (of which the 10 zero-asset rows are a subset) are *already* session prescriptions, not movements. `treadmill_intervals` ("Run Intervals") and `rowing_steady` ("Steady Row") are the one place in this catalog where a longer video is the *correct* asset rather than a compromise. And because those 15 rows map to only **8 distinct machines**, eight short generic machine loops — Pexels has usable b-roll of exactly this, under a licence with no standalone-file ban — would cover all 15. That is the cheapest legitimate win available anywhere in this report.

---

## D. The exerciseanimatic paid pack

**Verdict: this is the one source whose licence provably permits what the app needs.**

Product page: https://www.exerciseanimatic.com/product-page/complete-2000-exercise-videos-lifetime-unlimited-license-workout-yoga-animation-exercise-fitness-gym
Licence page: https://www.exerciseanimatic.com/license
Vendor: N.C.A. Health & Wellness LTD (Cyprus — business coordinates in the page metadata), contact `contact@exerciseanimatic.shop`

### Price — cheaper than the operator expected

From the product page's own Wix store JSON, fetched 2026-08-01:

```
"price":599, "formattedPrice":"$599.00",
"itemDiscount":{"discountRuleName":"SUMMER SALES AUGUST",
                "priceAfterDiscount":"$329.00"}
```

**List $599.00; current price $329.00** under an automatic discount named "SUMMER SALES AUGUST". The operator's brief said $359 — **the live page today says $329**. The discount is rule-based and dated-sounding, so it may move; re-check at purchase time.

### "2000 videos" — what that number actually means

The number drifts across the vendor's own surfaces. All four figures below are from the vendor:

| Claim | Value | Source |
|---|---|---|
| Product URL slug | "complete-**2000**-exercise-videos" | the page URL |
| Product description | *"Get **2500+** Exercise and Workout Animation Videos"* | product description |
| Shop catalogue | `"totalCount":2635` | https://www.exerciseanimatic.com/animated-fitness-videos-exercise-shop store JSON |
| FAQ gender split | *"**750+** Female exercises"* / *"**1700+** Male exercises"* | product-page FAQ, with filter URLs `...exercise-shop?Gender=Female` and `?Gender=Male` |

**So: it is NOT 2000 unique exercises.** Male and female are separate SKUs. Confirmed by the shop's own naming convention — the store JSON shows paired products `ankle-pumps` / `ankle-pumps-female`, `alternating-toe-tap-1` / `alternating-toe-tap-female`, `alternating-plank-lunge-1` / `alternating-plank-lunge-female`.

**Best reading: roughly 1,700–1,900 unique exercises, of which ~750 also have a female variant.** The vendor confirms the asymmetry explicitly:

> "Exercise Animatic started with a male character model as the base animation framework during the early development stages of the project. As the library expanded rapidly, the male collection naturally grew first. However, expanding the female character library is a major ongoing priority."

**This matters directly for this app.** `exercises.json` uses a `{girl, men}` video map and 310 of the 343 existing entries populate **both**. A library that is 1700 male / 750 female cannot fill both keys for every one of the 168. Expect to fill `men` for nearly all of them and `girl` for perhaps 40–45% — **which mirrors the shortfall the catalog already has** (28 entries are girl-only, 5 men-only). Verify per-exercise before assuming both genders.

### What is included

From the product description, verbatim:

> "✅🚀 Get 2500+ Exercise and Workout Animation Videos In Ultra HD 4K, FULL HD 1080p, HD 720p & 📱 Vertical Formats with MUSCLE-MAPPED, PRECISE DEMONSTRATIONS!
> ✅🎨 4500+ Professional Illustrations with Start-Finish of All Exercise Videos ...
> ✅📖 1500 Easy to Understand Step by Step Exercise Instructions ...
> ✅🎬 BONUS 1200+ Green Screen Videos ..."

Technical spec, verbatim:

> "Video Info (Without logo): 4K Ultra HD 3840X2160 Mp4 h.264 codec ... 60fps 16:9 ratio Each MP4 video is about 5-30 seconds loop
> Video Info (With and without logo): FULL HD 1920X1080 & 1080X1920 for the vertical version ... 30fps 16:9 ratio & 9:16 for the vertical version"

**H.264 MP4, 5–30 s loops** — a drop-in match for the existing `storage.googleapis.com/.../*.mp4` architecture. No transcoding pipeline needed.

Coverage claims relevant to the gap: *"Of which 600+ exercises are home exercises without equipment"*, and equipment types listed as *"Bodyweight, Calisthenics, Dumbbells, Barbell, Kettlebell, Yoga, Resistance Band, Gym Equipment"* — kettlebell and gym equipment are named, which are the gap's two worst-hit categories.

**Delivery caveat, verbatim from the FAQ:**

> "You will receive your videos via our business Dropbox."
> "Please make sure to download your bundle content within 30 days and keep a backup on your personal computer and your cloud drives. After that period the files will be erased."

**Act on this immediately after purchase.** The 30-day window is a hard deadline, and "lifetime licence" does not mean lifetime hosting.

### The licence — quoted in full, because this is the decisive part

From https://www.exerciseanimatic.com/license — "Lifetime Non-Exclusive Business 2 Business License (N-EB2BL)":

> "The N-EB2BL is included with every individually purchased video and applies to all Exercise Animatic content included in your purchased bundle.
> It allows you to use Exercise Animatic content in commercial B2B and B2C projects, including apps, websites, subscription platforms, online courses, social media, marketing and fitness software."

**What you can do** (verbatim list):

> - "Use purchased Exercise Animatic content in commercial iOS and Android apps, including free, paid and subscription-based fitness applications."
> - "Use the content in websites, online platforms, fitness software, membership programmes and other B2B or B2C digital products and services."
> - "Include the content in online courses, coaching programmes, rehabilitation platforms, corporate wellness systems and educational projects."
> - "Use the content in YouTube videos, social media posts, advertisements, promotional videos, e-books, presentations and other marketing materials."
> - "Monetise products, platforms and services that incorporate Exercise Animatic content."
> - "Add your logo, replace green-screen backgrounds, resize, crop, compress, transcode and adapt the content to match your brand and technical requirements."

**Clear not-to-do list** (verbatim):

> - "Sell, share or distribute Exercise Animatic videos, illustrations or other content as standalone products or downloadable files."
> - "Create a competing exercise library, stock-content website, marketplace or service whose primary purpose is to provide access to Exercise Animatic content."
> - "Share or provide access to the raw files outside your business or authorised project team."
> - "Grant sublicences, reseller rights, franchise rights or redistribution rights to another person or business."
> - "Upload, distribute or sell Exercise Animatic content through stock-media websites or digital asset marketplaces."
> - "Use the content to create NFTs, blockchain-based digital collectibles or similar crypto products."
> - "Use the content in television, cinema or other broadcast productions without prior written approval from Exercise Animatic."
> - "Upload or supply Exercise Animatic content to an Artificial Intelligence platform for training, fine-tuning, dataset creation or generating new AI content."

**Reading this against the Fitness App specifically:**

| App behaviour | Permitted? | Clause |
|---|---|---|
| Serve MP4s to app users from the GCS bucket | **Yes** | *"commercial iOS and Android apps, including free, paid and subscription-based"* |
| Charge a subscription for the app | **Yes** | *"Monetise products, platforms and services that incorporate Exercise Animatic content"* |
| Transcode / resize for mobile bandwidth | **Yes** | *"resize, crop, compress, transcode and adapt"* |
| Ship an offline/download-for-later feature | **Needs care** | *"Sell, share or distribute ... as standalone products or downloadable files"* — an in-app cache for playback reads as in-app use; a feature that hands the user a reusable MP4 file reads as distributing a downloadable file. **Ask the vendor in writing before building this.** |
| Publish the catalog as a public API / dataset | **No** | *"Create a competing exercise library ... whose primary purpose is to provide access to Exercise Animatic content"* |
| Feed clips to an AI pose/form-check model | **No** | *"Upload or supply ... to an Artificial Intelligence platform for training, fine-tuning, dataset creation"* |

> **The AI clause is a live conflict.** Per `core/BACKLOG_2026-07-31.md`, this app has a live form-check epic. Training or fine-tuning any model on these clips is expressly prohibited. Running a *pre-trained* pose model against the user's own camera feed is untouched by this clause — but do not use the licensed clips as training or reference data. **Confirm with the vendor before any work in that epic touches this footage.**

### Does it cover the 168?

**Likely most of it, but I could not verify per-exercise, and I will not present an estimate as a count.**

What supports "likely most":
- ~1,700+ unique male exercises against a 168-row gap made of standard, canonical exercise names (Barbell Deadlift, Cable Crossover, Pullups, Wide-Grip Lat Pulldown, Glute Ham Raise, Rack Pulls).
- The vendor names kettlebell and gym equipment explicitly — the gap's two worst categories.
- The `fedb_` rows come from free-exercise-db, a standard open dataset whose naming conventions are industry-common.

What I attempted and why it failed: I probed the shop by slugifying gap titles into `product-page/<slug>` URLs. **The method is not sound and I am reporting it as inconclusive, not as a result.** Two reasons: (1) Wix returns HTTP 503 rather than 404 for a non-existent product, so a miss is indistinguishable from throttling; (2) real slugs carry suffixes (`alternating-toe-tap-**1**`) and vendor naming differs from catalog naming, so a guessed slug missing proves nothing about the catalog.

What I actually ran, for the record: a first batch of **24** sampled gap titles → 23× HTTP 503, 1× timeout, **0 hits**. A second batch of **8** deliberately canonical names (`barbell-deadlift`, `cable-crossover`, `pullups`, `box-squat`, `muscle-up`, `glute-ham-raise`, `rack-pulls`, `wide-grip-lat-pulldown`) with 3 retries and 8–16 s backoff → 6× 503, 2× timeout, **0 hits**. Control probes of two slugs known to exist from the shop JSON returned 200 (`pull-sled-or-dog-sled-push`, `ankle-pumps`), confirming the fetch mechanism works.

**I am still calling this inconclusive rather than negative**, and deliberately so: the controls were run in a separate, less-loaded pass, two probes in the second batch timed out outright (the host was degrading under my requests), and the slug-format problem is unresolved. A tempting but wrong reading of "0/32 hits" is "the bundle does not cover these exercises" — that inference is not available from this data. I also could not enumerate the catalogue definitively: `https://www.exerciseanimatic.com/sitemap.xml` is advertised in `robots.txt` but returned 503 on every attempt. **This is exactly why the 10-name manual shop search below is the step that matters — it uses the vendor's own search instead of guessing URLs.**

**Known gaps in coverage, from the content model rather than from probing:**
- The **15 cardio rows** will not be covered as such. An animation library has "Rowing Machine"; it does not have "Row Intervals", because that is a prescription, not a movement.
- **Female variants** will be missing for roughly half, per the vendor's own 1700/750 split.

**How the operator should verify before paying:** the vendor publishes a free-samples page (https://www.exerciseanimatic.com/free-samples) and a searchable shop with per-exercise $1 SKUs. Take 10 hard names from `core/video_gap_168.csv` — the machine-specific ones are the real test, e.g. *Leverage Decline Chest Press*, *Zottman Preacher Curl*, *Smith Machine Behind the Back Shrug*, *Wide-Grip Pulldown Behind The Neck*, *Glute Ham Raise*, *Thigh Abductor*, *Rack Delivery*, *Plate Pinch*, *Bosu Ball Cable Crunch With Side Bends*, *Double Kettlebell Windmill* — and search the shop for each. Ten minutes of searching converts "likely most" into a number.

---

## Comparison table

| | **@WorkoutAnimation99** | **Full workouts (stock/CC/PD)** | **Full workouts (B2B licensors)** | **exerciseanimatic bundle** |
|---|---|---|---|---|
| Cost | Free | Free | Fitscope $15–30/mo **per video**; iBodyFit on contact | **$329** now (list $599), one-off |
| Volume | 168 videos | Pexels 13.7K workout clips; archive.org 174 PD fitness films | Fitscope *"thousands"*; iBodyFit *"over 500"* | ~1,700–1,900 unique exercises (2,635 SKUs) |
| Asset shape | Muscle-group **compilation reels** | Short b-roll (Pexels caps at "2m+") or 29-min 320×240 PD film | Full guided sessions, 5–60 min | **Per-exercise 5–30 s loops** |
| Fits `exercises.json` per-exercise model | **No** | **No** (except 15 cardio rows) | **No** — needs a new content type | **Yes, exactly** |
| Quality | Unverified (not viewed) | Pexels good; archive.org PD hit is 320×240 | Professional | 4K 60fps + 1080p + 9:16 vertical, H.264 MP4 |
| Male + female variants | No | No | No | Yes — but 1700 male / 750 female |
| **Licence permits paid-app use** | **Nothing stated** | Pexels **yes**; Vecteezy/Mixkit **no**; Pixabay **could not verify**; Coverr ambiguous | Fitscope **yes** (*"Monetize through your web, app..."*); others not published | **Yes, expressly** |
| Legal to obtain | **No** — YouTube ToS bars the download | Yes | Yes | Yes |
| Covers the 168 | **0 confirmed** | Only the 15 cardio rows | Only the 15 cardio rows | Likely most — **unverified**, see D |
| Delivery | — | Direct download | Contract | Dropbox, **30-day window** |
| **Verdict** | **Reject** | **Narrow use only** | **Different product** | **Adopt** |

---

## Recommendation

### 1. Buy the exerciseanimatic Ultimate Bundle — but verify coverage first (~10 min)

It is the only candidate whose licence contains a sentence that directly authorises this app's exact behaviour: *"Use purchased Exercise Animatic content in commercial iOS and Android apps, including free, paid and subscription-based fitness applications."* I am not inferring that from a permissive vibe; it is the text.

At **$329** for ~1,700+ unique exercises, per-exercise cost is under $0.20. Even if only half the 168 are covered, nothing else on this list competes — and the bundle simultaneously solves the much larger problem in point 3.

**Before paying:** run the 10-name shop search described at the end of section D. If 8+ of 10 hard machine names are present, buy. If fewer than 5, ask the vendor directly whether the missing ones exist before committing.

**Immediately after paying:** download everything within 30 days. *"After that period the files will be erased."*

### 2. Do not use @WorkoutAnimation99

Two independent disqualifications, either sufficient:
- **Nothing is stated.** The About text is 4 lines of generic health copy with no licence, no terms, and no contact. The one external link is a self-link. There is no store, no Patreon, no site — no alternative route to ask about or buy from. Silence is not permission.
- **Wrong shape.** 168 muscle-group compilation reels. Zero of the 30 sampled titles names a single exercise. Even with permission, extracting a per-exercise clip would mean cutting segments out of compilations — a derivative work, which is a larger rights problem, not a smaller one.

Plus: downloading breaches YouTube's ToS regardless of what the owner says, since clause (b) requires permission from **YouTube *and*** the rights holder.

If the operator wants to pursue it anyway — the animation style may be appealing — the **only** legitimate route is to contact the creator and ask for source files outside YouTube, under a written licence. Draft below. **My honest read: not worth the wait.** The channel has been dormant since December 2023, has 1.22K subscribers, and even a "yes" yields compilation reels that still do not fit the data model. Send it if you like, but do not sequence the bundle purchase behind it.

### 3. Treat this as 511 rows, not 168

**This is the most important thing in this report and it was not in the original question.**

The brief frames the task as "close the 168 gap". But per the project memory note (`reference_fitness_exercise_video_sources.md`), the **343 videos already in the bucket are unlicensed scaffolding**. Buying a licensed source for 168 while 343 unlicensed clips remain in `traidingbot-b4061-videos-eu` leaves the app **exactly as unshippable as it is today** — the exposure is per-file, and 343 unlicensed files is more exposure than 168, not less.

**The bundle's ~1,700 exercises are large enough to re-source the whole catalog.** So the correct scope is: buy once, then **re-point all 511 rows** at licensed assets and purge the old bucket contents. That converts a $329 content purchase into the thing that actually unblocks a production launch. Doing only the 168 spends the money without buying the outcome.

I flag this as **my read, not a verified legal position** — I have not audited the provenance of the 343 existing files myself; I am relying on the memory note. **Verify that provenance before launch either way.** If the 343 turn out to be properly licensed, this point drops and the scope is just the 168.

### 4. Take the cheap cardio win with Pexels

The 15 cardio rows will not be covered by any exercise-animation library, and 10 of them currently have **no visual asset at all** — the worst-looking rows in the app. They map to only 8 distinct machines. Pexels has b-roll of treadmills, rowers, and bikes, and its licence explicitly allows use *"on your website, blog or app"* with **no standalone-file clause and no primary-feature clause** — the two traps that disqualify Vecteezy and Mixkit. Eight short loops, zero cost, legally clean.

### 5. Do not pursue full-length workouts to close this gap

Not because the licences are bad — Fitscope's is fine and explicitly permits app monetisation — but because **it is a different product**. `exercises.json` is per-exercise; a 30-minute session has nowhere to live in it. Adding a "Sessions" content type may be a good future feature (Fitscope, iBodyFit and Hyperhuman all exist to supply it), but it is orthogonal to the 168 and should be evaluated on its own merits, not as gap-filling.

### 6. Open questions to resolve with the vendor before building

Send these to `contact@exerciseanimatic.shop` **before** work starts on the affected features:
- **Offline download.** Does an in-app "download this workout for offline use" feature count as distributing *"downloadable files"*? An in-app playback cache reads as in-app use; a user-accessible file export does not. Get it in writing.
- **AI / form-check.** The licence bars supplying content to an AI platform *"for training, fine-tuning, dataset creation or generating new AI content"*. Confirm that running a pre-trained pose model against the **user's own camera** — with these clips used only as on-screen reference for the human — is outside that clause. This blocks the form-check epic in `core/BACKLOG_2026-07-31.md`.

---

## Draft: question to send @WorkoutAnimation99

Send via the channel's YouTube "About → Send message" form, or as a comment on a recent video (the channel publishes no email address — verified: the About panel contains one link, a self-link).

> Subject: Licensing request — use of your exercise animations in a fitness app
>
> Hello,
>
> I'm the developer of a fitness app that shows a short demonstration clip for each exercise in its catalog. I came across your Workout Animation channel and would like to ask about licensing your animations.
>
> Three questions:
>
> 1. **Do you own the copyright** in the animations on the channel — did you create them yourself, or are they licensed from another source? If they are licensed to you, I would need to know whether your licence allows you to sub-license them onward.
>
> 2. **Would you licence the source files to me** for use in a commercial mobile app? To be specific about what I need: the right to host the video files on my own servers and stream them to users of my app, including users on a paid subscription. I would not resell the files, redistribute them as downloadable files, or make them available outside my app. I'm happy to pay, and happy to credit you in the app.
>
> 3. **Do you have the individual exercise clips** before they were edited into the compilation videos? Your published videos combine several exercises into one clip, but my app needs one short clip per exercise. If the per-exercise source animations still exist, those are what I'd want.
>
> To be clear about why I'm asking rather than just downloading: your channel doesn't state any licence, and YouTube's Terms of Service don't permit downloading videos, so I would only proceed with your explicit written permission and files supplied directly by you.
>
> If you'd rather not licence them, no problem at all — just let me know and I won't follow up.
>
> Thank you for your time.

**If the reply is anything other than a clear written yes covering all three points — including silence — the answer is no.** Do not proceed on a thumbs-up emoji, a "sure", or a comment reply. And note that question 1 is not a formality: if the channel does not own the animations (plausible for a small channel republishing 3D content), no permission it grants is worth anything.

---

## Method and verification log

Everything below was read-only. **No video file was downloaded. No downloader was run.** Files written: this report and `core/video_gap_168.csv`.

### Section A
- Parsed `D:\Repo\Fitness_App\mobile\assets\data\exercises.json` with Python; all counts are `collections.Counter` / `sum()` over the parsed list, reproducible from the file.
- CSV generated from the same parse, sorted by `(equipmentId, title)`, 168 rows + header (verified: `csv.reader` → 169 lines).

### Section B
- `https://www.youtube.com/@WorkoutAnimation99` and `/about` fetched as raw HTML via `urllib` with a browser User-Agent. WebFetch returned only footer navigation (YouTube renders client-side) — the metadata was extracted from the embedded `ytInitialData` JSON, specifically `channelMetadataRenderer` and `aboutChannelViewModel`.
- Counts (`"168 videos"`, `"1.22K subscribers"`, `"113,270 views"`, `"Joined May 15, 2023"`, `"country":"India"`) are verbatim JSON string values, not rendered text.
- Titles: 15 from `https://www.youtube.com/feeds/videos.xml?channel_id=UCYE687iEeF_ONEcmh-vFkag` (`<media:title>` elements); 30 unique from the `/videos` tab via `lockupMetadataViewModel` title fields. Last `<published>` = 2023-12-22.
- CC check: watch pages for `2E1eBeo33-0`, `xSx23Td3bXY`, `dgneQx50Z-o` fetched and searched for `Creative Commons` / `creativeCommon` / `CREATIVE_COMMONS` — 0 hits each.
- YouTube ToS quoted from `https://www.youtube.com/t/terms`, "Permissions and Restrictions" section, first restriction bullet.

### Section C
- Run as a separate parallel research investigation; sources cited inline in that section.
- **Explicitly unverified:** Pixabay's current licence text (six fetch attempts, all HTTP 403 Cloudflare); Videvo's terms (403, wording surfaced via search only); Fitter Stock (no substantive content returned); iBodyFit, YMove and Hyperhuman full licence terms (not published).
- The parallel investigation also had two of its own sub-threads (extended stock licences for Envato/Artgrid/Storyblocks/Adobe/Getty; a dedicated exercise-library survey covering gymvisual, MuscleWiki, wger, MoveKit, ExerciseDB) that had not reported at the time of writing. **Those results are not in this report and nothing here depends on them.** Worth a follow-up if the exerciseanimatic coverage check comes back weak — gymvisual.com in particular is a known direct competitor that was not assessed.

### Section D
- Product page and `https://www.exerciseanimatic.com/license` fetched as raw HTML via `urllib`; text extracted by stripping script/style blocks and tags. WebFetch returned only a DMCA badge (Wix renders client-side).
- Price from the page's embedded store JSON (`"price":599`, `"priceAfterDiscount":"$329.00"`, rule `"SUMMER SALES AUGUST"`).
- `"totalCount":2635` from the shop page's store JSON at `https://www.exerciseanimatic.com/animated-fitness-videos-exercise-shop`.
- Licence text quoted verbatim from the rendered licence page.
- **Inconclusive:** the slug-probe coverage test — 32 probes total (24 sampled + 8 canonical, the latter with retries and backoff), 0 hits, but Wix serves 503 not 404 for missing products, two probes timed out under load, and real slugs carry numeric suffixes. Reported as inconclusive, **not** as a coverage figure and **not** as a negative result.
- **Could not verify:** full product enumeration — `sitemap.xml` is advertised in `robots.txt` but returned 503 on every attempt.

### Claims I am NOT making
- Not claiming a coverage percentage for exerciseanimatic against the 168. Unverified.
- Not claiming a coverage number for @WorkoutAnimation99 beyond "0 confirmed per-exercise matches in a 30/168 title sample".
- Not claiming Pixabay is or is not usable. Could not verify.
- Not claiming the 343 existing videos are unlicensed from my own inspection — that comes from the project memory note and needs independent confirmation.
- Not offering legal advice. The licence quotes are accurate transcriptions; how they apply to this specific product is the operator's call, and the two open questions in Recommendation §6 should go to the vendor in writing.
