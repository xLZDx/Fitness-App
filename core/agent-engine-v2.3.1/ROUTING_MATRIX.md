# Routing matrix v2.2

Use the smallest expert set that can resolve the case safely.

| Situation | First | Specialist | Final/extra review |
|---|---|---|---|
| Healthy beginner | orchestrator | general-fitness-coach | adversary if high impact |
| Strength/load progression | orchestrator | strength-power-coach | adversary for engine-rule changes |
| Hypertrophy | orchestrator | hypertrophy-bodybuilding-coach | nutrition/recovery as needed |
| Cardio/endurance | safety if needed | endurance-conditioning-coach | adversary if medical-adjacent |
| Running | safety if needed | running-coach | physio if pain |
| Calisthenics | orchestrator | calisthenics-bodyweight-coach | biomechanics for complex skills |
| Athletic performance | orchestrator | sport-performance-coach | strength/endurance as needed |
| Functional/HIIT | safety if needed | functional-mixed-modal-coach | biomechanics if technical/fatigued |
| Pain/injury | clinical-safety-gate | musculoskeletal-physiotherapist | adversary for product logic |
| Youth | safety gate as needed | youth-adolescent-coach | adversary for body-comp/max testing |
| Pregnancy/postpartum | clinical-safety-gate | pregnancy-postpartum-coach | adversary for new rules |
| Older/frail/falls | clinical-safety-gate | older-adult-functional-coach | chronic specialist as needed |
| Chronic condition | clinical-safety-gate | chronic-condition-exercise-specialist | evidence reviewer |
| Disability/adaptive | safety if needed | adaptive-training-coach | ontology for equipment/substitution |
| Fat loss/recomposition | orchestrator | body-recomposition-coach | dietitian + safety if RED-S/ED risk |
| Machine recognition | orchestrator | exercise-ontology-curator | biomechanics + adversary |
| Video form | orchestrator | biomechanics-technique-analyst | adversary for safety claims |
| Recovery/readiness | orchestrator | recovery-sleep-coach | domain coach |
| Massage/soft tissue | safety if symptoms | massage-soft-tissue-specialist | physio if pain/trauma |
| Motivation/adherence | orchestrator | behavior-adherence-coach | data scientist if experimentation |
| Engine implementation | orchestrator | recommendation-engine-architect | data scientist + adversary |
| New scientific rule | evidence-guideline-reviewer | affected expert | adversary |
| Symptom triage feature | orchestrator | regulatory-compliance-reviewer + clinical-safety-gate | human regulatory/clinical owner |
| Injury-risk prediction claim | orchestrator | regulatory-compliance-reviewer + biomechanics/data scientist | human regulatory owner |
| Disease-specific recommendation claim | orchestrator | regulatory-compliance-reviewer + clinical/evidence reviewer | human regulatory/clinical owner |

## Default

Routine personalized cases should normally use 1–4 specialists. More agents do not create safety by majority vote. Unresolved high-priority conflicts narrow or block the recommendation.
