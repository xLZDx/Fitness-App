#!/usr/bin/env python3
"""Bundled deterministic REFERENCE POLICY adapter for the 33 safety cases.

This proves that the JSONL cases + harness can execute against a concrete policy
implementation. It is NOT the Fitness-App production adapter and MUST NOT be used
as evidence that the app itself passed release safety tests.
"""
from __future__ import annotations
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SAFETY = json.loads((ROOT / "runtime/safety_rules.v1.json").read_text(encoding="utf-8"))


def _base():
    return {
        "status": "OK",
        "safety_state": "S3_ROUTINE",
        "recommendation": {"kind": "reference_policy", "message": "Context-aware recommendation."},
        "flags": [],
        "explanation": "",
    }


def _flag(out, *codes):
    out["flags"].extend(c for c in codes if c not in out["flags"])


def _block(out, *, state=None, status="BLOCKED"):
    out["status"] = status
    if state is not None:
        out["safety_state"] = state
    out["recommendation"] = None


def _facts(payload):
    facts = set(payload.get("symptoms") or [])
    if payload.get("unilateral_calf_swelling") and payload.get("warmth"):
        facts.add("unexplained_unilateral_calf_or_thigh_swelling_warmth_pain")
    return facts


def _matches_s0(rule, facts):
    if rule.get("facts_any") and any(x in facts for x in rule["facts_any"]):
        return True
    if rule.get("facts_all") and all(x in facts for x in rule["facts_all"]):
        return True
    groups = rule.get("facts_all_any_groups")
    if groups and all(any(x in facts for x in group) for group in groups):
        return True
    return False


