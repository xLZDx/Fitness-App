// C24 image_prep_test (FOOD-15 label photo preparation, FOOD-07 client half,
// PRIV-19): prepareJpeg resizes to the long edge (1024 px meal, 1280 px label,
// 256 px thumbnail), never enlarges, bakes the EXIF orientation into the
// pixels, and re-encodes from raw pixels so no EXIF / GPS / ICC segment
// survives. Undecodable input and an over-3 MB result both give null.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fitness_app/features/food_diary/state/image_prep.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A [w] x [h] image whose left half is red and right half is blue.
img.Image _halves(int w, int h) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(0, 0, 255));
  img.fillRect(image,
      x1: 0, y1: 0, x2: w ~/ 2 - 1, y2: h - 1, color: img.ColorRgb8(255, 0, 0));
  return image;
}

Uint8List _jpg(img.Image image) =>
    Uint8List.fromList(img.encodeJpg(image, quality: 95));

img.Image _decode(Uint8List bytes) {
  final d = img.decodeJpg(bytes);
  expect(d, isNotNull, reason: 'output must be a decodable JPEG');
  return d!;
}

/// Marker bytes (second byte of FFxx) of every header segment before the scan.
List<int> _markers(Uint8List b) {
  expect(b[0], 0xFF);
  expect(b[1], 0xD8, reason: 'JPEG SOI');
  final out = <int>[];
  var i = 2;
  while (i + 3 < b.length) {
    if (b[i] != 0xFF) break;
    final m = b[i + 1];
    out.add(m);
    if (m == 0xDA) break; // start of scan: header is over
    final len = (b[i + 2] << 8) | b[i + 3];
    i += 2 + len;
  }
  return out;
}

