# Body Scan + Nutrition Coach - reference behaviour notes (clean-room distillation)

**Date:** 2026-10-15. **Branch:** `feature/body-scan-nutrition-coach`. **Status:** input to `BODY_SCAN_NUTRITION_TECH_DESIGN_2026-10-15.md` sections 3 and 29.

**Source and rule.** Distilled from the operator's two screen recordings of a third-party body-fat and fitness app (a whole-app tour and a weekly-scan session). Only behaviour, numbers, formulas and structure are recorded, in our own words. No UI copy strings, brand names, art descriptions, assets or code are carried here. Every item is tagged **[O]** observed on screen or **[I]** inferred by us. Numbers come from one test account (a 95.4 kg male profile, tested on 9 and 12 October 2026) and one short onboarding trial (70 kg default), so none of them is a validated constant. Nothing here was measured by us against our own product.

Anything the reference does that conflicts with our safety clamps (design section 13.6) is NOT adopted; the clamps always win.

## 1. Flows

### 1.1 Onboarding (about 16 questions plus an account gate) [O]
Order: main obstacle (4 choices) -> what the goal would change (4) -> sex at birth (2; used for body-fat reference ranges and, we infer, the BMR constant) -> age (stepper, default 30) -> height (cm or ft/in, default 170) -> current weight (kg or lb, default 70.0, one decimal) -> goal body fat (morphing figure with slider and reset; minimum seen 6% on the male figure) -> look direction (3 choices, skippable, explicitly "a style, never a target") -> timeline (weeks slider, adaptive-pace toggle) -> strength sessions per week (chips 0-7) -> average daily steps (slider 1k to 30k+) -> sleep (4 bands) -> eating style (8+ options, single select) -> familiarity with calorie tracking (3 levels; affects guidance verbosity only, stated to not change the plan) -> meals per day (1-5+, used to split protein) -> step source (health platform or manual checkbox) -> account gate (sign-in, placed after onboarding and before the first scan, one-sentence reason) -> first scan -> Today.
Behaviour: Continue is disabled until a choice exists (steps with defaults and the skippable look step excepted); answers survive back-navigation; a segmented progress bar advances per step. Landing screen claims about 3 minutes and private photos. [O]

### 1.2 Weekly scan [O]
Intro (same clothing, lighting, distance each week; 3 guided poses; about a minute) -> optional pre-scan sheet when the latest weight is older than today (two choices: log weight first, or scan anyway; the staleness threshold was not visible) -> camera boot -> per pose, in the order front, side, back: a status panel with three live checks (distance: too far / too close / ok; lighting: poor / ok; position: not straight / centred), on-device skeleton overlay, and when all three are green a 3-2-1 countdown then automatic capture; the user turns by themself between poses, no explicit prompt -> upload -> queued -> estimating -> result. The three poses took about 14-16 s. Failure and retry states were not observed.
Analysis page: a numbered five-step checklist (photos secured, body-composition estimate, plausibility check, trend verification, result saved), a progress bar and an elapsed m:ss counter. Observed timing: upload about 6 s, estimating about 16-18 s, counter reached 0:22 at the result, start to result about 55-60 s. The bar sat at a fixed plateau (about 30%) for the whole estimating stage. The last three checklist steps were never seen ticking at 1 s sampling, so they are cosmetic or finish in under a second. The estimate text says it reads the three poses against height, weight and the previous scan. [O]

### 1.3 Result screen [O]
Headline = TREND body fat (not the raw reading), a ring for points still to go, a change-versus-previous chip (a "no meaningful change" outcome at -0.1 pt), start and goal values, a sentence giving the raw reading with a likely range and a plain disclosure that single readings vary by about a point. Four tiles: weight trend, fat mass, lean mass (both with a "held" label for 0.1 kg moves), strength sessions this week (this tile refreshed late, showing a stale count for about a second). Chart: dots = single readings with likely ranges, line = smoothed trend, hollow point = estimate derived from weight only. Then a plan decision (hold the plan, when movement is inside noise), a next-week checklist (calorie range, protein, strength sessions, next scan 7 days later) and actions: compare photos, edit recorded weight, delete this scan's photos, done. The first scan's page is a baseline page with the same layout and a "see your plan" action. History rows show date, weight, photo availability and the TREND value with a label (baseline / steady). Compare needs two scans with photos available; the 9 October photos were already gone by 12 October, so the photo baseline restarted. [O]

