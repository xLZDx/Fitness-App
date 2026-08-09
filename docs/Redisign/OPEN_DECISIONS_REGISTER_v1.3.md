# Fitness App — Open Decisions Register v1.3

## Corrected summary

| Category | Count |
|---|---:|
| Debt from completed gates D1–D5 and D7 | 22 |
| D6 questions / blockers | 8 |
| Future D8–D9 decisions | 14 |
| Total | 44 |

Previous summary `26 / 8 / 10` was inconsistent with the actual gate counts.

## Required normalization

- Q39: LOCKED — Flutter.
- Q19: replace React Native wording with current Flutter/on-device ML wording.
- Q1 + Q41: duplicate decision, one Light Theme ADR.
- Q4: platform health integration decision, not fake iOS stub.

## Register

### D1 — Research, Audit, IA & Design System

1. Light theme — полная система или только ключевые экраны?
   - Options: Full D9 / 3–5 screens / Post-launch
   - Owner: Product + Design
   - Note: linked duplicate Q41.

2. Developer Handoff — отдельный экран в прототипе или только Figma-аннотации?
   - Options: Prototype screen / Figma-only
   - Owner: Product
   - Classification: internal process decision; does not block product UX.

3. Token naming — финальный словарь до D9?
   - Options: Approve now / Refactor in D9
   - Owner: Design + Dev

### D2 — Onboarding & Body Metrics

4. Health integration platform scope?
   - Corrected options: Android now / Android + separate iOS integration in same release / Defer platform integration
   - Owner: Dev + Product

5. Обязательные шаги — какие метрики на onboarding, а какие в Profile?
   - Options: Goal+level minimum / All 13
   - Owner: UX + Product

6. BMI — показывать или только вес и цель?
   - Options: Hide / Show neutrally
   - Owner: Product

7. Onboarding skip — полный пропуск или минимум 3 шага?
   - Options: Full skip / Minimum 3 / No skip
   - Owner: Product

### D3 — Home & Navigation

8. Recovery score — on-device или backend?
   - Options: On-device approximate / Backend
   - Owner: Tech + Product

9. Фото-карточка на Home — когда показывать?
   - Options: After 2+ compatible photos / milestone only
   - Owner: UX

10. Notch / Dynamic Island — отдельная адаптация header?
    - Options: Native adaptation / Safe area sufficient
    - Owner: Dev

### D4 — Scanner & Equipment

11. Offline equipment catalog scope?
    - Options: Top 50 / Top 200 / Full
    - Owner: Product + Dev

12. Unknown equipment — отправлять для ML improvement?
    - Options: With explicit consent / Local only
    - Owner: Privacy + Tech

13. Manual fallback for unknown equipment?
    - Options: Search / No fallback / Photo + ticket
    - Owner: UX

14. Equipment Page — full screen or bottom sheet?
    - Options: Full page / Bottom sheet
    - Owner: UX

### D5 — Exercise & Workout Player

15. Auto-progression recommendation timing?
    - Options: Immediate after +5% record / after 2 workouts / never
    - Owner: Product

16. Rest Timer sound default?
    - Options: On / Off
    - Owner: UX

17. Supersets and drop-sets scope?
    - Options: MVP / D8 / Post-launch
    - Owner: Product

18. Exercise replacement history in workout log?
    - Options: Save replacement marker / No
    - Owner: Product

### D6 — Technique Coach & Workout Summary

19. Form Check ML scope?
    - Corrected options: Real on-device ML in current Flutter stack / Demo prototype
    - Owner: Tech + Product
    - Status: HARD BLOCKER

20. Supported exercises for first release?
    - Options: Top 5 / Top 15 / All library
    - Owner: Product
    - Status: HARD BLOCKER

21. Exercise-to-camera-angle matrix?
    - Required artifact: exercise → side/front/45-degree → required landmarks
    - Owner: Sport Science
    - Status: HARD BLOCKER

22. Save Form Check history in workout log?
    - Options: Summary linked to workout / Session-only
    - Owner: Product
    - Provisional default: summary metadata only; no frames/video.

23. Voice cue implementation?
    - Options: On-device TTS / Recorded files
    - Owner: Dev
    - Status: HARD BLOCKER

24. Voice language?
    - Options: RU only / RU+EN / app-system locale
    - Owner: Product
    - Provisional default: app/system locale.

25. Show confidence percentage?
    - Options: Raw percent / Hide raw value
    - Owner: UX
    - Provisional default: reliability label, no raw percent.

26. Workout Summary route relation?
    - Options: Replace existing WorkoutDone / New screen layered after it
    - Owner: Dev
    - Status: HARD BLOCKER

### D7 — Progress & Progress Photos

27. Photo storage policy?
    - Options: Local-only MVP / Cloud opt-in / Cloud default
    - Owner: Privacy + Tech

28. Face anonymization before export?
    - Options: Optional / Default on / Not included
    - Owner: Privacy + UX

29. Milestone tags?
    - Options: Standard only / Standard + custom
    - Owner: UX

30. Compare different camera angles?
    - Options: Block / Warn and allow
    - Owner: UX

### D8 — Programs, AI Coach, Profile, Subscription

31. Paywall placement?
    - Options: After Plan Preview / At limit
    - Owner: Product

32. Free-tier limits?
    - Options: Proposed counts / Other
    - Owner: Product

33. AI Coach scope?
    - Options: Workout-only / Global contextual
    - Owner: Product

34. AI Coach backend?
    - Options: Contextual API / Rules / Custom model
    - Owner: Tech

35. Subscription periods?
    - Options: Month+year / plus quarter
    - Owner: Product

36. Family subscription?
    - Options: No / Post-launch / D8
    - Owner: Product

37. Profile data export in MVP?
    - Options: MVP / Post-launch
    - Owner: Legal + Product

38. Garmin/Polar scope?
    - Options: D8 / Post-launch
    - Owner: Product

### D9 — States, Accessibility, Platform & Prototype

39. Mobile implementation stack?
    - Decision: LOCKED — Flutter
    - Status: Locked by Existing Architecture
    - React Native/native rewrite is out of scope.

40. Minimum OS versions?
    - Options: Android 10+/iOS 16+ / Android 8+/iOS 15+
    - Owner: Dev

41. Light theme timing?
    - Options: D9 / Post-launch / system-only
    - Owner: Product
    - Status: Duplicate/continuation of Q1.

42. Reduced motion coverage?
    - Options: Full alternatives / Critical only
    - Owner: Dev + Design

43. Offline mode scope?
    - Options: Workout only / Home+Workout+Progress
    - Owner: Tech + Product

44. Push notification types?
    - Options: Workout only / Workout+photos+records
    - Owner: Product
