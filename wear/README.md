# Wear OS companion (scaffold)

Minimal Wear OS Kotlin module that consumes the `fitnessapp/wear_sync`
MethodChannel from the phone app. Phase E1 in the v2 roadmap.

**Status: scaffold only.** Build wiring + IDE recognition pending. The
Flutter side already speaks to a `MethodChannelWearSyncService` so the
phone APK ships fine without this module — building the watch APK is
the remaining work.

## Pieces

- `build.gradle.kts` — Compose-for-Wear-OS app target, API 33+.
- `AndroidManifest.xml` — Wearable feature flag + `MainActivity`.
- `MainActivity.kt` — bootstraps the Compose UI and registers the
  Wearable Data Layer listener that mirrors the phone's
  `WearWorkoutState` JSON envelope.
- `ui/WatchFace.kt` — Compose surface: current exercise + set counter
  + rest-timer ring + tappable "Done set" button.
- `data/WearStateRepository.kt` — single source of truth for the
  watch-side state; the data-layer listener feeds it.

## Phone ↔ Watch envelope

```json
{
  "title": "Squat",
  "set": 2,
  "totalSets": 5,
  "kg": 80.0,
  "rest": 90,
  "isResting": true
}
```

Same shape as `WearWorkoutState.toMessage()` on the phone side. We
keep it tiny on purpose — Wearable Data Layer has a 100 KB ceiling
per message, and a circular watch face has no room for narrative
text.

## Build

```bash
# Wear OS APK
./gradlew :wear:assembleDebug
adb -s <watch-emu> install build/outputs/apk/debug/wear-debug.apk

# Phone APK still builds via Flutter as before; the wear module is a
# sibling target, not a Flutter dependency.
flutter build apk --debug
```

The phone-side `MethodChannelWearSyncService` works in test mode against
a paired Wear OS emulator without changes — the JSON envelope flows over
the data layer as long as both APKs share the same applicationId base.
