# iOS permissions TODO

The iOS folder hasn't been generated yet (Android-first launch). When
`flutter create -i swift --platforms=ios .` lays down `ios/Runner/Info.plist`,
add these usage-description keys so HealthKit / camera / mic / BLE
flows don't crash on first prompt:

```xml
<!-- Health (HealthKit). The `health` Flutter package routes both
     keys through the system permission picker. -->
<key>NSHealthShareUsageDescription</key>
<string>Fitness reads your workouts, steps, sleep, and HRV so we can
show recovery insights and adjust your plan.</string>
<key>NSHealthUpdateUsageDescription</key>
<string>Fitness writes completed workouts back to Apple Health so they
land in your activity rings alongside other apps.</string>

<!-- Camera (form check + visual equipment recognition). -->
<key>NSCameraUsageDescription</key>
<string>Fitness uses the camera on-device for form-check feedback and
to recognise gym equipment from a photo. No frames are uploaded.</string>

<!-- Mic (voice-only mode). -->
<key>NSMicrophoneUsageDescription</key>
<string>Fitness listens for voice commands like "done set" so you can
keep your hands on the bar.</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>Speech recognition runs on-device to power the voice-only
workout mode.</string>

<!-- BLE (TX.3 buddy matching). -->
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Fitness uses BLE to find a workout buddy who's at the same gym.</string>

<!-- Photo library (progress photos saved to Photos). -->
<key>NSPhotoLibraryAddUsageDescription</key>
<string>Save progress photos to your library (you control the
encryption key — they stay private to you).</string>
```

Plus the Health-Capabilities entitlement in
`ios/Runner/Runner.entitlements`:

```xml
<key>com.apple.developer.healthkit</key>
<true/>
<key>com.apple.developer.healthkit.access</key>
<array/>
```

When iOS lands, also enable HealthKit in the Xcode project Capabilities
tab so the entitlement plumbs through to the provisioning profile.
