---
name: fitness-evidence-rules
description: Evidence hierarchy and source-verification rules for clinical, training, nutrition, and product-safety recommendations.
user-invocable: false
---
# Fitness-App evidence rules v2

## Evidence hierarchy

Prefer, in order:
1. Current official clinical/public-health guidelines and professional position statements relevant to the exact population.
2. Current systematic reviews / meta-analyses of controlled trials.
3. Randomized or prospective controlled studies.
4. Observational evidence.
5. Expert consensus/opinion when stronger evidence is unavailable.

Do not treat a credential, influencer, single textbook, or training tradition as equivalent to evidence.

## Source rules

- For safety-critical or medical-adjacent claims, verify current primary/official sources before changing product policy.
- Record title, issuing body, publication/update date, URL/DOI, population, and exact claim supported.
- Distinguish evidence for healthy adults from evidence for youth, pregnancy/postpartum, older/frail adults, chronic disease, disability, or athletes.
- Do not extrapolate a result about group averages into a precise individual prediction.
- If reputable guidance conflicts, state the conflict and choose the more conservative product behavior until a clinical owner decides.
- Mark product-policy choices separately from scientific conclusions.

## Baseline references to re-check for freshness

- ACSM 2026 Position Stand on resistance training prescription in healthy adults (Med Sci Sports Exerc. 2026;58(4):851-872; DOI 10.1249/MSS.0000000000003897).
- WHO Guidelines on Physical Activity and Sedentary Behaviour (2020) for children/adolescents, adults, older adults, pregnancy/postpartum, chronic conditions and disability.
- ACOG Committee Opinion 804 on physical activity/exercise during pregnancy and postpartum; verify whether replaced/updated before release.
- AAP Clinical Report: Resistance Training for Children and Adolescents (2020); verify current status before release.
- IOC 2023 consensus on Relative Energy Deficiency in Sport (REDs), including CAT2 and body-composition risk considerations.
- PAR-Q+ / ePARmed-X+ current official materials for pre-participation screening; verify current questionnaire/version and license/use conditions.

## Evidence output

For every material product rule changed, return:

```yaml
claim: ...
population: ...
source_type: guideline | position_statement | systematic_review | trial | other
source: ...
published_or_updated: ...
applicability: direct | partial | extrapolated
confidence: high | medium | low
product_rule: ...
notes: ...
```
