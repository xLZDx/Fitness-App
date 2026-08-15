---
name: fitness-clinical-reference
description: "Evidence-aware clinical reference for exercise-safety engineering: normalized red-flag categories, medication-effect tags, pregnancy/intensity cautions, condition restrictions, and pain-triage boundaries. Use with fitness-core-policy; this is not a diagnostic protocol."
user-invocable: false
---
# Fitness-App clinical reference v2.2

`fitness-core-policy` defines decision precedence. This skill supplies concrete clinical-adjacent reference points for design/review. It does **not** authorize diagnosis or replace clinician-authored protocols.

## Governance status

- Engineering reference only until signed by the named clinical safety owner in `GOVERNANCE_OWNERSHIP.md`.
- Every executable rule must carry a source/version in the runtime rule bundle.
- Prefer normalized symptom/condition codes over free-text keyword matching.
- Separate **evidence/guideline statements** from deliberately conservative **product policy**.

## 1. S0 hard-interrupt categories

The deterministic gate should act on normalized facts such as the following. These are categories for escalation, not diagnoses.

| Normalized trigger | Product action |
|---|---|
| chest pain/pressure/tightness during exertion, especially with radiation or marked breathlessness | stop exercise content; urgent/emergency pathway per localization |
| exertional syncope/near-syncope or palpitations with dizziness | stop exercise content; urgent clinical pathway |
| sudden focal neurologic deficit: facial droop, one-sided weakness, speech difficulty, sudden major visual loss, seizure/new confusion | emergency pathway |
| saddle/groin sensory loss plus new bladder/bowel dysfunction, or rapidly progressive bilateral neurologic deficit | emergency pathway |
| unexplained unilateral calf/thigh swelling/warmth/pain, especially with sudden dyspnea/chest pain | urgent/emergency pathway; no massage/loaded exercise workaround |
| severe muscle pain/swelling after exertion with dark urine or markedly reduced urine output | urgent pathway |
| hot swollen joint with fever/systemic illness | urgent pathway |
| pregnancy warning sign such as vaginal bleeding, fluid leakage, regular painful contractions, dyspnea before exertion, chest pain, severe dizziness/headache, calf pain/swelling | stop exercise and follow obstetric urgent-contact pathway |
| heat exposure plus confusion/altered mental status | emergency pathway |
| self-harm intent or imminent safety concern | crisis/safety pathway; no training optimization in that response |

**Implementation rule:** the user-facing reply must not bury an urgent action below a workout. If input extraction is uncertain on a potentially S0 fact, ask the minimum clarifying question or escalate conservatively rather than clearing the user by inference.

## 2. S1/S2 examples requiring clearance or explicit restriction

Do not maintain a universal one-size-fits-all contraindication list in prose. Route these through condition-specific, clinician-owned rules:

- new or progressive neurologic symptoms without an S0 pattern;
- new unexplained exertional symptoms or a substantial drop in exercise tolerance;
- acute/recent major cardiovascular event or unstable cardiovascular disease;
- uncontrolled symptomatic arrhythmia or decompensated heart failure;
- acute systemic illness with fever;
- suspected/known acute DVT/PE;
- recent surgery without a current surgeon/rehab protocol;
- pregnancy with medical/obstetric complications or missing required clearance context;
- recurrent falls/dizziness in older adults;
- active eating-disorder/RED-S concern where energy-deficit optimization could worsen risk.

Numeric thresholds (for blood pressure, glucose, oxygen saturation, etc.) must come from a current clinician-approved protocol for the exact population and jurisdiction. Do not invent a universal cutoff here.

## 3. Medication normalization boundary

Never infer a medication class from `name_raw` using model memory. The expected chain is:

`name_raw -> verified medication identifier/class -> exercise_effect_tags -> product behavior`

The first mapping comes from a verified drug data source (for example RxNorm/ATC/licensed database). This skill only defines the **second** mapping semantics. The machine-readable version lives in `runtime/medication_effects.v1.json`.

### Exercise-effect tags

