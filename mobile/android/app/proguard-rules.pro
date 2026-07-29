# App-level R8/ProGuard rules.
#
# tflite_flutter references the TFLite GPU delegate, but the GPU delegate
# AAR is not bundled (we run CPU inference only). R8 fails the release
# build on the dangling reference without this suppression — rule text
# taken verbatim from R8's generated missing_rules.txt.
-dontwarn org.tensorflow.lite.gpu.GpuDelegateFactory$Options
-dontwarn org.tensorflow.lite.gpu.**
