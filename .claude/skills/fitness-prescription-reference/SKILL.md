---
name: fitness-prescription-reference
description: Quantitative exercise-prescription reference with evidence-backed anchors separated from configurable product heuristics. Covers resistance training, e1RM/RIR, endurance intensity, progression, recovery and nutrition without treating coaching conventions as universal medical facts.
user-invocable: false
---
# Fitness-App prescription reference v2.2

This file separates three things that v2.1 mixed together:

- **EVIDENCE_ANCHOR** — supported by a current guideline/position statement or strong evidence;
- **MODEL_ESTIMATE** — useful estimate with known error/individual variation;
- **PRODUCT_HEURISTIC** — configurable coaching policy, never presented as a universal scientific rule.

Measured individual response and higher-priority safety restrictions always win.

## 1. Resistance-training anchors

### EVIDENCE_ANCHOR — healthy adults, ACSM 2026

- Regular resistance training of all major muscle groups at least twice weekly is a practical high-level target.
- Strength outcomes can be emphasized with heavier loading; ACSM's 2026 summary highlights ~80% 1RM and 2–3 sets/exercise as an effective strength-oriented prescription.
- Hypertrophy is supported by higher weekly volume; the 2026 ACSM summary highlights roughly 10 sets per muscle group/week as a useful target.
- Power can be emphasized with moderate loads (~30–70% 1RM) moved rapidly in the concentric phase.
- Training to momentary failure and complex periodization are not required for the average healthy adult to make meaningful gains.

Do not convert these population-level anchors into a guarantee for one user.

## 2. Load ↔ reps and e1RM

### MODEL_ESTIMATE

Common e1RM formulas:
- Epley: `e1RM = load * (1 + reps/30)`
- Brzycki: `e1RM = load * 36 / (37 - reps)`

Use one configured formula consistently. Prediction error grows with higher rep counts and varies by exercise/person; return a range/confidence rather than false precision.

A generic %1RM-to-repetition table is a **rough starting estimate only**, not a deterministic truth. Prefer the person's recent performance history and RIR/RPE response.

### PRODUCT_HEURISTIC — capacity freshness

Do not hard-code “2 weeks” or “8 weeks” as biological expiry dates. Mark a capacity estimate stale when one or more configured signals materially reduce transferability, for example:
- meaningful detraining gap;
- illness/injury;
- major exercise-variant change;
- repeated recent performance inconsistent with the estimate.

Thresholds belong in versioned config and should be validated from product data.

## 3. RIR/RPE

RIR is useful for autoregulation, but accuracy varies by set, exercise, proximity to failure and individual. Do **not** assume every novice overestimates RIR by a fixed `+2` for a fixed three-month period; evidence does not support that as a universal correction.

When no load history exists, use a submaximal calibration procedure and record actual reps/RIR. Example product wording: choose a load you could perform for several more reps and stop well before failure; the exact calibration protocol must be set by the goal coach and safety state.

### PRODUCT_HEURISTIC — failure policy

If the product chooses to prohibit momentary failure on selected high-skill/high-consequence lifts, encode that as a named product policy with exercise-property rules. Do not present it as an ACSM universal prohibition.

## 4. Hypertrophy volume

The v2.1 `MV/MEV/MAV/MRV` fixed numeric ranges are removed from the mandatory reference. Those labels can be useful coaching heuristics, but they are not universal physiological constants and should not act as safety/release gates.

Default approach:
- start from a conservative weekly volume appropriate to training age and current history;
- use the ACSM ~10 sets/muscle/week anchor as one reference point for healthy-adult hypertrophy programming;
- adjust from actual performance, recovery, adherence and session-time constraints;
- increase one main load dimension at a time where practical.

## 5. Progression

There is no evidence-based universal rule that every novice should add exactly `+2.5 kg lower / +1.25 kg upper`, or that two misses require exactly `-10%`.

### PRODUCT_HEURISTIC — bounded progression

A product may configure conservative bounds, but they must be explicitly versioned. Preferred progression logic:
1. user completes the prescribed rep range with technique criteria met and RIR/RPE inside target;
2. choose the smallest available equipment increment or a small relative increment;
3. hold when effort/technique exceeds target;
4. regress when repeated misses, pain/restriction, or stale-capacity signals occur.

Any `max_single_session_change_pct` is product policy, not a medical fact.

## 6. Deload / fatigue management

v2.1's fixed “any two triggers” rule and exact `40–60% volume / 90% intensity` recipe are removed as mandatory rules. Evidence does not establish one universal deload trigger or prescription.

Use trends rather than one noisy day:
- repeated performance decline;
- rising effort at a fixed workload;
- persistent sleep/recovery disruption;
- accumulating soreness/pain;
- planned competition/travel/periodization context.

A deload may reduce volume, intensity, frequency or combinations depending on goal/context. Treat the exact recipe as configurable coaching policy and test it against longitudinal outcomes.

## 7. Endurance intensity

Use `fitness-clinical-reference` first to decide whether HR-based prescription is suitable.

### MODEL_ESTIMATE

If an estimated HRmax is needed, clearly label it estimated. `208 - 0.7*age` is a commonly used population equation; individual error can be large enough to shift zone assignment.

Prefer measured thresholds/HRmax, pace, power or critical-speed/threshold data when available. When HR response is medication-affected or otherwise unreliable, prefer RPE/talk test/pace/power.

There is no single universal five-zone mapping. Store the chosen zone model and its source/version in the calculation trace.

### PRODUCT_HEURISTIC — progression

Do not enforce the “10% rule” or an ACWR `0.8–1.3` target as an injury-prevention law. ACWR may be logged as an exploratory workload metric, but it must not independently predict injury or automatically drive load changes.

Progress duration/intensity/frequency from the person's recent tolerated load and change fewer major stressors at once. Interval templates are examples, not universal defaults.

## 8. Nutrition/body composition boundary

Nutrition outputs must respect `sports-nutrition-dietitian`, RED-S/eating-disorder screening, age, pregnancy and clinical restrictions.

Useful evidence-informed adult protein targets can be offered as ranges when applicable, but v2.1's sex-specific absolute calorie floors (`1200/1500 kcal`) are **not** universal safety thresholds and are removed from the release gate.

For weight change:
- avoid aggressive universal rates;
- use a conservative, individualized target only when body-composition optimization is appropriate;
- stop deficit optimization when RED-S/disordered-eating risk is triggered;
- under 18: product policy prohibits app-generated calorie/weight-loss targets.

## 9. Time-budget arithmetic

This remains deterministic and useful:

`session_minutes = warmup + sum(sets * (work_seconds + rest_seconds))/60 + transitions`

If computed duration exceeds `constraints.minutes_per_session`, reduce scope and report what changed. Do not solve a time-budget violation by silently shortening safety-critical rest or warm-up requirements.

## 10. Rule metadata required for numbers

Any executable numeric rule must store:
- `rule_id`
- `rule_type: EVIDENCE_ANCHOR | MODEL_ESTIMATE | PRODUCT_HEURISTIC`
- `population`
- `source_id` or `policy_owner`
- `version`
- `last_reviewed`
- `confidence`
- `override_conditions`

This metadata is required so the app can distinguish “science says” from “our product conservatively chooses.”
