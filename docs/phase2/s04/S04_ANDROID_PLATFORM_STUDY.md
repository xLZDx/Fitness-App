# S04 Android platform study (GPS recorder without a map)

Status: DRAFT, 2026-10-17. Documentation only; no code written, no command run, no device used. Closes gap G4 (and the Android half of G12) in `docs/phase2/s04/S04_DOC_READINESS.md`. Input for the architect's S04 design; this study makes NO design choice.

## 0. Method and labels

- FACT = stated on an official page; the URL and the read date follow in the same row. All pages were read on 2026-10-17 through a page-to-text fetch tool, which summarises the page. Where the fetch summary said a topic was "not on this page", the claim is not labelled FACT.
- INFERENCE = drawn from facts; the premise is named. UNKNOWN = not established from official sources. NOT_RUN = needs a device or a console and was not done.
- Sources used: developer.android.com, support.google.com/googleplay (Play Console help), docs.flutter.dev, pub.dev pages of the packages named in section 5. pub.dev shows relative dates ("19 days ago"); they are quoted as shown and are only valid on 2026-10-17.
- Short URLs: A = `https://developer.android.com`, P = `https://support.google.com/googleplay/android-developer`.

## 1. Current app state (read in this worktree)

| Item | Value | Label |
|---|---|---|
| targetSdk / compileSdk / minSdk | 36 / 36 / 26 (`mobile/android/app/build.gradle` lines 87, 125, 132) | FACT |
| Location packages | none; `permission_handler ^11.3.1` and `flutter_local_notifications ^17.2.4` are declared (`mobile/pubspec.yaml` lines 48, 75) | FACT |
| Manifest | declares CAMERA, POST_NOTIFICATIONS, RECEIVE_BOOT_COMPLETED, WAKE_LOCK, VIBRATE, Health Connect permissions; NO location permission, NO `FOREGROUND_SERVICE*`, no `<service>` of ours | FACT (`AndroidManifest.xml` lines 3-35, 74-96, 117) |
| Manifest note | comment says to re-add a permission "only together with the feature, the privacy text and the Play declaration" | FACT (lines 30-35) |
| Impact of targetSdk 36 | Android 14, 15 and 16 behaviour all applies to this app | INFERENCE (target 36 >= 34, 35, 36) |

POST_NOTIFICATIONS is already declared, so the notification permission is a runtime request only, not a manifest change (FACT, manifest line 7).

## 2. Foreground service of type `location`

| # | Claim | Label | Source (read 2026-10-17) |
|---|---|---|---|
| 2.1 | Manifest value `android:foregroundServiceType="location"`; permission `FOREGROUND_SERVICE_LOCATION` plus `FOREGROUND_SERVICE`; code constant `FOREGROUND_SERVICE_TYPE_LOCATION` | FACT | A/develop/background-work/services/fgs/service-types |
| 2.2 | From Android 14 (API 34, for apps targeting 34+) each foreground service must declare its type(s) in the manifest and the app must request the type-specific permission; without it the system throws `SecurityException` | FACT | A/develop/background-work/services/fgs/changes |
| 2.3 | Runtime prerequisites for the `location` type: location services on, and `ACCESS_COARSE_LOCATION` or `ACCESS_FINE_LOCATION` granted | FACT | A/.../fgs/service-types ; A/.../fgs/launch |
| 2.4 | A type passed to `startForeground()` that is not declared in the manifest throws `IllegalArgumentException` | FACT | A/.../fgs/launch |
| 2.5 | Start in two steps: `startForegroundService()` then the service calls `ServiceCompat.startForeground(id, notification, type)`; id must not be 0; notification priority must be LOW or higher | FACT | A/.../fgs/launch |
| 2.6 | The deadline of about 5 seconds between the two start steps (`ForegroundServiceDidNotStartInTimeException`) is not on the launch page | UNKNOWN from official text read; the launch page points to a "Service timeout" guide that was not read | A/.../fgs/launch |
| 2.7 | The system does not allow starting a foreground service from the background for apps targeting API 31+; exemptions include: transition from a user-visible state, user interaction with a notification/widget/bubble, high-priority FCM, exact alarm for a user-requested action, geofence transition, boot broadcasts (extra limits on 14+), the user turning off battery optimisation for the app | FACT | A/develop/background-work/services/fgs/restrictions-bg-start |
| 2.8 | Android 14+: a service that needs a while-in-use permission (location, camera, microphone) cannot be CREATED while the app is in the background, even if a general exemption applies; the app gets a `SecurityException` if it lacks the permission at creation | FACT | A/.../fgs/restrictions-bg-start |
| 2.9 | Practical rule from the same page: start the service while the app has a visible activity. A `location` service started by an app that holds `ACCESS_BACKGROUND_LOCATION` can access location all the time, even in the background | FACT | A/.../fgs/restrictions-bg-start ; A/.../fgs/service-types ("cannot create a location FGS while in background, exception: ACCESS_BACKGROUND_LOCATION") |
| 2.10 | Android 15: timeouts apply to `dataSync` and `mediaProcessing`; `location` is not named there. Which types a boot receiver may not start is "not said" on the page | FACT (timeouts named); UNKNOWN (boot-start rule for `location`) | A/.../fgs/changes |
| 2.11 | Android 16: jobs started from a foreground service follow job quotas (affects WorkManager use inside the recorder, not the service itself) | FACT | A/.../fgs/changes ; A/topic/performance/power/power-details |

