---
name: fitness-regulatory-reference
description: Regulatory boundary reference for Fitness-App features and claims. Covers general-wellness versus medical-purpose risk in the US and EU, with special attention to symptom triage, injury prediction, diagnosis/treatment claims, physiological-signal analysis, and AI-enabled software. Requires current official-source verification.
user-invocable: false
---
# Fitness-App regulatory reference v2.2

This is a **design-review reference**, not legal advice. Regulatory status depends on intended purpose, claims, functionality, jurisdiction and current law/guidance. A named human regulatory/legal owner must approve release decisions.

## United States

FDA's January 2026 General Wellness guidance keeps low-risk software for maintaining/encouraging a healthy lifestyle, unrelated to diagnosis/cure/mitigation/prevention/treatment of disease, outside or at the edge of device oversight depending on the exact function and claims.

Escalate for regulatory review when a feature:
- diagnoses or claims to detect a disease/injury;
- predicts individual injury/disease risk;
- interprets symptoms to determine a medical condition or treatment path;
- analyzes physiological/medical signals for clinical implications;
- recommends treatment or medication changes;
- makes disease-specific claims beyond permitted general-wellness framing.

Do not assume that calling a feature “AI coach” or adding a disclaimer changes its intended purpose.

## European Union

Under Regulation (EU) 2017/745, software specifically intended for a medical purpose can qualify as a medical device; lifestyle/well-being software without a medical purpose does not. Rule 11 can classify software that provides information used for diagnostic or therapeutic decisions at Class IIa or higher depending on potential impact.

Escalate when intended purpose or marketing includes diagnosis, prevention, monitoring, prediction, prognosis, treatment or alleviation of disease/injury, or when software outputs drive diagnostic/therapeutic decisions.

## Product-claim review categories

- `LOWER_RISK_WELLNESS`: exercise education, generic fitness planning, habit/recovery coaching without disease/injury claims.
- `REGULATORY_REVIEW_REQUIRED`: symptom triage, disease-specific adaptation, physiological-signal interpretation, claims that exercise recommendations mitigate/treat a condition, camera-based injury-risk prediction.
- `HIGH_RISK_CLAIM`: diagnosis, treatment selection, emergency decision support presented as definitive, medication advice, or claims whose failure could plausibly cause serious harm.

These labels are internal routing labels, not legal classifications.

## Required output

For every reviewed feature capture:
- jurisdiction;
- intended purpose;
- exact user-facing/marketing claims;
- data analyzed;
- decision/action produced;
- who uses the output;
- foreseeable harm if wrong;
- likely wellness/device boundary questions;
- official sources checked and dates;
- unresolved questions for counsel/regulatory owner.
