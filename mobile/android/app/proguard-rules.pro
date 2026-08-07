# App-level R8/ProGuard rules.
#
# Every rule here is a -dontwarn for a class that is REFERENCED but not
# BUNDLED. R8 treats a dangling reference as a hard error, so each of these
# is load-bearing: delete one and `flutter build apk --release` fails.
#
# Rule text is copied verbatim from R8's own missing_rules.txt
# (mobile/build/app/outputs/mapping/release/missing_rules.txt) rather than
# written by hand. A hand-typed rule that is subtly wrong suppresses nothing
# and the build fails identically 6 minutes later.
#
# --- TFLite GPU delegate --------------------------------------------------
#
# The delegate AAR is not bundled; inference is CPU-only. Originally added
# for tflite_flutter, which was REMOVED on 2026-08-07 (unused, 7.2 MB of
# native code per ABI). The rule stays because google_mlkit_image_labeling
# embeds TFLite itself -- whether the reference survived the removal is
# unverified, and a needless -dontwarn costs nothing while a missing one
# costs a failed build.
-dontwarn org.tensorflow.lite.gpu.GpuDelegateFactory$Options
-dontwarn org.tensorflow.lite.gpu.**

# --- ML Kit text recognition, non-latin scripts ---------------------------
#
# google_mlkit_text_recognition's Android plugin has a single initialize()
# that can construct a recogniser for any of five scripts. We depend only on
# the latin artifact (TextRecognitionScript.latin, machine_text_anchor reads
# equipment decals), so the other four Options classes are referenced by that
# switch statement and never present.
#
# Adding the other artifacts instead would grow the APK for scripts no
# equipment decal in the catalogue uses.
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
