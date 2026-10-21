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

## Acceptance criteria for delivery 1 (measurable; thresholds are proposals to confirm before the pilot)
1. Pass-by test: 20 passes within 100 m of a gym without entering produce 0 saved visits.
2. Adjacent-business test: 10 visits to a different business in the same building produce 0 saved gym visits without user confirmation.
3. True visits: of 30 real visits of 45 minutes or more with the app open inside the gym, at least 27 (90%) are detected or offered for confirmation.
4. Poor accuracy: fixes with reported accuracy worse than 100 m never create a saved visit.
5. Privacy: no location is sent to a server before the visit is confirmed or the user has agreed to upload; turning attendance off deletes pending evidence on the device.
6. Permissions: with foreground location denied the app works fully and explains what attendance needs.
The pilot corpus, devices (Samsung S8 reference) and who runs the pilot are fixed before the pilot starts.

## Package registers affected
FU-AC-047 (calibrated automatic inference) gets the thresholds above instead of "to be defined"; the background-geofence rows move to delivery 2.