### 1.4 Today tab [O]
Day strip with future days locked. A plan card with a completion ring (3 of 6 actions = 50%). Three headline numbers: calorie target (with its range underneath and the explicit sum "base + exercise"), protein minimum, steps goal. Weight card (latest, trend equals the weight itself for the first week, estimated body fat with its source scan date). Perfect-day streak card (first milestone 3 days; per-day badge x/3 or x/4, denominator varies by day). Health-source sync chip with last sync time. Action list that auto-completes: protein, calorie range, steps (with progress bar), training session (weekly target from onboarding), weekly scan (or an optional daily scan row on non-due days), log weight. A weekly-review card shows the opening date and days until the next scan. [O]

### 1.5 Nutrition tab and meal scan [O]
Remaining-calories ring with four cells (goal, food, exercise credit, left), three macro tiles with "left of goal", a log-a-meal card with five methods (photo scan, barcode, food label, describe, search), a "remix" teaser locked until the previous day has meals, and a diary by slot (breakfast, lunch, dinner, snacks) with per-slot kcal, macros and share of the day.
Photo flow: camera permission empty state (allow camera or upload) -> viewfinder with a "fit the whole meal" frame, three tip chips, gallery, shutter, manual entry -> staged analysis with elapsed seconds and a hint of 5-15 s (observed 16-20 s) -> an intermediate "estimate ready" card listing foods found and a portion-confidence figure (review or retake) -> review page: model-raised "check these" chips (3-4, e.g. portion size, cooking oil, salt, soup consistency), editable name, kcal plus a confidence pill (24% and 73% seen), macro summary, per-ingredient rows with their own confidence (75% seen), add ingredient, "fix with a note", an "what we assumed" explanation, slot selector preselected by time of day (14:07 gave lunch), time eaten, save-as-template toggle (off by default), a note that totals change only on save. Save shows a toast and the diary updates. Add-to-slot page: slot tabs, fastest method highlighted, recent and saved meals as shortcuts, a sticky bar showing slot and "0 of N kcal". [O]

### 1.6 Plan tab and profile [O]
Targets card with an ownership mode (coached / shared / manual; only the coached text was seen: the plan sets and adjusts targets weekly), calorie slider showing range and plan value, protein minimum, steps goal. "Coach" evidence panel with six inputs (weight, food, steps, training, scans, check-in). Weekly-review card with a 7-day countdown, past reviews list, per-metric toggle letting the coach adjust the steps goal, explainer rows. Pace card: goal body fat, estimated finish date, start-to-goal bar, points to go, weekly pace in kg. Profile: reminders (weekly scan Sunday 08:00; optional daily scan reminder default off; weight-log reminder default on), connected sources with sync-now, privacy (retention, deletion, export, consent), notifications (coach nudges, e.g. a lunch nudge at 13:00), help centre (scan cooldown is 7 days "so each comparison covers a real week of change"), account actions. [O]

## 2. State machines and rules

- **Scan:** intro -> [stale-weight sheet] -> camera boot -> per pose {setup checks -> all green -> 3-2-1 -> capture} -> upload -> queued -> estimating -> result. [O] Error paths unknown.
- **Meal scan:** permission -> viewfinder -> uploading -> queued -> analysing -> estimate ready -> review -> saved. [O] Stage names are four; elapsed counter ticks every 2 s in the recording.
- **Ownership:** coached = plan sets and adjusts; shared = coach proposes and user can override [I]; manual = user owns, coach never changes values [I].
- **Gating:** future days locked; compare needs 2+ scans with photos; remix needs yesterday's meals; next scan unlocks 7 days after the last; first review opens 6 days after the first scan; trend line drawn only from the second scan; share disabled until a result exists. [O]

## 3. Numbers table

