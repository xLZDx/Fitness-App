# Emulator captures — the other half of §30

The sibling `../prototype/` folder holds what the app is *supposed* to look
like. This folder holds what it *does* look like, captured from a real build
on a real device, so a gate can be closed against a pair of pictures.

§30 of the master prompt asks for exactly that pair — capture an emulator
screenshot, compare it against the reference, record the deviations. It was
never executed once across R1–R11. `f2_home_2026-08-09.png` is the first
time it was.

## What is here

| File | Build | Compare against |
|---|---|---|
| `f2_home_2026-08-09.png` | Ф2, release APK (`--target-platform android-x64`) on `Pixel_API_34`, 320×640 | `../prototype/p_162.jpg` |

## How to take one

The app on the emulator is **release-signed**, so a debug APK will not install
over it (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`). Build release for the
emulator's own ABI instead of uninstalling — an uninstall wipes the logged-in
session, and without a session there is no screen to photograph.

```bash
flutter build apk --release --target-platform android-x64
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb shell am force-stop com.fitnessapp.fitness_app.sptr
adb shell monkey -p com.fitnessapp.fitness_app.sptr -c android.intent.category.LAUNCHER 1

# Capture through a file on the device. `adb exec-out screencap -p > out.png`
# corrupts the PNG under PowerShell, which encodes the redirected stream as
# text.
adb shell screencap -p /sdcard/shot.png
adb pull /sdcard/shot.png . && adb shell rm /sdcard/shot.png
```

## Deviations recorded for Ф2

Structure matches the reference: flat full-width bar, top hairline, the Scan
tab lifted into a circle that breaks that hairline, accent-coloured active
tab, five single-line labels.

Three deliberate divergences, all argued in `core/DECISION_LOG.md`:

1. **Inactive tabs are brighter than the prototype's.** Its `#3E3E50` scores
   1.96:1 on the bar — an interactive control below any legibility bar. The
   token `textSecondary` is used instead, at 9.27:1.
2. **Workouts and Profile keep meaningful icons.** The prototype's `◈` and
   `○` are Figma Make placeholders, not designed glyphs.
3. **The Scan label sits ~4px below its neighbours.** Not a defect — the same
   arithmetic the prototype's own `marginTop: -18` produces, and its own
   frames show it too.

One measured observation, not a divergence: this emulator is 320dp wide, so a
tab is 64dp and "Тренировки"/"Прогресс" nearly touch. They do not wrap or
ellipsise. The prototype's viewport is ~390dp, where the gaps are visible;
phones at 360dp+ have the room.
