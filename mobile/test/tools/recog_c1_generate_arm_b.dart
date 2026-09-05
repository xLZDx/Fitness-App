// RECOG-C1 step 1 — generate the Arm-B (viewfinder-cropped) inputs.
//
// Plan fitness_app-2026-09-05T11-25-16-919Z-377ee0, hash b78bffa5...
// Not a test. Named without the `_test.dart` suffix on purpose, so a plain
// `flutter test` run never collects it and never rewrites the corpus. Run it
// explicitly:
//
//   flutter test test/tools/recog_c1_generate_arm_b.dart
//
// Paths and the viewport come from the environment so nothing about one
// machine's layout is baked into the committed source:
//
//   RECOG_C1_SRC   directory holding the original photographs (read-only)
//   RECOG_C1_WORK  working directory this writes into
//   RECOG_C1_VW    viewfinder card width  in logical pixels
//   RECOG_C1_VH    viewfinder card height in logical pixels
//
// Why it runs under `flutter test` rather than as a plain `dart run`: the
// production crop is `cropToViewfinder`, which needs dart:ui's `Rect`/`Size`
// and `compute`. Running it here means Arm B is produced BY THE PRODUCTION
// FUNCTION, not by a re-implementation of it that could quietly drift — the
// plan's verification (d) rests on that.
//
// Deterministic by construction: same originals + same viewport => same
// bytes, because every step (EXIF bake, cover-fit inverse, `copyCrop`,
// `encodeJpg(quality: 88)`) is the fixed production path. The manifest
// records the sha256 of both arms so the claim is checkable rather than
// asserted.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:fitness_app/core/camera/centre_crop.dart';
import 'package:fitness_app/features/scanner/widgets/scan_viewfinder.dart';

String _env(String name) {
  final v = Platform.environment[name];
  if (v == null || v.trim().isEmpty) {
    throw StateError('$name is not set; see the header of this file');
  }
  return v.trim();
}

String _sha256OfFile(File f) => sha256.convert(f.readAsBytesSync()).toString();

/// CSV escaping: every field is quoted, so a path containing a comma or a
/// quote cannot silently shift a column.
String _csv(List<Object?> cells) =>
    cells.map((c) => '"${'$c'.replaceAll('"', '""')}"').join(',');

void main() {
  // `cropToViewfinder` runs `compute`, which needs the binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generate Arm-B viewfinder crops', () async {
    final srcDir = Directory(_env('RECOG_C1_SRC'));
    final workDir = Directory(_env('RECOG_C1_WORK'));
    final double vw = double.parse(_env('RECOG_C1_VW'));
    final double vh = double.parse(_env('RECOG_C1_VH'));
    final Size viewport = Size(vw, vh);
    final Rect window = ScanViewfinder.windowNormalized(viewport);

    expect(srcDir.existsSync(), isTrue, reason: '${srcDir.path} must exist');

    final armA = Directory('${workDir.path}/arm_a')..createSync(recursive: true);
    final armB = Directory('${workDir.path}/arm_b')..createSync(recursive: true);

    final sources = srcDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.jpg'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    // ignore: avoid_print
    print('viewport ${vw}x$vh  window $window  sources ${sources.length}');

    final rows = <String>[
      _csv(const [
        'index',
        'source_file',
        'image_id_sha256_original',
        'original_w',
        'original_h',
        'baked_w',
        'baked_h',
        'crop_left',
        'crop_top',
        'crop_right',
        'crop_bottom',
        'crop_w',
        'crop_h',
        'arm_b_sha256',
        'arm_b_bytes',
      ]),
    ];

    for (var i = 0; i < sources.length; i++) {
      final src = sources[i];
      final name = src.uri.pathSegments.last;

      // Arm A is the untouched original, copied so the corpus directory is
      // never written to and both arms hash from files this run owns.
      final aFile = File('${armA.path}/$name');
      aFile.writeAsBytesSync(src.readAsBytesSync(), flush: true);
      final imageId = _sha256OfFile(aFile);

      // The crop rect, from the PRODUCTION function, against the EXIF-baked
      // size — the same orientation `_cropWindow` bakes before cropping.
      final decodedRaw = img.decodeImage(aFile.readAsBytesSync());
      expect(decodedRaw, isNotNull, reason: 'could not decode $name');
      final baked = img.bakeOrientation(decodedRaw!);
      final rect = viewfinderSourceRect(
        Size(baked.width.toDouble(), baked.height.toDouble()),
        viewport,
        window,
      );

      final outPath = await cropToViewfinder(
        aFile.path,
        viewport: viewport,
        windowNormalized: window,
      );
      // `cropToViewfinder` is fail-open: on any failure it returns the INPUT
      // path. A silently uncropped Arm B would be the whole comparison
      // measuring nothing, so this is a stop, not a warning.
      expect(outPath, isNot(aFile.path), reason: 'crop failed for $name');

      final cropped = File(outPath);
      final bFile = File('${armB.path}/$name');
      bFile.writeAsBytesSync(cropped.readAsBytesSync(), flush: true);
      cropped.deleteSync();

      rows.add(_csv([
        i,
        name,
        imageId,
        decodedRaw.width,
        decodedRaw.height,
        baked.width,
        baked.height,
        rect.left.round(),
        rect.top.round(),
        rect.right.round(),
        rect.bottom.round(),
        rect.right.round() - rect.left.round(),
        rect.bottom.round() - rect.top.round(),
        _sha256OfFile(bFile),
        bFile.lengthSync(),
      ]));

      // ignore: avoid_print
      print('[${i + 1}/${sources.length}] $name  baked ${baked.width}x'
          '${baked.height}  crop ${rect.width.round()}x${rect.height.round()}');
    }

    final manifest = File('${workDir.path}/recog_c1_arm_manifest.csv');
    manifest.writeAsStringSync('${rows.join('\n')}\n');

    // ignore: avoid_print
    print('manifest: ${manifest.path}');
    // ignore: avoid_print
    print('manifest sha256: ${_sha256OfFile(manifest)}');
    // ignore: avoid_print
    print('viewport_recorded: ${vw}x$vh  '
        'window_normalized: ${jsonEncode({
          'left': window.left,
          'top': window.top,
          'right': window.right,
          'bottom': window.bottom,
        })}');
  }, timeout: const Timeout(Duration(minutes: 30)));
}
