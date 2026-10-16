/// Shared sampling helpers of the pure GPX and FIT encoders (S02 design 7).
/// Pure Dart, no Flutter or dart:io imports.
library;

import 'sample_stream.dart';

/// How far (ms) a non-GPS sample may be from a route point and still belong to
/// it. Heart rate, altitude and speed are usually sampled at 1 Hz, so a point
/// without a sample inside the window simply carries no value.
const int kExportSampleToleranceMs = 5000;

/// The value of a non-GPS [stream] nearest to [offsetMs], or null when the
/// stream is null/empty or no sample lies within [toleranceMs]. O(log n).
double? nearestStreamValue(
  SampleStream? stream,
  int offsetMs, {
  int toleranceMs = kExportSampleToleranceMs,
}) {
  if (stream == null || stream.isEmpty || stream.values.length != stream.length) {
    return null;
  }
  final offsets = stream.offsetsMs;
  var lo = 0;
  var hi = offsets.length - 1;
  // First index whose offset is >= offsetMs.
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (offsets[mid] < offsetMs) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  var best = lo;
  if (lo > 0 && (offsetMs - offsets[lo - 1]).abs() <= (offsets[lo] - offsetMs).abs()) {
    best = lo - 1;
  }
  final delta = (offsets[best] - offsetMs).abs();
  if (delta > toleranceMs) return null;
  final v = stream.values[best];
  return v.isFinite ? v : null;
}
