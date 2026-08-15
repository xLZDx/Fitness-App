---
name: fitness-intake-contract
description: Canonical Fitness-App user/context schema, data provenance, freshness, and minimum-data requirements for personalized recommendations.
user-invocable: false
---
# Fitness-App intake contract v2

Use one canonical object across all experts and the recommendation engine. The schema is intentionally richer than the UI; collect only fields required for the current feature and consent context.

```jsonc
{
  "subject": {
    "id": "uuid",
    "age_years": 34,
    "sex_at_birth": "female|null",
    "gender": "female|null",
    "height_cm": 168.0,
    "body_mass_kg": 71.4,
    "body_composition": {"body_fat_pct": null, "method": null, "measured_at": null}
  },

  "consent": {
    "health_data_processing": true,
    "ai_recommendations_ack": true,
    "video_analysis": false,
    "wearable_data": false,
    "minor_guardian_flow_complete": null
  },

  "safety": {
    "screening_tool": {"name": "PAR-Q+", "version": null, "completed_at": null, "result": null},
    "current_symptoms": [],
    "red_flag_hits": [],
    "medical_conditions": [
      {"name_raw": "hypertension", "normalized_code": null, "status": "controlled", "source": "self_report"}
    ],
    "medications": [
      {
        "name_raw": "lisinopril",
        "normalized_name": null,
        "drug_class": null,
        "exercise_effect_tags": [],
        "verified_source": null,
        "verified_at": null
      }
    ],
    "clearance": {
      "status": "unknown",
      "restrictions": [],
      "source": null,
      "issued_at": null,
      "expires_at": null
    }
  },

  "pregnancy_postpartum": {
    "applicable": false,
    "pregnant": null,
    "gestational_weeks": null,
    "postpartum_weeks": null,
    "delivery_context": null,
    "obstetric_restrictions": [],
    "pelvic_floor_symptoms": []
  },

  "pain_rehab": {
    "current": [
      {
        "region": "left_knee",
        "onset": "2026-08-10",
        "pain_now_0_10": 2,
        "worst_24h_0_10": 4,
        "mechanism": null,
        "aggravating": ["deep_squat"],
        "easing": ["walking"],
        "neuro_symptoms": false,
        "under_clinician_care": false,
        "diagnosis_if_clinician_provided": null
      }
    ],
    "movement_restrictions": [],
    "cleared_movements": [],
    "return_to_activity_criteria": []
  },

  "training": {
    "training_age_months": 18,
    "current_level": "intermediate",
    "sessions_per_week_last_4w": 3.0,
    "detraining_weeks": 0,
    "weekly_hard_sets_by_muscle": {},
    "weekly_endurance_minutes": 90,
    "recent_session_load": null
  },

  "capacity": {
    "strength": {
      "e1rm": {"back_squat": {"value_kg": 92.5, "method": "epley_from_reps_rir", "measured_at": "2026-07-28"}},
      "bodyweight_tests": {"pushup_reps": 14}
    },
    "endurance": {
      "resting_hr": null,
      "max_hr": {"value": null, "source": null, "measured_at": null},
      "threshold_hr": null,
      "ftp_w": null,
      "critical_speed": null,
      "recent_race_or_field_test": null
    },
    "movement": {
      "tests": []
    }
  },

  "goals": {
    "primary": "hypertrophy",
    "secondary": [],
    "target_date": null,
    "priority_muscles": [],
    "sport": null,
    "body_composition_goal": null
  },

  "constraints": {
    "sessions_per_week": 4,
    "minutes_per_session": 60,
    "equipment_ids": [],
    "available_load_increments": {},
    "environment": "commercial_gym",
    "schedule": [],
    "preferences": [],
    "dislikes": [],
    "accessibility_needs": []
  },

  "readiness": {
    "date": "2026-08-15",
    "sleep_hours": null,
    "energy_1_5": null,
    "soreness_1_5": null,
    "stress_1_5": null,
    "resting_hr_delta": null,
    "hrv": {"value": null, "baseline": null, "device": null}
  },

  "nutrition_recovery": {
    "diet_pattern": null,
    "allergies": [],
    "protein_estimate_g_per_kg": null,
    "energy_intake_tracking": false,
    "menstrual_or_endocrine_reds_signals": [],
    "sleep_average_hours": null,
    "alcohol": null
  },

  "history": {
    "sessions": [],
    "exercise_performance": {},
    "pain_events": [],
    "program_changes": []
  },

  "vision_context": {
    "exercise_id": null,
    "equipment_id": null,
    "camera_view": null,
    "capture_quality": null,
    "pose_confidence": null,
    "observable_metrics": {},
    "model_version": null
  },

  "preference": {
    "locale": "ru-RU",
    "units": "metric",
    "coaching_tone": "direct",
    "explanation_depth": "medium"
  },

  "provenance": {
    "field_path": {
      "source": "self_report|device|vision|calculated|clinician_document|verified_external",
      "captured_at": null,
      "confidence": null,
      "source_version": null
    }
  }
}
```

## Contract rules

1. `age_years`, applicable safety state, goals, constraints, and recent history are minimum inputs for a personalized training prescription.
2. A specific load requires a recent basis in `capacity.strength` or `history.exercise_performance`; otherwise prescribe a calibration method such as RIR/RPE.
3. Heart-rate zone prescription requires a valid intensity method and medication/condition check. Do not silently use an age-predicted HRmax when the product claims precision.
4. Raw medication names are not enough. Exercise-effect tags must come from a verified medication normalization layer, not from model memory.
5. A clinician-provided diagnosis or restriction must be stored as provenance-bearing data; the model may not create one.
6. Vision outputs are observations, never medical facts. Store model version and confidence.
7. Treat consumer wearables and body-composition devices as noisy measurements; use trends and device-aware baselines.
8. Freshness is field-specific. A capacity value can become stale after detraining, illness, injury, major program change, or enough elapsed time to make it unreliable.
9. Collect sensitive fields only when relevant to the recommendation and consented. Do not use sex/gender as a generic shortcut when the actual causal input is training history, pregnancy status, body size, or another measurable factor.
10. Unit conversion happens at the boundary. Store canonical units internally and render user-preferred units at output.