| Value | Meaning | Tag |
|---|---|---|
| 3 min / 60 s | onboarding and scan length claims | O |
| 30 y / 170 cm / 70.0 kg | onboarding defaults | O |
| 6% | lowest goal body fat reachable on the male figure | O |
| 16 weeks | timeline slider maximum | O |
| 0.56 kg/wk cap at 70 kg | = 0.8% of body weight per week | O / I |
| 0.57 kg/wk plan pace at 95.4 kg | = 0.6% of body weight per week | O |
| 0-7 | strength session choices | O |
| 1k-30k+ | self-reported steps slider; bands seen: 5,000-8,000 "moderate", over 10,000 "very active" | O |
| 4 sleep bands, 1-5+ meals, 8+ eating styles | inputs | O |
| health read scopes: steps, exercise sessions, active calories, sleep; history 30 days | permission sheet | O |
| 95.4 kg, 31.0% (29.2-32.8), goal 16.0% | test account baseline | O |
| 29.6 kg fat / 65.8 kg lean / 15.0 pts to go | baseline derived | O |
| 1,760 kcal base, range 1,560-1,860 | plan = base -200 / +100 | O |
| 640 kcal exercise credit, day target 2,400, day range 2,200-2,500 | credit added on top of base | O |
| 145 g protein, 145 g carbs, 65 g fat | macro goals at 1,760 kcal | O |
| 7,000 steps | goal equal to the onboarding answer | O |
| 2 days/week training target | from onboarding | O |
| 1,840 kcal in the add-meal bar | unexplained, differs from the day target | O |
| 3 of 6 = 50% | completion ring | O |
| 3 days to first streak milestone; badge x/3 or x/4 | streak | O |
| 7 days | scan cooldown | O |
| day 6 / day 7 | first review opens / next scan due, counted from the first scan | O |
| 3-2-1 s | capture countdown | O |
| 5-15 s hint vs 16-20 s real | meal analysis | O |
| 24% / 73% / 75% | portion, meal, ingredient confidence shown | O |
| 156 kcal (3/34/0 g) and 407 kcal (4.4/53.3/19.5 g) | two meal results | O |
| 30.8% reading (29.2-32.4), trend 30.9%, delta -0.1, 14.9 pts to go | second scan | O |
| 29.5 / 65.9 / 95.4 kg | second-scan fat / lean / weight | O |
| about +-1 pt | disclosed scan-to-scan variation | O |
| 8 weeks | strength history window | O |
| Sunday 08:00; daily scan reminder off; weight reminder on; lunch nudge 13:00 | reminder defaults | O |
| 2,300 mg | faint sodium reference | I |

## 4. Formula findings (arithmetic)

1. **Composition (confirmed).** fat mass = weight x bf: 95.4 x 0.310 = 29.574 (shown 29.6); 95.4 x 0.309 = 29.479 (29.5). lean = weight - fat: 65.826 (65.8); 65.921 (65.9). points to go = trend - goal: 31.0 - 16.0 = 15.0; 30.9 - 16.0 = 14.9. Delta = new trend - old trend = -0.1.
2. **Goal weight and ETA (confirmed to the day).** goal weight = lean / (1 - goal bf) = 65.826 / 0.84 = 78.36 kg; to lose = 95.4 - 78.36 = 17.04 kg; at 0.57 kg/wk = 29.9 weeks = 209 days; 9 Oct 2026 + 210 d = 7 May 2027 (shown). Assumes lean mass constant.
3. **Pace.** 0.56 / 70 = 0.80%; 0.57 / 95.4 = 0.60%. Two different percentages, so the rule depends on something else (bf level, sleep, goal); unknown. The pace bar fill (about 88%) is relative to an unknown maximum.
4. **Trend smoothing.** Previous trend 31.0, new reading 30.8, new trend 30.9: weight on the new reading = (31.0 - 30.9) / (31.0 - 30.8) = 0.5, admissible 0.25-0.75 given rounding. One data pair, so alpha is NOT pinned.
5. **Interval.** First scan 31.0 with 29.2-32.8 (half-width 1.8); second reading 30.8 with 29.2-32.4 (half-width 1.6). Symmetric, shrinking with prior information. Rule unknown.
6. **Calories.** Base 1,760; range = base -200 / +100. Day target = base + exercise credit (1,760 + 640 = 2,400; 1,760 when no credit). "Under range" = lower bound of the day range - eaten (2,200 - 407 = 1,793). Left = day target - eaten (2,400 - 407 = 1,993). Energy search: a deficit of 0.57 x 7,700 / 7 = 627 kcal/day implies expenditure about 2,387; against Mifflin-St Jeor for 95.4 kg, 170 cm, 30 y male (954 + 1,062.5 - 150 + 5 = 1,871.5) that is a multiplier of 1.275, which matches no standard activity factor. Katch-McArdle gives 370 + 21.6 x 65.8 = 1,791. The age and height of the tested account were not visible. **The reference's base value is NOT reproduced and is not used.**
7. **Macros (pattern confirmed).** protein = 2.2 x lean = 144.8 -> 145. Fat about 1.0 g per kg lean = 65.8 -> 65 (or 33% of kcal: 64.5). Carbs = remainder: (1,760 - 580 - 592) / 4 = 147 -> 145 (5 g rounding). Atwater check 4 x 145 + 4 x 145 + 9 x 65 = 1,745 (15 under 1,760). Protein is presented as a minimum and split across the meal count [I].
8. **Meal energy.** 4.4 x 4 + 53.3 x 4 + 19.5 x 9 = 406.3 vs 407 shown. The porridge: 3 x 4 + 34 x 4 = 148 vs 156 shown (8 kcal, 5%): unseen decimals or fibre. Small mismatches are normal; large ones are the signal.
9. **Remaining counters** round to nearest: 145 - 4.4 = 140.6 -> 141.
10. **Timeline date** for a 16-week choice showed a finish 19 weeks away; not reproduced (reference defect or unknown rule).
11. **Steps goal** = onboarding average (7,000); adjusted by the weekly review when the toggle is on. [O / I]

