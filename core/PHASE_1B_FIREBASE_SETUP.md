# Phase 1B — Firebase setup (one-time)

This is the user-facing checklist to swap the in-memory mocks for the real Firebase backend. After it's done, no UI code changes — only a couple of provider overrides in `main.dart` flip.

---

## 1. Create the Firebase project

1. Go to <https://console.firebase.google.com> and sign in with the Google account you want as the project owner.
2. **Add project** → name it whatever you like (e.g. `fitness-app-prod`). Disable Google Analytics for now if asked (we can add it later).

## 2. Enable Auth and Firestore

In the Firebase console:

1. **Build → Authentication → Get started**
   - Sign-in providers tab → enable **Email/Password** and **Anonymous**.
   - For Google sign-in: enable **Google** as a provider too. Note the **Web SDK configuration** Web client ID — we'll need it for Android.
2. **Build → Firestore Database → Create database**
   - Production mode (we'll lock it down with rules).
   - Pick the region closest to your users (cannot be changed later).

## 3. Add the Android app

1. Project overview → **Add app → Android**.
2. Android package name: `com.fitnessapp.fitness_app.sptr` (must match exactly).
3. App nickname: `Fitness App (Android)`.
4. **Debug signing certificate SHA-1**: open a terminal and run:
   ```powershell
   cd "D:\test 2\Fitness App\mobile"
   $env:JAVA_HOME = "C:\Program Files\Microsoft\jdk-17.0.18.8-hotspot"
   & "$env:JAVA_HOME\bin\keytool.exe" -list -v `
       -keystore "$env:USERPROFILE\.android\debug.keystore" `
       -alias androiddebugkey `
       -storepass android -keypass android
   ```
   Copy the **SHA1** fingerprint into the Firebase form.
5. Download the generated `google-services.json` and put it at:
   ```
   D:\test 2\Fitness App\mobile\android\app\google-services.json
   ```
   (already in `.gitignore`, will not be committed)

## 4. Configure Flutter ↔ Firebase

Install the Firebase tooling — both go into `D:\.pub-cache` because `PUB_CACHE` is set there:

```powershell
$env:Path = "$env:Path;D:\flutter\bin;D:\.pub-cache\bin"
$env:PUB_CACHE = "D:\.pub-cache"
dart pub global activate flutterfire_cli
```

Install Firebase CLI itself (Node-based). To keep it off C:, use a portable Node setup or:

```powershell
# Tell npm to install globals on D:
npm config set prefix "D:\npm-global"
$env:Path = "D:\npm-global;$env:Path"
npm install -g firebase-tools
firebase login
```

Then from the project:

```powershell
cd "D:\test 2\Fitness App\mobile"
flutterfire configure
```

This generates `lib/firebase_options.dart` with the right config for Android (and any other platforms you select).

## 5. Flip the providers

Open `D:\test 2\Fitness App\mobile\lib\main.dart` and change `runApp` to initialise Firebase + override the two repository providers:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'features/auth/data/firebase_auth_repository.dart';
import 'features/auth/state/auth_providers.dart';
import 'features/profile/data/firestore_profile_repository.dart';
import 'features/profile/state/profile_providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWith((_) => FirebaseAuthRepository()),
      profileRepositoryProvider.overrideWith((_) => FirestoreProfileRepository()),
    ],
    child: const FitnessApp(),
  ));
}
```

Done. The whole app now runs against real Firebase; mocks remain for tests via per-test overrides.

## 6. Lock down Firestore

Drop these rules at `firestore.rules` and deploy with `firebase deploy --only firestore:rules`:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{uid}/{document=**} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
    // Future: equipment / exercise catalogs are read-only for clients
    match /equipment/{anyId} {
      allow read: if request.auth != null;
      allow write: if false;
    }
    match /exercises/{anyId} {
      allow read: if request.auth != null;
      allow write: if false;
    }
  }
}
```

## 7. Smoke test

1. `flutter run` on the emulator.
2. Sign in with Continue → email/password / Google as appropriate.
3. Step through the questionnaire. Check the Firestore console — `users/{uid}/profile/main` should appear with all the fields.
4. Force-quit the app, relaunch, sign in same account: data should round-trip.

## 8. Already prepared in code

These files are already written and ready to be wired up; you don't need to author them:

- `mobile/lib/features/auth/data/firebase_auth_repository.dart` — `FirebaseAuthRepository`
- `mobile/lib/features/profile/data/firestore_profile_repository.dart` — `FirestoreProfileRepository`
- `pubspec.yaml` — `firebase_core`, `firebase_auth`, `cloud_firestore` already added.