| Verified effect tag | Product behavior |
|---|---|
| `hr_response_blunted_or_altered` | do not use generic age-predicted target-HR zones as the sole intensity controller; prefer RPE/talk test/pace/power, or a clinician-derived individualized HR target if supplied |
| `orthostatic_or_postexercise_hypotension_risk` | use gradual transitions/cool-down; surface symptom stop rules; do not change medication timing/dose |
| `hypoglycemia_risk_with_exercise` | require the user's clinician-authored diabetes/exercise action plan when individualized glucose/insulin decisions are needed; never advise medication dose/timing/injection changes |
| `dehydration_or_electrolyte_risk` | hydration/heat caution and symptom monitoring; no medication changes |
| `bleeding_or_bruising_risk` | flag collision/fall/soft-tissue-trauma decisions for clinician/sport-specific review; a stricter product block may be configured and must be labeled product policy |
| `balance_or_alertness_impairment` | increase fall-risk caution and simplify environment/task complexity where appropriate |
| `thermoregulation_or_hr_effect` | prefer symptom/RPE-based control in heat and avoid unsupported HR assumptions |
| `myopathy_or_rhabdo_signal_relevance` | new severe muscle symptoms/dark urine trigger the urgent pathway; do not tell the user to stop a medicine |

**Unknown/unverified medication:** do not guess the class. For a recommendation that depends on medication-sensitive metrics (for example target HR), use a non-medication-sensitive fallback or return a normalization gap. A medication field does **not** automatically block unrelated routine strength advice when no symptom/condition gate is triggered.

## 4. Pregnancy intensity guidance

For uncomplicated pregnancy, exercise can be appropriate after the required obstetric/medical evaluation context is satisfied. Because heart-rate responses can be variable, **RPE and talk test are the default app intensity controls**. Do not state that HR is universally forbidden; an individualized clinician-provided target can be used if present and compatible with the product protocol.

Stop and route when pregnancy warning signs from section 1 occur. High-intensity exercise is not automatically prohibited for every pregnant user; training history, complications, current obstetric context, and specialist review matter.

## 5. Pain and musculoskeletal triage

The generic product must **not** encode a universal rule such as “pain <= 3/10 or 4/10 is always acceptable.” Numeric pain-monitoring thresholds are condition/protocol-specific.

Generic rules:
- stop the specific exercise for sharp, electric/radiating pain, rapidly escalating pain, new weakness/numbness, major trauma, or symptoms that violate a clinician restriction;
- do not diagnose tissue damage from pain location, a questionnaire, or video;
- a condition-specific rehab protocol may intentionally permit some symptoms, but that allowance must be explicit and provenance-tagged;
- substitutions must not reproduce the same restricted movement property under a different exercise name.

## 6. Soft-tissue/massage boundary

Do not recommend massage/foam rolling as a workaround for suspected DVT, acute fracture/major trauma, systemic infection/fever, open/infected wounds, or an unexplained acute swelling/mass. For anticoagulation, severe osteoporosis, recent surgery, or other elevated bleeding/tissue risk, route depth/location decisions to an appropriate clinician-authored policy instead of claiming one universal massage rule.

## 7. Heart-rate method validity

Prefer, in order:
1. measured/clinician-derived thresholds appropriate to the user;
2. activity-specific field-test thresholds when suitable;
3. estimated HR methods only when no condition/medication/pregnancy context makes them unreliable;
4. RPE/talk test/pace/power fallbacks.

Beta-blockers and other HR-altering therapies do **not** mean every possible HR target is invalid. They make generic formula-derived targets unreliable; individualized targets may still be available from clinical exercise testing.

## 8. Evidence anchors

- ACOG Committee Opinion 804: pregnancy exercise, RPE/talk-test preference and warning signs.
- American Heart Association: beta-blockers can require adjusted, individualized target HR; exercise testing may be used.
- Current ACSM/other clinician-approved pre-participation guidance for disease-specific thresholds.

Use `EVIDENCE_REGISTRY.md` for versioned links and review dates.
