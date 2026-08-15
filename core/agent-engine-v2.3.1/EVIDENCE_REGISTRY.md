# Evidence registry — v2.2 baseline

Baseline sources for engineering references. This is not a frozen source of truth. Material clinical/regulatory rules must be re-verified before release and owned by the applicable human reviewer.

## Exercise / training

1. Currier BS, et al. **ACSM Position Stand: Resistance Training Prescription for Muscle Function, Hypertrophy, and Physical Performance in Healthy Adults: An Overview of Reviews.** Med Sci Sports Exerc. 2026;58(4):851-872. DOI 10.1249/MSS.0000000000003897. https://pubmed.ncbi.nlm.nih.gov/41843416/
2. ACSM. **Updated Resistance Training Guidelines** summary, 2026-03-17. https://acsm.org/resistance-training-guidelines-update-2026/
3. WHO. **Guidelines on physical activity and sedentary behaviour.** 2020. https://www.who.int/publications/i/item/9789240015128
4. Bastos V, et al. **Feasibility and Usefulness of Repetitions-In-Reserve Scales for Selecting Exercise Intensity: A Scoping Review.** 2024. https://pubmed.ncbi.nlm.nih.gov/38563729/
5. Accuracy/reliability examples for RIR — do not turn into a fixed novice correction: https://pubmed.ncbi.nlm.nih.gov/37036795/ and https://pubmed.ncbi.nlm.nih.gov/37967832/
6. Deload practices vary substantially and are not one universal recipe: https://pubmed.ncbi.nlm.nih.gov/39446750/
7. ACWR caution/limitations: https://pubmed.ncbi.nlm.nih.gov/32502973/ ; updated association review https://pubmed.ncbi.nlm.nih.gov/41029871/

## Pregnancy / special populations

8. ACOG. **Physical Activity and Exercise During Pregnancy and the Postpartum Period, Committee Opinion 804.** https://www.acog.org/clinical/clinical-guidance/committee-opinion/articles/2020/04/physical-activity-and-exercise-during-pregnancy-and-the-postpartum-period
9. AAP. **Resistance Training for Children and Adolescents.** Pediatrics 2020. https://publications.aap.org/pediatrics/article/145/6/e20201011/76942/
10. Mountjoy M, et al. **IOC consensus statement on Relative Energy Deficiency in Sport (REDs).** 2023. https://pubmed.ncbi.nlm.nih.gov/37752011/
11. PAR-Q+ / ePARmed-X+ official resources: https://eparmedx.com/

## Medication / intensity

12. American Heart Association. **How Do Beta Blocker Drugs Affect Exercise?** Current consumer/clinical education page; generic target HR may need adjustment and individualized exercise testing can be used. https://www.heart.org/en/health-topics/consumer-healthcare/medication-information/how-do-beta-blocker-drugs-affect-exercise
13. Medication identity/class normalization should use a verified drug source (for example RxNorm/ATC/licensed database). The pack deliberately does not ship raw-name -> class guesses.

## Regulatory — verify by market and feature

14. FDA. **General Wellness: Policy for Low Risk Devices**, Final Guidance, January 2026. https://www.fda.gov/regulatory-information/search-fda-guidance-documents/general-wellness-policy-low-risk-devices
15. FDA. **Clinical Decision Support Software**, Final Guidance, January 2026. https://www.fda.gov/regulatory-information/search-fda-guidance-documents/clinical-decision-support-software
16. FDA Digital Health Policy Navigator, healthy-lifestyle/software decision points. https://www.fda.gov/medical-devices/digital-health-center-excellence/step-3-software-function-intended-maintaining-or-encouraging-healthy-lifestyle
17. Regulation (EU) 2017/745 (MDR), including software intended purpose and Rule 11. https://eur-lex.europa.eu/eli/reg/2017/745/oj
18. European Commission MDCG guidance index; software qualification/classification document MDCG 2019-11 rev.1 (June 2025). https://health.ec.europa.eu/medical-devices-sector/new-regulations/guidance-mdcg-endorsed-documents-and-other-guidance_en

## Claude Code platform behavior

19. Claude Code official docs — custom subagents, nested delegation, tools, skills and startup context: https://code.claude.com/docs/en/sub-agents
20. Claude Code official docs — Skills/frontmatter: https://code.claude.com/docs/en/slash-commands

## Source governance

For every executable safety/numeric rule, store source or policy owner, population, version, review date and override conditions. A model-generated summary is never the source of truth.

## Emergency / urgent-pattern source IDs used by runtime rules

These IDs are referenced by `runtime/safety_rules.v1.json`. They support conservative escalation categories; they do not diagnose the condition named by the source.

- `AHA-CHEST-2025` — American Heart Association, heart-attack/chest-pain warning signs and urgent EMS guidance. https://www.heart.org/en/health-topics/heart-attack/warning-signs-of-a-heart-attack
- `AHA-ARRHYTHMIA-CURRENT` — American Heart Association, arrhythmia symptoms including dizziness, fainting/near-fainting, palpitations and chest pressure. https://www.heart.org/en/health-topics/arrhythmia/symptoms-diagnosis--monitoring-of-arrhythmia/
- `CDC-STROKE-2026` — CDC, Signs and Symptoms of Stroke, updated May 19 2026. https://www.cdc.gov/stroke/signs-symptoms/index.html
- `NICE-NEURO-NG127` — NICE NG127, immediate referral for severe low-back pain with new bladder/bowel/sexual disturbance or perineal numbness. https://www.nice.org.uk/guidance/ng127/chapter/Recommendations-for-adults-aged-over-16
- `CDC-VTE-CURRENT` — CDC, DVT/PE signs and immediate-care guidance. https://www.cdc.gov/blood-clots/about/
- `CDC-RHABDO-2025` — CDC/NIOSH, rhabdomyolysis symptoms and immediate medical-attention guidance, Jan 14 2025. https://www.cdc.gov/niosh/rhabdo/signs-symptoms/index.html
- `NICE-SEPTIC-JOINT-NG219` — NICE NG219, suspected septic arthritis requires immediate referral through local pathway. https://www.nice.org.uk/guidance/ng219/chapter/Recommendations
- `CDC-HEAT-CURRENT` — CDC/NIOSH, heat-stroke symptoms including confusion/altered mental status and emergency response. https://www.cdc.gov/niosh/heat-stress/about/illnesses.html
- `PRODUCT-CRISIS-SAFETY-POLICY` — product safety policy placeholder. Must be localized and approved by the safety/clinical owner; this pack does not hardcode hotline numbers or jurisdiction-specific emergency instructions.

Runtime safety rules remain `ENGINEERING_BASELINE_NOT_CLINICALLY_SIGNED_OFF` until the governance sign-off record is completed.
