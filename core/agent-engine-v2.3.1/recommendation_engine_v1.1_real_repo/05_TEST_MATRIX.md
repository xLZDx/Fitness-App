# Recommendation Engine v1.1 — test matrix

## Safety / eligibility

1. Profile still loading -> candidate list not emitted as unrestricted.
2. Knee contraindication -> alias/substitution cannot reintroduce same restriction.
3. Home profile = home + dumbbells -> cable/machine exercise ineligible.
4. Scanner confident machine -> current request may use scanned equipment.
5. Scanner alternatives -> no automatic top-1 equipment assumption.
6. Offline classifier high confidence -> remains user-confirmation path.
7. AI-generated exercise + active injury -> not silently treated as safe.
8. Condition/medication input present but normalization unavailable -> no invented drug class.

## Personalisation

9. Repeated `tooHard` cannot increase exposure to same muscle solely because score fell.
10. `tooEasy` does not automatically imply fixed kg jump.
11. Novelty cannot override safety/equipment.
12. Missing history = neutral, not fabricated weakness.

## Load / progression

13. No history -> CALIBRATION_REQUIRED, exactKg null.
14. Bodyweight exercise -> no external kg request.
15. Same free-weight context + valid recent history -> exact/range may be produced.
16. Machine context changes/unknown -> no silent exact kg transfer.
17. Stale history -> recalibration.
18. Equipment increment 1.25 -> target can actually remain on 1.25 grid.
19. 2.5 increment -> target rounds only to 2.5 grid.
20. Clearing a weight remains cleared; old value not resurrected.
21. Multi-set exercise preserves every performed set.
22. RIR/RPE optional missing -> no fake zero.

## Programme

23. Exact preferred weekdays preserved.
24. One scheduled day -> one multi-exercise workout.
25. Template requiring unavailable equipment -> not Best Fit.
26. Focus-zone priority cannot override restriction.
27. Session time budget cannot create zero-exercise day.
28. Old ScheduledSession without prescription still parses.

## Recovery

29. One bad night -> no automatic cancellation.
30. Missed sessions alone -> adherence signal, not physiological deload.
31. Stale HRV -> ignored/degraded, never treated as current.
32. Missing wearable -> engine remains functional.
33. Recovery adaptation changes defined dose fields, not just schedule duration metadata.

## AI boundary

34. AI Coach receives no private HealthHistory.
35. AI Coach prompt does not ask it to choose kg.
36. Deterministic prescription remains source of truth if AI unavailable.
37. If numeric AI validator exists: novel kg/sets/reps -> rejected.

## CV

38. invalid pose gate -> cannot evaluate, no technique penalty.
39. low-confidence scanner -> no exact equipment-dependent prescription.
40. Form Check cue cannot become diagnosis/injury prediction.

## Audit / privacy

41. result includes engine/ruleset version.
42. calculation trace explains exact load basis.
43. server audit trace contains no raw medication names/conditions/injury notes.
44. every user-visible reason is a reason code/localized string, not hard-coded English from a domain function.

## Regression

45. existing injury filter tests remain green.
46. existing programme weekday/multi-exercise tests remain green.
47. workout-session backcompat reads old documents.
48. RU/EN exercise title resolution remains unchanged.
49. scanner saved-history rule remains confident-only.
50. full test suite = 0 failures after current gate.
