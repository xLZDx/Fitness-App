import 'dart:convert';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards what actually ends up INSIDE the app bundle.
///
/// Why this file exists: 66 exercises shipped with correct frame paths in
/// `exercises.json` and all 132 image files present on disk, yet every demo
/// rendered "Demo unavailable" on device. The pubspec declared
/// `- assets/exercises/`, and a Flutter directory entry covers only the files
/// sitting directly in that directory — it does not recurse. The frames lived
/// one level down, so none of them were packaged.
///
/// 487 unit and widget tests were green throughout: none of them touched the
/// bundle. `rootBundle` under `flutter test` resolves through the real asset
/// manifest, so these assertions fail for exactly the reason the device did.
///
/// The catalog and the frames that caused the original bug were removed on
/// 2026-08-04. The bug CLASS did not go anywhere: `assets/posters/girl/` and
/// `assets/posters/men/` are two more non-recursive directory entries, and
/// 2,539 posters are what makes the first frame of every clip instant and
/// offline. These assertions moved onto them rather than being deleted with
/// the files that happened to expose the problem first.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('bundled assets', () {
    test('the exercise catalog is packaged and parses', () async {
      final raw =
          await rootBundle.loadString('assets/data/exercises_vendor.json');
      final items = json.decode(raw) as List<dynamic>;
      expect(items, isNotEmpty);
    });

    test('the equipment catalog is packaged and parses', () async {
      final raw = await rootBundle.loadString('assets/data/equipment.json');
      expect(json.decode(raw), isA<List<dynamic>>());
    });

    test('every declared poster is really in the bundle', () async {
      // The original bug in one sentence: declared in the catalog, present on
      // disk, absent from the bundle. Nothing but the bundle itself catches
      // it, and a poster that is not packaged is a card that shows a spinner
      // until the network answers — on a screen whose whole point is that it
      // does not have to.
      //
      // Read through the asset MANIFEST rather than loading each file: 2,539
      // `rootBundle.load` calls blew the 30s test timeout, and the manifest
      // answers the same question ("is this packaged?") for every one of them
      // at once instead of sampling and hoping.
      final raw =
          await rootBundle.loadString('assets/data/exercises_vendor.json');
      final items =
          (json.decode(raw) as List<dynamic>).cast<Map<String, dynamic>>();

      final paths = <String>{
        for (final e in items)
          ...((e['poster'] as Map<String, dynamic>? ?? const {})
              .values
              .cast<String>()),
      };
      expect(paths.length, greaterThanOrEqualTo(2500),
          reason: 'guards against the catalog silently shrinking');

      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final packaged = manifest.listAssets().toSet();
      final missing = paths.difference(packaged).toList()..sort();

      expect(missing, isEmpty,
          reason: '${missing.length} posters are declared in the catalog but '
              'not packaged. Check that pubspec covers the directory these '
              'files actually live in; directory entries do not recurse.');
    });

    test('poster paths are flat, not nested in per-exercise folders', () async {
      final raw =
          await rootBundle.loadString('assets/data/exercises_vendor.json');
      final items =
          (json.decode(raw) as List<dynamic>).cast<Map<String, dynamic>>();

      final nested = <String>[];
      for (final e in items) {
        for (final p in (e['poster'] as Map<String, dynamic>? ?? const {})
            .values
            .cast<String>()) {
          // assets/posters/<body>/<file> is 4 segments; a 5th means a
          // subdirectory, which the pubspec entry would not cover.
          if (p.split('/').length != 4) nested.add(p);
        }
      }
      expect(nested, isEmpty,
          reason: 'nested posters are excluded from the bundle by pubspec');
    });

    test('the catalog the app removed is really gone from the bundle',
        () async {
      // Deleting the files is not the same as un-shipping them: a stale entry
      // in the asset manifest, or a copy left in another declared directory,
      // would keep 1.3 MB of dead JSON in the APK and let a future call site
      // quietly load a catalog nobody maintains any more.
      for (final gone in const [
        'assets/data/exercises.json',
        'assets/data/exercises.ru.json',
      ]) {
        await expectLater(
          rootBundle.loadString(gone),
          throwsA(isA<FlutterError>()),
          reason: '$gone is still packaged',
        );
      }
    });

    test('the equipment recognition model is packaged', () async {
      final bytes =
          await rootBundle.load('assets/models/equipment_v1.tflite');
      expect(bytes.lengthInBytes, greaterThan(1000000),
          reason: 'equipment_v1.tflite is ~4.3 MB; a tiny file means the '
              'placeholder got shipped instead of the trained model');
    });
  });
}
