# Change record: enable the V0 queue for one test account and fix the Android build (2026-10-23)

Base: master 2db7f8b5. Operator word given 2026-10-23 ("разрешаю все"; account chosen by me on the operator's instruction).

## What changed (live, dev project fitness-app-korostelev)
- Firestore document users/Lo8d63DKKug55g5ZtcIPeuOC5cL2/workout_command_policy/current created (migrationState SERVER_ONLY, sendingPaused false). The account is the operator's own Google sign-in (korostelevivan@gmail.com); it did not exist before (read first: 404). Rollback: delete that one document, or set sendingPaused true (every command then answers MIGRATION_HOLD and stays pending on the device).
- Cloud Run service submitworkoutcommands (europe-west1): env WORKOUT_COMMANDS_ENABLED=true, new revision submitworkoutcommands-00003-lrs, 100 percent traffic, previous revision -00002-red. Rollback: update-env-vars WORKOUT_COMMANDS_ENABLED=false (or route traffic back to -00002-red). A normal firebase deploy of this function resets the variable unless it is added to the functions environment file.
- All other accounts have no policy document, so they still get MIGRATION_HOLD.

## Code change
- mobile/android/app/build.gradle: the wiredWithFiles lambdas are cast to kotlin.jvm.functions.Function1 instead of java.util.function.Function. The old cast failed the debug build on this machine (No signature of method wiredWithFiles) with AGP 8.7.0 / Gradle 8.10.2.

## Verification state
Debug APK built with --dart-define=WORKOUT_COMMAND_QUEUE=true (D:/tmp/v0_test_build/app-debug-queue-on.apk, google-services.json copied from the primary checkout, not committed). Not verified: install on a device, a real send, the 20-minute offline scenario. No tests run by the coordinator.