## 5. UX ideas worth adopting (our words)

1. Trend as the headline; raw readings as dots with a plain likely range.
2. Say "no meaningful change" and hold the plan when movement is inside noise.
3. Hands-free camera assistant: three live checks, then automatic countdown capture per pose.
4. Analysis page with named stages and an elapsed timer so waiting is bounded and honest.
5. Review-before-save for AI meals: model questions as tappable chips, a short "what we assumed", per-item confidence.
6. Show the day target as an explicit sum so users see why it moves.
7. Calories as a range, protein as a minimum.
8. Auto-completing action checklist with progress inside each row.
9. A clear coached / shared / manual control.
10. Ask for health data late, read-only, manual fallback, scopes explained on the same screen.
11. Account gate immediately before the first scan with a one-sentence reason.
12. Explain the scan cooldown ("a real week of change").
13. Pre-scan sheet for stale weight.
14. Safe-pace warning with a concrete capped kg/week and an adaptive-pace option.
15. Face-blurred storage, retention control, per-scan photo deletion.
16. Slot-aware meal logging with recent and saved meals.

## 6. Observed weaknesses to avoid

- Meal-analysis time hint (5-15 s) was shorter than reality (16-20 s).
- The scan progress bar plateaued while the longest stage ran, and three listed stages were never visibly executed.
- A steps band chip did not update when the slider moved back.
- A late counter refresh showed a wrong session count for a second.
- Permission sheet asked for sleep and active calories while the on-screen copy named only steps and workouts.
- The calorie "under your range" figure was shown at 14:00, when the day was not over.
- Membership screen contradicted itself (no membership, yet active and renewing).
- The date shown for a 16-week timeline did not match 16 weeks.

## 7. Unclear items (second-look list)

1. Exact calorie formula (profile of the tested account unknown). 2. The 1,840 kcal figure. 3. The 16-week date mismatch. 4. Pace rule (0.8% vs 0.6%, effect of sleep, bf level, meaning of the pace bar). 5. Thresholds behind "no meaningful change" and "held", and the other plan-decision outcomes. 6. Shared and manual mode behaviour. 7. The weekly review page proper, past reviews, explainers. 8. Barcode, label, describe, search, saved meals, recipes, remix output, diary editing. 9. How sleep data is used. 10. Goal slider maximum, female range, timeline minimum. 11. Analysis steps 3-5 and all error/retry paths. 12. Paywall (prices, trial, structure). 13. Streak rules and denominators. 14. Notifications, widgets, units, retention options. 15. How "x of 6" relates to "y left" and whether optional rows count.