Manifest entries a recorder would need (derived from 2.1-2.4; INFERENCE, a checklist, not a design):
- `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`; `POST_NOTIFICATIONS` already present.
- One `<service ... android:foregroundServiceType="location" android:exported="false">`. If a Flutter package supplies the service, it may declare this itself or require the app to declare it (see section 5).
- `ACCESS_BACKGROUND_LOCATION` only if the design needs it (see 3.6 and the open questions).

## 3. Runtime permission sequence

| # | Claim | Label | Source (read 2026-10-17) |
|---|---|---|---|
| 3.1 | Ask in context after a user tap, never at app launch | FACT | A/develop/sensors-and-location/location/permissions/runtime (matches GPS-PRIV-005) |
| 3.2 | Android 12+: request `ACCESS_FINE_LOCATION` and `ACCESS_COARSE_LOCATION` together; fine alone is ignored on some releases. The dialog offers Precise or Approximate, then While using the app / Only this time / Deny | FACT | same |
| 3.3 | If only approximate is granted, the app receives approximate location whatever it declares; background accuracy follows the foreground choice | FACT | A/training/location/permissions ; A/.../permissions/background |
| 3.4 | Android 11+: requesting foreground and background location in one request makes the system ignore it and grant neither; background is a separate, later request | FACT | A/.../permissions/runtime |
| 3.5 | Android 11+: the system dialog has no "Allow all the time" button; the user is taken to a settings page. Target-11+ apps should show educational UI with the localized settings label from `getBackgroundPermissionOptionLabel()` and let the user decline and still use the app | FACT | A/.../permissions/background |
| 3.6 | The Android permissions overview defines "foreground" location as access "while a feature is visible or while it runs a foreground service" (service must declare type `location`); "background" is any other access, such as continuous sharing or geofencing | FACT | A/training/location/permissions |
| 3.7 | Consequence for the contract: a `location` foreground service started while the app is visible keeps working with the screen off WITHOUT `ACCESS_BACKGROUND_LOCATION`, per 2.8, 2.9 and 3.6. The fetched pages do not state this in one sentence; the background-location guide's own text on foreground services was not found | INFERENCE (high confidence from 2.8 + 3.6); needs device confirmation | see rows cited |
| 3.8 | Without background permission the app cannot START a location service from the background (2.8). So a restart after a kill with no visible UI cannot resume location without `ACCESS_BACKGROUND_LOCATION` | INFERENCE from 2.8 | A/.../fgs/restrictions-bg-start |
| 3.9 | Downgrading precise to approximate in settings restarts the app process; denial must be handled gracefully | FACT | A/.../permissions/runtime |
| 3.10 | Android 10+: the system may show a reminder notification after background location is used; users can tap it to change the setting | FACT | A/.../permissions/background |
| 3.11 | Android 13+ (targeting 33+): the app controls when the POST_NOTIFICATIONS dialog appears. Apps do NOT need the permission to launch a foreground service, but must still attach a notification. If denied, the notification appears in the Task Manager but not in the drawer | FACT | A/develop/ui/views/notifications/notification-permission |
| 3.12 | Whether the service keeps running after POST_NOTIFICATIONS is denied is implied (permission not needed to launch) but not stated | INFERENCE; NOT_RUN | same |
| 3.13 | Auto-reset of permissions for unused apps: not covered by the pages read | UNKNOWN | - |

