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
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('bundled assets', () {
    test('the exercise catalog is packaged and parses', () async {
      final raw = await rootBundle.loadString('assets/data/exercises.json');
      final items = json.decode(raw) as List<dynamic>;
      expect(items, isNotEmpty);
    });

    test('the equipment catalog is packaged and parses', () async {
      final raw = await rootBundle.loadString('assets/data/equipment.json');
      expect(json.decode(raw), isA<List<dynamic>>());
    });

    test('every exercise declares at least two demo frames', () async {
      final raw = await rootBundle.loadString('assets/data/exercises.json');
      final items = (json.decode(raw) as List<dynamic>)
          .cast<Map<String, dynamic>>();

      final short = <String>[];
      for (final e in items) {
        final frames = (e['frames'] as List<dynamic>? ?? const []);
        if (frames.length < 2) short.add(e['id'] as String);
      }
      expect(short, isEmpty,
          reason: 'a single frame cannot animate — the demo needs start+end');
    });

    test('every declared demo frame is really in the bundle', () async {
      final raw = await rootBundle.loadString('assets/data/exercises.json');
      final items = (json.decode(raw) as List<dynamic>)
          .cast<Map<String, dynamic>>();

      final paths = <String>{
        for (final e in items)
          ...(e['frames'] as List<dynamic>? ?? const []).cast<String>(),
      };
      expect(paths, hasLength(132),
          reason: 'guards against the catalog silently shrinking');

      final missing = <String>[];
      final empty = <String>[];
      for (final p in paths) {
        try {
          final bytes = await rootBundle.load(p);
          if (bytes.lengthInBytes == 0) empty.add(p);
        } on FlutterError {
          missing.add(p);
        }
      }

      expect(missing, isEmpty,
          reason: 'declared in exercises.json but not packaged — this is the '
              '"Demo unavailable" bug. Check that pubspec covers the '
              'directory these files actually live in; directory entries do '
              'not recurse.');
      expect(empty, isEmpty, reason: 'packaged but zero bytes');
    });

    test('frame paths are flat, not nested in per-exercise folders', () async {
      final raw = await rootBundle.loadString('assets/data/exercises.json');
      final items = (json.decode(raw) as List<dynamic>)
          .cast<Map<String, dynamic>>();

      final nested = <String>[];
      for (final e in items) {
        for (final p in (e['frames'] as List<dynamic>? ?? const [])) {
          // assets/exercises/<file> is 3 segments; a 4th means a subdirectory,
          // which the pubspec entry would not cover.
          if ((p as String).split('/').length != 3) nested.add(p);
        }
      }
      expect(nested, isEmpty,
          reason: 'nested frames are excluded from the bundle by pubspec');
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
