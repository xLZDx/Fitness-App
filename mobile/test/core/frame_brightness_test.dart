import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/camera/frame_brightness.dart';

/// R2.2 state 9. The low-light gate's only testable half: brightness from
/// bytes, with no camera involved. The rest (frame runs, the banner) is
/// widget-level; this pins the arithmetic so a format mix-up cannot make a
/// lit room read as dark.
void main() {
  Uint8List luma(int value, {int pixels = 1000}) =>
      Uint8List.fromList(List.filled(pixels, value));

  /// BGRA, four bytes per pixel, in the plugin's byte order.
  Uint8List bgra(int b, int g, int r, {int pixels = 1000}) =>
      Uint8List.fromList(
          List.generate(pixels * 4, (i) => [b, g, r, 255][i % 4]));

  group('averageFrameBrightness — luma plane (Android yuv420)', () {
    test('black is 0 and white is 1', () {
      expect(averageFrameBrightness(luma(0), interleavedBgra: false), 0.0);
      expect(averageFrameBrightness(luma(255), interleavedBgra: false), 1.0);
    });

    test('mid grey lands mid scale', () {
      final v = averageFrameBrightness(luma(128), interleavedBgra: false)!;
      expect(v, closeTo(128 / 255, 0.001));
    });

    test('a dark room reads below the threshold, a lit one above', () {
      // The numbers the gate actually turns on: 25/255 ≈ 0.098 is a dim room,
      // 90/255 ≈ 0.353 an ordinary one.
      expect(averageFrameBrightness(luma(25), interleavedBgra: false)!,
          lessThan(kLowLightBrightness));
      expect(averageFrameBrightness(luma(90), interleavedBgra: false)!,
          greaterThan(kLowLightBrightness));
    });

    test('empty bytes yield no reading rather than a false dark one', () {
      // Null, not 0.0 — "we did not measure" must never be indistinguishable
      // from "it is pitch black", or a dropped frame would raise the banner.
      expect(averageFrameBrightness(Uint8List(0), interleavedBgra: false),
          isNull);
    });
  });

  group('averageFrameBrightness — BGRA (iOS)', () {
    test('white is 1 whichever channel order is used', () {
      expect(averageFrameBrightness(bgra(255, 255, 255), interleavedBgra: true),
          closeTo(1.0, 0.001));
      expect(
          averageFrameBrightness(bgra(0, 0, 0), interleavedBgra: true), 0.0);
    });

    test('green weighs more than blue, per Rec. 601', () {
      // Not decoration: reading BGRA in the wrong order would make a blue-lit
      // room look bright and a green-lit one dark.
      final green = averageFrameBrightness(bgra(0, 255, 0), interleavedBgra: true)!;
      final blue = averageFrameBrightness(bgra(255, 0, 0), interleavedBgra: true)!;
      expect(green, greaterThan(blue));
      expect(green, closeTo(0.587, 0.001));
      expect(blue, closeTo(0.114, 0.001));
    });

    test('BGRA read as luma would be wrong — the flag matters', () {
      final bytes = bgra(0, 255, 0);
      final asBgra = averageFrameBrightness(bytes, interleavedBgra: true)!;
      final asLuma = averageFrameBrightness(bytes, interleavedBgra: false)!;
      expect(asBgra, isNot(closeTo(asLuma, 0.05)),
          reason: 'a format mix-up must not silently produce a plausible value');
    });
  });

  group('sampling', () {
    test('a large frame is sampled, not summed, and stays accurate', () {
      // 1280x720 luma is ~920k bytes; averaging all of them per frame on the
      // UI isolate would cost more than the recognition it guards.
      final big = luma(200, pixels: 1280 * 720);
      final v = averageFrameBrightness(big, interleavedBgra: false)!;
      expect(v, closeTo(200 / 255, 0.001));
    });

    test('a frame smaller than the sample budget is read whole', () {
      final small = luma(64, pixels: 10);
      expect(averageFrameBrightness(small, interleavedBgra: false)!,
          closeTo(64 / 255, 0.001));
    });
  });
}
