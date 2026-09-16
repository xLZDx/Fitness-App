import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Backlog row 25: `server_export.dart` called `FirebaseFunctions.instance`
/// instead of the project's `functionsForRegion` helper, defaulting to the
/// SDK's region (`us-central1`) while every deployed callable lives in
/// `europe-west1` (`functions_region.dart`'s own `kFunctionsRegion`). That
/// mismatch does not fail at build time -- it fails at call time, as
/// `NOT_FOUND` on every invocation, because the SDK builds the endpoint URL
/// from the region. Nine other services already went through the same
/// region-mismatch bug and were fixed to use `functionsForRegion`; this file
/// was the one left behind because nothing tied the ten call sites together.
///
/// A source scan, not a unit test of `functionsForRegion` itself: that
/// getter calls `FirebaseFunctions.instanceFor`, which requires
/// `Firebase.initializeApp` to have already run, so it cannot be exercised
/// in a plain `flutter_test` unit test without a full Firebase test harness.
/// What CAN be checked without one is the actual defect class -- a bare,
/// unpinned `FirebaseFunctions.instance` anywhere in the app -- which is
/// exactly what silently reintroduces the `NOT_FOUND` failure the first time.
void main() {
  test('no file under lib/ calls the unpinned FirebaseFunctions.instance', () {
    // The suite runs with `mobile/` as its working directory.
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'expected to run from mobile/');

    final offenders = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final src = entity
          .readAsStringSync()
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      // `.instance` word-bounded so this never flags `.instanceFor`, which is
      // the correct, region-pinned call `functionsForRegion` itself makes.
      if (RegExp(r'FirebaseFunctions\.instance\b(?!For)').hasMatch(src)) {
        offenders.add(entity.path);
      }
    }

    expect(offenders, isEmpty,
        reason: 'these files call FirebaseFunctions.instance directly, which '
            'defaults to the wrong region and fails every callable with '
            'NOT_FOUND at runtime -- inject functionsForRegion '
            "(core/firebase/functions_region.dart) as the fallback instead: "
            '${offenders.join(', ')}');
  });
}