INFERENCE, the contract mapping: GPS-PRIV-005 (no prompt at launch) matches 3.1; GPS-PRIV-006 (foreground first) matches 3.4; GPS-PRIV-007 ("background location used only while a recording is active") is satisfiable in two ways that the platform allows: (a) recording by a visible-started foreground service with no background permission at all, or (b) adding `ACCESS_BACKGROUND_LOCATION` requested only at the moment of the first recording. Which one is required is a design decision; (a) shrinks the Play declaration surface (section 4) but gives up unattended restart (3.8).

GPS-PRIV-008 (revocation stops collection at once): the app is told via the permission check or a process restart (3.9); a revocation from system settings while recording is not documented on the pages read as a callback. UNKNOWN; NOT_RUN on a device.

Suggested order (INFERENCE from 3.1-3.11, for the S04-D contract): pre-prompt copy -> foreground location (fine + coarse together) -> POST_NOTIFICATIONS (before the first start, since the strip depends on a visible notification) -> start service from the visible activity -> only if the design needs it, a later separate background request with educational UI.

## 4. Google Play declarations

| # | Claim | Label | Source (read 2026-10-17) |
|---|---|---|---|
| 4.1 | Background location is allowed only for core functionality with significant user benefit; health/fitness is listed among significant benefits; ads and analytics are never acceptable reasons | FACT | P/answer/9799150 |
| 4.2 | Foreground access is preferred; if a feature could work with foreground access, rejection risk rises | FACT | P/answer/9799150 |
| 4.3 | The declaration form (Play Console, App content, Sensitive app permissions, Location permissions) takes ONE location-based feature; multiple features cause rejection; approval covers the whole app | FACT | P/answer/9799150 |
| 4.4 | A video of 30 s or less is required: feature activated from the background, the prominent disclosure dialog, the runtime prompt; recorded from the Android app | FACT | P/answer/9799150 |
| 4.5 | The prominent in-app disclosure is a dialog before the runtime request; it must include the word "location", indicate background use (e.g. "when the app is closed") and list every feature using background location. A privacy policy alone is not sufficient; the policy must be at an active non-PDF URL linked in the app and listing | FACT | P/answer/9799150 |
| 4.6 | Dropping background location requires removing the permission and code from ALL tracks (including closed and open) and rolling a compliant release to 100%. A change to the feature needs a new form | FACT | P/answer/9799150 |
| 4.7 | The page gives no review time or deadline | FACT (absence on the page); real review time UNKNOWN | P/answer/9799150 |
| 4.8 | Separate foreground service declaration (App content): for apps targeting Android 14+, per service type, give the functionality, the user impact if deferred or interrupted, a video of the user starting the feature, and a use case. For `location` the video shows the user starting location sharing, navigation or geofence setup | FACT | P/answer/13392821 |
| 4.9 | The foreground service declaration page lists no deadline for apps updating now other than "types are required when you update to Android 14" | FACT | P/answer/13392821 |
| 4.10 | Rule "declared set equals used set" (GPS-PRIV-011): 4.6 supports it for background location (remove permission, code and all tracks). A rule for foreground service types alone is not on the pages read | FACT for background; UNKNOWN for the rest | P/answer/9799150 |
| 4.11 | Is a `location` foreground service started while the app is visible treated by Play as "background location" needing the form? The Android definition (3.6) treats it as foreground; the Play page does not address this | UNKNOWN; would need Play support or a pre-launch submission | - |

INFERENCE: the app is a fitness tracker, so 4.1 names its category; the form (4.3) still needs one feature statement, e.g. "workout route recording", and the S04 record button video (4.4, 4.8) must exist before submission. Both videos need a physical build: NOT_RUN. Neither declaration blocks internal testing; this is INFERENCE from the fact that the forms are in App content, and was not verified against a Play statement.

## 5. Doze, standby buckets, OEM killers and what survives