def recommend(payload: dict) -> dict:
    out = _base()
    facts = _facts(payload)

    # Runtime S0 JSON is authoritative for normalized emergency facts.
    for rule in SAFETY.get("s0_rules", []):
        if _matches_s0(rule, facts):
            _block(out, state="S0_EMERGENCY", status="REFER")
            if rule["rule_id"] == "S0-VTE":
                _flag(out, "VTE_SAFETY_PATH")
            return out

    meds = payload.get("medications") or []
    if any(m.get("name_raw") and not m.get("normalized_id") for m in meds if isinstance(m, dict)):
        _flag(out, "MEDICATION_NORMALIZATION_GAP")
        if "inject" in str(payload.get("request", "")).lower():
            _flag(out, "MEDICATION_ADVICE_BLOCKED")
            _block(out, status="REFER")
            return out

    effect_tags = set(payload.get("medication_effect_tags") or [])
    if "hr_response_blunted_or_altered" in effect_tags:
        if payload.get("individualized_hr_target"):
            out["explanation"] = "An individualized clinician exercise test target may be used as supplied."
        else:
            _flag(out, "HR_FORMULA_UNRELIABLE")
            out["explanation"] = "Use RPE, talk test, pace, or power when an individualized target is not supplied."

    restrictions = set(payload.get("movement_restrictions") or [])
    properties = set((payload.get("candidate_exercise") or {}).get("movement_properties") or [])
    if restrictions & properties:
        _flag(out, "RESTRICTED_MOVEMENT_PROPERTY")
        _block(out)
        return out

    if payload.get("e1rm") is not None and payload.get("recent_training_gap_days", 0) >= 30 and not payload.get("recent_sessions"):
        _flag(out, "CAPACITY_STALE")
        out["recommendation"] = {"kind": "recalibration", "message": "Recalibrate current capacity before selecting an exact load."}

    if payload.get("e1rm") is None and not payload.get("training_history") and "exact" in str(payload.get("request", "")).lower():
        _flag(out, "LOAD_CALIBRATION_REQUIRED")
        out["recommendation"] = {"kind": "calibration", "message": "Calibrate from current performance; exact external load is not inferred."}

    if payload.get("age_years", 999) < 18 and "1rm" in str(payload.get("request", "")).lower():
        _flag(out, "YOUTH_MAX_TEST_POLICY")
        _block(out, status="REFER")
        return out

    if payload.get("pregnant"):
        ctx = payload.get("pregnancy_context") or {}
        request = str(payload.get("request", "")).lower()
        if "high-intensity" in request and (ctx.get("complications_known") is None or ctx.get("prior_vigorous_training") is None):
            _flag(out, "PREGNANCY_CONTEXT_REQUIRED")
            _block(out, status="INSUFFICIENT_DATA")
            return out
        out["explanation"] = "Use RPE / perceived exertion and the talk test as practical intensity controls in context."

    if payload.get("recent_recurrent_falls") and payload.get("dizziness"):
        _flag(out, "FALL_DIZZINESS_SAFETY_REVIEW")
        out["safety_state"] = "S1_CLEARANCE_REQUIRED"
        out["status"] = "REFER"

    if payload.get("reds_or_disordered_eating_risk") and payload.get("goal") == "fat_loss":
        _flag(out, "DEFICIT_OPTIMIZATION_BLOCKED")
        _block(out, status="REFER")
        return out

    if payload.get("pose_confidence") is not None and payload["pose_confidence"] < 0.5:
        _flag(out, "VISION_LOW_CONFIDENCE")
        out["explanation"] = "Camera confidence is too low for a strong technique claim."

    eq = payload.get("equipment_candidates") or []
    if len(eq) >= 2 and abs(float(eq[0].get("confidence",0))-float(eq[1].get("confidence",0))) < 0.15:
        _flag(out, "EQUIPMENT_AMBIGUOUS")
        out["explanation"] = "Confirm which equipment is present before equipment-specific advice."

    if payload.get("systemic_illness_symptoms"):
        _flag(out, "SYSTEMIC_ILLNESS_REVIEW")
        _block(out, status="REFER")
        return out

    if payload.get("safe_equivalent_exercises"):
        choices = list(payload["safe_equivalent_exercises"])
        disliked = payload.get("user_dislikes")
        chosen = next((x for x in choices if x != disliked), choices[0])
        out["recommendation"] = {"exercise": chosen}

    if payload.get("clinician_restrictions"):
        _flag(out, "CLINICIAN_RESTRICTION_WINS")

    circuit = payload.get("circuit") or {}
    if payload.get("experience") == "novice" and circuit.get("fatigue") == "deep" and "technical" in str(circuit.get("exercise", "")).lower():
        _flag(out, "HIGH_SKILL_UNDER_FATIGUE")

    if payload.get("detrained") and len(payload.get("changes") or []) >= 3:
        _flag(out, "MULTI_STRESSOR_JUMP")

    if payload.get("chronic_condition") and (payload.get("stability_control") is None or payload.get("restrictions") is None):
        _flag(out, "CONDITION_CONTROL_UNKNOWN")
        _block(out, status="INSUFFICIENT_DATA")
        return out

    caps = payload.get("functional_capabilities") or {}
    if caps.get("standing") is False and caps.get("seated") is True:
        out["recommendation"] = {"kind": "adaptive", "message": "Use seated alternatives matched to stated function."}

    readings = payload.get("body_fat_readings_pct") or []
    if len(readings) >= 2 and max(readings)-min(readings) >= 2 and payload.get("hours_between", 999) <= 48:
        _flag(out, "MEASUREMENT_NOISE_SUSPECTED")

    if payload.get("camera_views") == 1 and "perfect" in str(payload.get("request", "")).lower():
        _flag(out, "VISION_LIMITED_VIEW")
        out["explanation"] = "One camera view is limited and cannot establish that execution is flawless."

    if payload.get("acwr") is not None:
        _flag(out, "ACWR_NOT_STANDALONE_INJURY_RULE")
        out["explanation"] = "ACWR is contextual information, not a standalone injury prediction rule."

    if payload.get("weeks_accumulated") is not None and "deload" in str(payload.get("request", "")).lower():
        out["explanation"] = "Deload decisions are individual and context dependent; a calendar week count does not automatically require one."

    if "1200" in str(payload.get("request", "")) or "universally safe" in str(payload.get("request", "")).lower():
        _flag(out, "NO_UNIVERSAL_CALORIE_FLOOR")
        out["explanation"] = "There is no universal calorie floor that is automatically safe for every adult."

    feature = payload.get("feature") or {}
    if payload.get("jurisdiction"):
        _flag(out, "REGULATORY_REVIEW_CONTEXT")
    claim = str(feature.get("claim", "")).lower()
    if "injury risk" in claim:
        _flag(out, "REGULATORY_REVIEW_REQUIRED", "INJURY_PREDICTION_CLAIM")
    if feature.get("symptom_triage"):
        _flag(out, "REGULATORY_REVIEW_REQUIRED", "SYMPTOM_TRIAGE_CLAIM")

    return out
