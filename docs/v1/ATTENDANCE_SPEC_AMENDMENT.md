# Amendment: GPS gym attendance, first delivery (2026-10-21)

Decision (operator, 2026-10-21): the first delivery detects gym attendance while the app is open (foreground). Background geofences are a separate later step, started only after the Google Play background-location policy is checked.

## Facts this rests on
- `mobile/android/app/build.gradle` removes `ACCESS_BACKGROUND_LOCATION` unconditionally ("Always: background location is never declared in S04"); the removal runs for both `GPS_RECORDER` modes.
- No geofence, attendance or gym-map code exists in `mobile/lib` today (grep on the integration candidate was empty).
- Google Play allows background location only for a core, user-visible benefit with a justified declaration, and a foreground service is not an automatic exemption (Play Console Help; re-verify with a dated source before the declaration is written).

## Delivery 1 (this amendment): foreground attendance
- A visit is suggested or recorded only while the app is open and the user has granted foreground location.
- An attendance visit (GymVisit) stays separate from a workout (WorkoutSession) and from a GPS track.
- Low-confidence evidence stays "unknown" or asks the user to confirm; only high-confidence visits are saved automatically.
- A user who never opens the app near the gym gets no automatic visit. This is a stated limitation of delivery 1, not a defect.

## Delivery 2 (later, separate decision): background geofences
Entry criteria: a written Play policy assessment with source and date, an Android manifest change plan that reverses the unconditional removal behind its own flag, in-app disclosure copy, and a privacy review. Until then the build keeps stripping the permission.

## Classes used by the criteria
- Automatic detection: a visit saved without user action. Allowed only for high confidence.
- Confirmation suggestion: the app asks "were you at the gym?" and saves only after the user says yes. A suggestion is not a detection.
- Unknown: no visit, no prompt.
The high-confidence rule (for example minimum dwell time inside the gym polygon, accuracy limit, number of consistent fixes), the ground-truth labeling rules (who labels a visit and from what evidence) and the pilot thresholds are written down and frozen before the pilot starts; the counts below are minimum scenarios, not proof of statistical calibration.

## Acceptance criteria for delivery 1 (measurable; thresholds are proposals to confirm before the pilot)
1. Pass-by test: 20 passes within 100 m of a gym without entering produce 0 saved visits and 0 confirmation prompts counted as detections.
2. Adjacent-business test: 10 visits to a different business in the same building produce 0 automatic detections; confirmation suggestions are allowed but are counted separately as false-positive prompts, with a frozen maximum rate.
3. True visits, automatic: of 30 real visits of 45 minutes or more with the app open inside the gym, at least 20 (about 67%) are detected automatically with high confidence (recall of automatic detection), and automatic detections have 0 false positives in criteria 1 and 2 (precision). Visits that are only suggested are reported as a separate number and do not count toward this threshold. Both numbers are proposals and are frozen before the pilot.
4. Poor accuracy: fixes with reported accuracy worse than 100 m never create a saved visit or an automatic detection.
5. Foreground only (negative tests): with the app in the background, with the screen locked, after the app is terminated, and while the existing GPS recorder foreground service keeps delivering locations, no visit is inferred, saved or suggested from those samples. Only an explicit user confirmation after the app returns to the foreground can create a visit, and the saved record marks it as user-confirmed, not inferred. Test: walk into a gym with the app backgrounded for the whole visit; 0 visits are created until the user opens the app and confirms.
6. Privacy: no location is sent to a server before the visit is confirmed or the user has agreed to upload; turning attendance off deletes pending evidence on the device.
7. Permissions: with foreground location denied, approximate-only location, or location services off, attendance is off with an explanation of what it needs, and these journeys are unaffected: sign-in, set logging and the rest timer (`LOCAL_QUEUE_DECISION.md`), nutrition diary, equipment scan, body progress photos, AI coach chat. Test: run each listed journey once per permission state.
The pilot corpus, devices (Samsung S8 reference) and who runs the pilot are fixed before the pilot starts.

## Package registers affected
FU-AC-047 (calibrated automatic inference) gets the thresholds above instead of "to be defined"; the background-geofence rows move to delivery 2.