bool _containsAscii(Uint8List b, String needle) {
  final n = needle.codeUnits;
  for (var i = 0; i + n.length <= b.length; i++) {
    var ok = true;
    for (var j = 0; j < n.length; j++) {
      if (b[i + j] != n[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return true;
  }
  return false;
}

void main() {
  group('constants (design s17.2, s17.6)', () {
    test('long edges and the byte cap', () {
      expect(kMealLongEdge, 1024);
      expect(kLabelLongEdge, 1280);
      expect(kMealThumbLongEdge, 256);
      expect(kPreparedMaxBytes, 3 * 1024 * 1024);
    });
  });

  group('resize to the long edge', () {
    test('meal landscape 3000x2000 -> width 1024, height keeps the ratio', () {
      final out = prepareJpeg(_jpg(_halves(3000, 2000)), longEdge: kMealLongEdge);
      final d = _decode(out!);
      expect(d.width, 1024);
      expect(d.height, inInclusiveRange(682, 683)); // 2000 * 1024 / 3000
    });

    test('meal portrait 2000x3000 -> height 1024, width keeps the ratio', () {
      final out = prepareJpeg(_jpg(_halves(2000, 3000)), longEdge: kMealLongEdge);
      final d = _decode(out!);
      expect(d.height, 1024);
      expect(d.width, inInclusiveRange(682, 683));
    });

    test('label long edge is 1280, not 1024', () {
      final src = _jpg(_halves(3000, 2000));
      final label = _decode(prepareJpeg(src, longEdge: kLabelLongEdge)!);
      final meal = _decode(prepareJpeg(src, longEdge: kMealLongEdge)!);
      expect(label.width, 1280);
      expect(label.height, inInclusiveRange(853, 854)); // 2000 * 1280 / 3000
      expect(meal.width, 1024);
    });

    test('thumbnail long edge is 256', () {
      final d = _decode(
          prepareJpeg(_jpg(_halves(1024, 768)), longEdge: kMealThumbLongEdge)!);
      expect(d.width, 256);
      expect(d.height, 192);
    });

    test('square image -> both sides at the long edge', () {
      final d = _decode(
          prepareJpeg(_jpg(_halves(2000, 2000)), longEdge: kMealLongEdge)!);
      expect(d.width, 1024);
      expect(d.height, 1024);
    });

    test('exactly at the long edge is left as it is', () {
      final d = _decode(
          prepareJpeg(_jpg(_halves(1024, 600)), longEdge: kMealLongEdge)!);
      expect(d.width, 1024);
      expect(d.height, 600);
    });

    test('one pixel over the long edge is resized', () {
      final d = _decode(
          prepareJpeg(_jpg(_halves(1025, 600)), longEdge: kMealLongEdge)!);
      expect(d.width, 1024);
    });

    test('a smaller image is never enlarged', () {
      final d = _decode(
          prepareJpeg(_jpg(_halves(500, 300)), longEdge: kMealLongEdge)!);
      expect(d.width, 500);
      expect(d.height, 300);
    });

    test('resizing keeps the picture (left stays red, right stays blue)', () {
      final d = _decode(
          prepareJpeg(_jpg(_halves(2000, 1000)), longEdge: kMealLongEdge)!);
      final left = d.getPixel(d.width ~/ 4, d.height ~/ 2);
      final right = d.getPixel(3 * d.width ~/ 4, d.height ~/ 2);
      expect(left.r, greaterThan(200));
      expect(left.b, lessThan(60));
      expect(right.b, greaterThan(200));
      expect(right.r, lessThan(60));
    });

    test('output is always a JPEG, also for a PNG source', () {
      final png = Uint8List.fromList(img.encodePng(_halves(1600, 800)));
      final out = prepareJpeg(png, longEdge: kMealLongEdge)!;
      expect(out[0], 0xFF);
      expect(out[1], 0xD8);
      expect(_decode(out).width, 1024);
    });
  });

  group('EXIF orientation is baked into the pixels', () {
    test('orientation 6 (90 degrees clockwise) turns a landscape into a portrait',
        () {
      final src = _halves(200, 100);
      src.exif.imageIfd.orientation = 6;
      final input = _jpg(src);
      // Baseline: the source really carries the tag, so the test is not vacuous.

      final d = _decode(prepareJpeg(input, longEdge: kMealLongEdge)!);
      expect(d.width, 100, reason: 'width and height swap');
      expect(d.height, 200);
      // Rotating 90 deg clockwise moves the red left half to the top.
      final top = d.getPixel(50, 50);
      final bottom = d.getPixel(50, 150);
      expect(top.r, greaterThan(200));
      expect(top.b, lessThan(60));
      expect(bottom.b, greaterThan(200));
      expect(bottom.r, lessThan(60));
    });

    test('orientation 3 (180 degrees) swaps left and right', () {
      final src = _halves(200, 100);
      src.exif.imageIfd.orientation = 3;
      final d = _decode(prepareJpeg(_jpg(src), longEdge: kMealLongEdge)!);
      expect(d.width, 200);
      expect(d.height, 100);
      final left = d.getPixel(50, 50);
      final right = d.getPixel(150, 50);
      expect(left.b, greaterThan(200), reason: 'blue is now on the left');
      expect(right.r, greaterThan(200), reason: 'red is now on the right');
    });

    test('no orientation tag stays unrotated', () {
      final d = _decode(prepareJpeg(_jpg(_halves(200, 100)), longEdge: 1024)!);
      expect(d.width, 200);
      expect(d.height, 100);
      expect(d.getPixel(50, 50).r, greaterThan(200));
    });

    test('orientation is applied before the resize decision', () {
      // 3000x1000 rotated to 1000x3000: the long edge is now the height.
      final src = _halves(3000, 1000);
      src.exif.imageIfd.orientation = 6;
      final d = _decode(prepareJpeg(_jpg(src), longEdge: kMealLongEdge)!);
      expect(d.height, 1024);
      expect(d.width, inInclusiveRange(341, 342));
    });

    test('the output carries no orientation tag (it would rotate twice)', () {
      final src = _halves(200, 100);
      src.exif.imageIfd.orientation = 6;
      final d = _decode(prepareJpeg(_jpg(src), longEdge: kMealLongEdge)!);
      expect(d.exif.imageIfd.hasOrientation, isFalse);
    });
  });

  group('no metadata survives (EXIF, GPS, ICC)', () {
    test('EXIF block with make, software and GPS is gone', () {
      final src = _halves(400, 300);
      src.exif.imageIfd.make = 'SecretCamMaker';
      src.exif.imageIfd.software = 'SecretSoftware';
      src.exif.gpsIfd.gpsLatitude = 51.5;
      src.exif.gpsIfd.gpsLongitude = -0.12;
      final input = _jpg(src);

      // Baseline: the source has an APP1 segment with the strings.
      expect(_markers(input), contains(0xE1));
      expect(_containsAscii(input, 'SecretCamMaker'), isTrue);

      final out = prepareJpeg(input, longEdge: kMealLongEdge)!;
      expect(_markers(out), isNot(contains(0xE1)), reason: 'no APP1/EXIF');
      expect(_containsAscii(out, 'SecretCamMaker'), isFalse);
      expect(_containsAscii(out, 'SecretSoftware'), isFalse);
      expect(_containsAscii(out, 'Exif'), isFalse);
      final d = _decode(out);
      expect(d.exif.isEmpty, isTrue);
      expect(d.exif.gpsIfd.isEmpty, isTrue);
    });

    test('an ICC profile is gone', () {
      final src = _halves(400, 300);
      src.iccProfile = img.IccProfile(
          'SecretProfile', img.IccProfileCompression.none, Uint8List(128));
      final input = _jpg(src);
      expect(_markers(input), contains(0xE2), reason: 'baseline: APP2 present');

      final out = prepareJpeg(input, longEdge: kMealLongEdge)!;
      expect(_markers(out), isNot(contains(0xE2)));
      expect(_containsAscii(out, 'ICC_PROFILE'), isFalse);
    });

    test('also stripped when the image is resized', () {
      final src = _halves(3000, 2000);
      src.exif.imageIfd.make = 'SecretCamMaker';
      final out = prepareJpeg(_jpg(src), longEdge: kLabelLongEdge)!;
      expect(_markers(out), isNot(contains(0xE1)));
      expect(_containsAscii(out, 'SecretCamMaker'), isFalse);
    });
  });

  group('failure paths', () {
    test('empty bytes -> null', () {
      expect(prepareJpeg(Uint8List(0), longEdge: kMealLongEdge), isNull);
    });

    test('random bytes -> null, no throw', () {
      final junk = Uint8List.fromList(List<int>.generate(512, (i) => (i * 37) & 0xFF));
      expect(prepareJpeg(junk, longEdge: kMealLongEdge), isNull);
    });

    test('text is not an image -> null', () {
      final text = Uint8List.fromList('not an image at all'.codeUnits);
      expect(prepareJpeg(text, longEdge: kLabelLongEdge), isNull);
    });

    test('a truncated JPEG -> null, no throw', () {
      final full = _jpg(_halves(400, 300));
      final cut = Uint8List.sublistView(full, 0, 40);
      expect(prepareJpeg(cut, longEdge: kMealLongEdge), isNull);
    });

    test('a result that cannot get under 3 MB -> null', () {
      // High-entropy noise at a long edge far above the real ones: even
      // quality 55 stays over the cap.
      final rng = math.Random(7);
      final noise = img.Image(width: 3200, height: 3200);
      for (final p in noise) {
        p
          ..r = rng.nextInt(256)
          ..g = rng.nextInt(256)
          ..b = rng.nextInt(256);
      }
      final src = Uint8List.fromList(img.encodePng(noise, level: 0));
      expect(prepareJpeg(src, longEdge: 4000), isNull);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a realistic photo-sized result stays under the cap', () {
      final out = prepareJpeg(_jpg(_halves(4000, 3000)), longEdge: kLabelLongEdge)!;
      expect(out.length, lessThanOrEqualTo(kPreparedMaxBytes));
    });
  });

  group('prepareJpegInBackground', () {
    test('gives the same size contract off the UI isolate', () async {
      final out = await prepareJpegInBackground(_jpg(_halves(3000, 2000)),
          longEdge: kMealLongEdge);
      expect(_decode(out!).width, 1024);
    });

    test('undecodable bytes -> null', () async {
      final out = await prepareJpegInBackground(
          Uint8List.fromList([1, 2, 3, 4]),
          longEdge: kMealLongEdge);
      expect(out, isNull);
    });
  });
}
