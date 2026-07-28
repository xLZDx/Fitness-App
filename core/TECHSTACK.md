# TECHSTACK

Current tech stack and key stack decisions. Source: mobile/pubspec.yaml,
functions/package.json, mobile/android build files. Current-state only.

## Mobile app (mobile/)
- Flutter · Dart SDK ^3.6.0 · Android AGP 8.7.0 · Kotlin 2.2.20 · Gradle
- State management: flutter_riverpod 2.6.1
- Routing: go_router 16.1.0
- Feature-first architecture: lib/features/<feature>/ (33 feature modules)

## Backend (Firebase BaaS)
- firebase_core 4.7.0 · firebase_auth 6.4.0 · cloud_firestore 6.3.0 · cloud_functions 6.0.0
- Firestore security rules + indexes at repo root (firestore.rules, firestore.indexes.json)

## Cloud Functions (functions/)
- Runtime Node 20 · TypeScript 5.4 · firebase-admin 12.6 · firebase-functions 6.0
- Purpose: Stripe Checkout + webhook bridge (stripe 17.4)

## On-device ML / sensors
- google_mlkit_pose_detection 0.14 · google_mlkit_image_labeling 0.14 · tflite_flutter 0.11
- mobile_scanner (QR) · camera · health 11.0 · flutter_blue_plus (BLE)
- speech_to_text · flutter_tts

## Cross-cutting
- Networking: dio 5.7 · Notifications: flutter_local_notifications + timezone
- Security: crypto · encrypt · permission_handler
- Media: video_player · image · image_picker
- Wear OS companion module (wear/, Kotlin)

## Key decisions
- Riverpod (not Bloc) for state; go_router for navigation
- Firebase as BaaS; payments via Stripe -> Cloud Functions bridge (no client-side secret)
- On-device ML for pose/equipment recognition (privacy: sensor data stays on device)
- Android-first; iOS on roadmap (abstractions must accommodate HealthKit + App Store IAP).
  The full rule is in core/CONVENTIONS.md -- it constrains package choice, not just architecture.

## Local toolchain

- Flutter SDK: `D:\flutter`
- Android SDK: `D:\android-sdk`
- Emulator AVD: `Pixel_API_34` (under `D:\android-sdk\avd`)
- JDK: `C:\Program Files\Microsoft\jdk-17.0.18.8-hotspot` (system install)
- Env vars pointing at the above: `PUB_CACHE`, `GRADLE_USER_HOME`, `TEMP`, `TMP`,
  `ANDROID_AVD_HOME`, `ANDROID_SDK_ROOT`, `FLUTTER_ROOT`