| # | Claim | Label | Source (read 2026-10-17) |
|---|---|---|---|
| 5.1 | Doze (API 23+, all apps) starts when the device is unplugged, stationary and screen-off; it suspends network, ignores wake locks, defers standard alarms and JobScheduler/WorkManager | FACT | A/training/monitoring-device-state/doze-standby |
| 5.2 | Doze exits when the user moves the device, turns on the screen or plugs in. A GPS recording is normally while moving | FACT (exit conditions); INFERENCE (a moving user keeps Doze from engaging) | same |
| 5.3 | App Standby: an app is not idle while it has a foreground service or a visible notification; "do not start a foreground service just to prevent the system from determining that your app is idle" | FACT | same |
| 5.4 | Foreground service: exempt from network restrictions, NOT exempt from job and alarm limits by bucket (before Android 16 jobs had no limit during a foreground service, since 16 they do) | FACT | A/topic/performance/power/power-details |
| 5.5 | Buckets: active, working set, frequent, rare, restricted (Android 12+), never. An app with a long-running foreground service counts as active. Restricted bucket exemptions include apps granted `ACCESS_BACKGROUND_LOCATION` | FACT | A/topic/performance/appstandby |
| 5.6 | User can manually restrict battery usage for an app; that overrides bucket limits for jobs/alarms | FACT | A/topic/performance/power/power-details |
| 5.7 | Requesting exemption from battery optimisation (`ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`): Play policy prohibits it "unless the core function of the app is adversely affected"; a fitness tracker is not on the page's list of acceptable examples (safety apps, task automation, companion apps) | FACT (policy text, list); INFERENCE (tracker not listed means a request is a policy risk) | A/training/monitoring-device-state/doze-standby |
| 5.8 | User stop in Task Manager (Android 13+, any target): the system stops the whole app and removes it from memory, removes the notification and sends NO callback; the page does not say the system restarts it; detect on next start with `ApplicationExitInfo` reason `REASON_USER_REQUESTED`. Test with `adb shell cmd activity stop-app PACKAGE` | FACT | A/develop/background-work/services/fgs/handle-user-stopping |
| 5.9 | Swipe-away from recents, low-memory kill and force-stop: behaviour of a foreground service in these cases is NOT described on the pages read | UNKNOWN (official text); NOT_RUN on device | - |
| 5.10 | OEM-specific killers (vendor battery managers): not covered by any official Android page read | UNKNOWN; the community list dontkillmyapp.com is NOT an official source and is excluded | A/topic/performance/power/power-details says OEM restrictions are "not mentioned" |
| 5.11 | `onDestroy()` cannot be relied on for critical work when the process is killed; the fetch summary labelled this "general knowledge", not page text | INFERENCE | A/.../fgs/stop-fgs |
| 5.12 | `START_STICKY` restart after a kill: not documented on the launch page; and by 3.8 a restarted location service may be refused if no visible state exists | UNKNOWN; INFERENCE for the refusal; NOT_RUN | A/.../fgs/launch |

What "restoring after kill" can honestly promise (INFERENCE from 5.8, 5.9, 5.11, 5.12, 3.8; the wording is for the S04-D contract, not a decision):
- The journal holds every sample that was flushed to disk before the kill; samples taken after the last flush and before the kill are lost, as is any gap while no process runs.
- After a user Stop or a kill, nothing runs until the user opens the app; no automatic continuation of tracking is promised on the platform pages read.
- On the next launch the app can detect an unclean end (journal marker; for user stops also `ApplicationExitInfo`) and offer recovery (matches GPS-PRIV-014).
- The distance travelled during a gap is not measured. A straight line across the gap is a presentation choice, not a measurement.
- The design must not claim "survives app kill" for continued recording; it can claim "survives screen off" only after the device test below. The roadmap DoD "survives app kill and screen off" therefore needs the architect to state which of the two meanings applies (see open questions).

## 6. Location API and Flutter-side constraints

Platform facts:

| # | Claim | Label | Source (read 2026-10-17) |
|---|---|---|---|
| 6.1 | Fused provider is `com.google.android.gms:play-services-location`; works only with Google Play services; fallback is the platform `LocationManager` | FACT (summary said the details came from the Play services reference, not the request-updates page) | A/develop/sensors-and-location/location/request-updates |
| 6.2 | `LocationRequest` priorities: HIGH_ACCURACY (highest power), BALANCED_POWER_ACCURACY (about 100 m), LOW_POWER (about 10 km), PASSIVE. Interval, min update interval, max update delay (batching) and min update distance are settable | FACT | same |
| 6.3 | HIGH_ACCURACY needs `ACCESS_FINE_LOCATION`; approximate-only grants give coarse results | FACT | same ; A/training/location/permissions |
| 6.4 | Without a foreground service a background app receives location only "a few times each hour" (Android 8+); a foreground service is the documented route for continuous use | FACT (limit); INFERENCE (service as route, fetch summary labelled it general knowledge) | A/develop/sensors-and-location/location/background |
| 6.5 | Interval, min distance and batching values for walking, running and cycling: no official recommendation exists; these are product numbers to be set by S04-D/architect and measured | UNKNOWN | - |

