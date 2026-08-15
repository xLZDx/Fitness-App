# Governance ownership — REQUIRED before production release

This package contains AI reviewers and engineering references. **AI agents are not accountable clinical or legal owners.** The product must name real humans/organizations for the roles below before a production release that uses the corresponding feature class.

| Area | Required human owner | Release condition |
|---|---|---|
| Clinical safety policy / red flags / condition restrictions | Named licensed clinical advisor with scope appropriate to target market/populations | `REQUIRED_BEFORE_MEDICAL_ADJACENT_RELEASE` |
| Exercise-programming policy | Qualified strength & conditioning / exercise professional | `REQUIRED_BEFORE_PERSONALIZED_PRESCRIPTION_RELEASE` |
| Nutrition / body-composition policy | Registered/licensed dietitian where applicable | `REQUIRED_BEFORE_INDIVIDUALIZED_NUTRITION_RELEASE` |
| Pregnancy/postpartum policy | Obstetric/qualified women's-health clinical reviewer | `REQUIRED_BEFORE_PREGNANCY_FEATURE_RELEASE` |
| Youth policy | Pediatric/adolescent exercise clinical reviewer | `REQUIRED_BEFORE_UNDER18_RELEASE` |
| Regulatory / legal intended-purpose review | Named regulatory counsel/specialist for each jurisdiction | `REQUIRED_BEFORE_CLAIMS_OR_MEDICAL_ADJACENT_RELEASE` |
| Safety rule-engine implementation | Named engineering owner | `REQUIRED_BEFORE_RELEASE` |
| CV/pose/equipment model safety | Named ML/CV owner | `REQUIRED_BEFORE_CAMERA_COACH_RELEASE` |
| Privacy/data protection | Named privacy/security owner; DPO where required | `REQUIRED_BEFORE_PERSONAL_HEALTH_DATA_RELEASE` |

## Sign-off record

Populate this table in the real repository; do not leave placeholders in a release branch.

```yaml
clinical_safety_owner:
  name: REQUIRED
  credentials_scope: REQUIRED
  jurisdictions: []
  approved_policy_version: null
  approved_at: null

regulatory_owners:
  US:
    name_or_firm: REQUIRED_IF_US_MARKET
    reviewed_intended_purpose_version: null
    reviewed_at: null
  EU:
    name_or_firm: REQUIRED_IF_EU_MARKET
    reviewed_intended_purpose_version: null
    reviewed_at: null

safety_engineering_owner:
  name: REQUIRED
  rule_bundle_version: null
  signed_at: null
```

## Change-control rule

Any change to an executable S0/S1 safety rule, medication-effect behavior, pregnancy/youth restriction, diagnostic/injury-risk claim, or emergency flow requires:

1. source/evidence update;
2. applicable human owner review;
3. safety eval suite pass;
4. static package checks pass;
5. version bump and audit-log entry.