Flutter facts (docs.flutter.dev/platform-integration/platform-channels, read 2026-10-17):
- FACT: channels can be called from the root isolate or from a background isolate registered through `BackgroundIsolateBinaryMessenger.ensureInitialized(RootIsolateToken)`; platform-side handlers run on the main thread unless a task queue is used.
- FACT: the platform-channel page states no minimum Flutter version; the repo's toolchain is Flutter 3.27.1 / Dart 3.6.0 (`mobile/pubspec.yaml` comment lines 61-62). Whether that comment is still current is UNKNOWN.
- INFERENCE: two shapes exist. (S1) the service logic and the location listener live natively and Dart only starts/stops and reads a journal the native side writes; (S2) a Dart isolate inside the service does the work. S1 survives UI-engine loss better but duplicates journal writing in Kotlin, which collides with the S02 design rule that one Dart repository owns the journal (`S02_DESIGN.md` line 452). S2 keeps one writer but needs the Flutter engine alive in the service process. This tension is a design question, not decided here.
- INFERENCE: plugin-based isolates cannot share object references with the UI isolate (flutter_background_service page states this); data crosses as primitives/maps. A background recorder that writes the journal from its own isolate needs the journal code to be isolate-safe and the single-writer mutex to span isolates. UNKNOWN whether the S02 mutex does.

Candidate packages (no recommendation; every field below was read on the package page on 2026-10-17 unless marked):

| Package | Version / licence / publisher | Maintenance as shown | What the page states | Minimum evidence before it could be chosen |
|---|---|---|---|---|
| `geolocator` | 14.1.1, MIT, baseflow.com (verified); Flutter Favorite | "19 days ago" | Android uses FusedLocationProviderClient with LocationManager fallback; optional `foregroundNotificationConfig` (title, text, wake lock); plugin manifest declares the Android 14 foreground-location permission and merges it; needs compileSdk 35 (repo has 36) | Read its Android manifest and source for the service type it declares; test with screen off 30 min; check what happens after swipe-away; confirm notification channel and permission behaviour on 13+ |
| `location` | 10.0.2, MIT, bernos.dev (verified) | "2 months ago" | `enableBackgroundMode`; foreground notification via `changeNotificationOptions`; manifest needs `ACCESS_BACKGROUND_LOCATION`; page says tracking stops if the user swipes the app away or the OS terminates it; Play services not mentioned | Same device tests; the manifest dependency on background permission would force the Play form (section 4) |
| `flutter_foreground_task` | 11.0.3, MIT, pravera.me (verified) | "about 40 days" | Not a location source. Supports 13 service types including `location`, `serviceTypes` at start, `TaskHandler` in a separate isolate, `autoRunOnBoot`, notification-permission helpers, battery-optimisation request helper; needs Kotlin 2.2.20+ and Gradle 8.11.1+ | Check the repo toolchain against Kotlin/Gradle minimums (UNKNOWN here); decide if a location source is combined with it; Play risk of its battery-exemption helper (5.7) |
| `flutter_background_service` | 5.1.0, MIT, maseka.dev (verified) | "22 months ago" (oldest) | Separate isolate for `onStart`; page says Android 14 needs a type on the `<service>` and gives the location example; lists no supported types | Evidence that it still builds with compileSdk 36 and targets 34+ behaviour; the stale date is a maintenance risk |
| `flutter_background_geolocation` (Transistor Software) | 5.9.0, licence shown inconsistently (Apache-2.0 in sidebar, MIT in footer); commercial: licence required for RELEASE builds on Android and iOS (debug free, 30-day trial) | "7 days ago" | Motion detection, distance filter; headless mode and restart-after-kill are not mentioned on the page | Cost, licence terms and a licence key held outside the repo (cf. signing key practice in `build.gradle` lines 17-40); whether a paid dependency is acceptable is an operator decision |
| Own platform channel (Kotlin `Service` + `FusedLocationProviderClient`) | n/a; code we own | n/a | Full control of service type, notification, flush; requires Kotlin work and an Android reviewer | Cost estimate, test strategy for the native side, journal-writer decision (S1/S2 above) |

Notes on the table (INFERENCE): none of these packages was installed, built or run for this study. "Page states" is the pub.dev text, not verified behaviour. The permission_handler package already in the repo can request location and notification permissions; whether it also covers `ACCESS_BACKGROUND_LOCATION` as a separate step was not read (UNKNOWN; read its pub.dev page before design).

## 7. Not checkable without a device (all NOT_RUN)

1. Location updates continue with screen off for the intended session length (at least 60 min) on the reference phone, and on a second brand if available.
2. Behaviour after swipe-away from recents, after Task Manager Stop (5.8), after force-stop, and after a low-memory kill; whether the service restarts and whether location access is allowed after a restart (5.9, 5.12, 3.8).
3. Whether the notification appears and the service keeps running when POST_NOTIFICATIONS is denied (3.12).
4. Revocation from system settings while recording: whether the app learns of it and how fast (GPS-PRIV-008).
5. Foreground-service start exception on a cold start from a notification tap or from a quick-settings tile (2.7, 2.8).
6. Vendor battery-manager behaviour on the operator's phone (5.10); the reference model is UNKNOWN (readiness doc section 4, item 2). Repo evidence suggests a Samsung S23 Ultra and an S8 have been used (`AndroidManifest.xml` lines 98-116, FACT that those devices appear in comments); whether either is the reference device is UNKNOWN.
7. Battery drain per hour at each priority/interval setting; GPS accuracy under tree cover or city canyons; first-fix time.
8. Play review outcome of the background location and foreground service declarations (section 4), including the videos.
9. Doze entry during a stationary pause (auto-pause) and the effect on sample cadence; test commands from section 5 (`dumpsys deviceidle force-idle`, `am set-inactive`, `cmd activity stop-app`) are documented but were not run.
10. Any claim about packages in section 6, which were read from pub.dev pages only.

## 8. Open questions for the S04 design

| # | Question | Why it matters | Who | Evidence needed |
|---|---|---|---|---|
| Q1 | Is `ACCESS_BACKGROUND_LOCATION` used at all? Option A: no, foreground service started while visible; option B: yes, requested at first recording | A: smaller Play declaration, no OS "all the time" setting step, but no unattended restart (3.8). B: restart possible, but the Play form, video, disclosure dialog and reminder notification apply (4.3-4.6) | architect, operator | Device test of 3.7; Play support answer for 4.11 |
| Q2 | What does the DoD "survives app kill" mean: continued recording, or journal recovery on next launch? | Platform text supports only the second (section 5) | operator, product-owner | Device tests 2 and 3 in section 7 |
| Q3 | Single journal writer in Dart (S2) or a native writer (S1)? | S02 design rule vs resilience to engine loss (section 6) | architect | Package source read; isolate-safe mutex check |
| Q4 | Which location source: maintained package, own channel, or paid package? | Section 6 table; licence cost and Play surface differ | architect, operator for cost | The minimum-evidence column of the table |
| Q5 | Sample interval, accuracy priority, min distance per sport | No official recommendation (6.5); drives battery protocol | architect, product-owner | Battery test on the reference phone |
| Q6 | Is a battery-optimisation exemption requested? | Play policy risk (5.7) vs the OEM-killer risk (5.10) | architect, operator | Reference-phone behaviour without exemption |
| Q7 | When is POST_NOTIFICATIONS asked, and what does the recorder do if it is denied? | 3.11, 3.12; strip needs a visible notification | ui-designer (S04-D) | Device test 3 |
| Q8 | Which reference phone and Android version, and is a second brand available? | All of section 7 | operator | A named model and date |
| Q9 | Does the installed toolchain meet the package minimums (Kotlin, Gradle, compileSdk)? | `flutter_foreground_task` needs Kotlin 2.2.20+, Gradle 8.11.1+; others compileSdk 35 | architect | Read `mobile/android` Gradle files and the toolchain versions (not done here) |
| Q10 | Who writes the Play declaration videos and the prominent disclosure text, and when? | Sections 4.4, 4.5, 4.8; needs a build and approved wording (GPS-PRIV-010) | technical-writer, operator | Final design |
| Q11 | iOS: Android only for S04? | Readiness doc G12; no iOS project in the repo | operator | Already an operator decision item |
