// C14 (D-4, D-69): the on-device face blur. Real pixels through the real
// isolate service: the head window must lose its detail, the body must keep it,
// the output must be a metadata-free JPEG on the 1280 px grid, and anything
// that cannot be protected must be a refusal (fail closed).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:fitness_app/features/body_scan/state/blur_service.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_models.dart';

ScanLandmark _l(String n, double x, double y, [double p = 0.9]) =>
    ScanLandmark(name: n, x: x, y: y, likelihood: p);

final _head = [
  _l('nose', 0.5, 0.15),
  _l('leftEar', 0.46, 0.15),
  _l('rightEar', 0.54, 0.15),
  _l('leftShoulder', 0.3, 0.30),
  _l('rightShoulder', 0.7, 0.30),
];

/// High-contrast 2 px stripes everywhere, so detail is easy to measure.
Uint8List _striped(int w, int h, {bool exif = false}) {
  final im = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = ((x ~/ 2) + (y ~/ 2)).isEven ? 0 : 255;
      im.setPixelRgb(x, y, v, v, v);
    }
  }
  if (exif) {
    im.exif.imageIfd.make = 'SECRET-CAMERA-MAKE';
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 95));
}

/// Standard deviation of luminance in a square window around (cx, cy).
double _detail(img.Image im, int cx, int cy, {int half = 10}) {
  final vals = <double>[];
  for (var y = cy - half; y < cy + half; y++) {
    for (var x = cx - half; x < cx + half; x++) {
      vals.add(img.getLuminance(im.getPixel(x, y)).toDouble());
    }
  }
  final mean = vals.reduce((a, b) => a + b) / vals.length;
  final v = vals.fold<double>(0, (a, b) => a + (b - mean) * (b - mean)) /
      vals.length;
  return math.sqrt(v);
}

void main() {
  const service = IsolateBlurService();

  group('frameFromScanLandmarks', () {
    test('x is scaled by the aspect ratio, y and likelihood are kept', () {
      final f = frameFromScanLandmarks([_l('nose', 0.5, 0.2, 0.7)], 0.75);
      final n = f.landmarks[LandmarkType.nose]!;
      expect(n.x, closeTo(0.375, 1e-12));
      expect(n.y, 0.2);
      expect(n.likelihood, 0.7);
      expect(f.aspectRatio, 0.75);
    });

    test('unknown names and non-finite coordinates are dropped', () {
      final f = frameFromScanLandmarks([
        _l('tail', 0.5, 0.5),
        _l('nose', double.nan, 0.5),
        _l('leftEar', 0.5, double.infinity),
        _l('rightEar', 0.5, 0.5),
      ], 1.0);
      expect(f.landmarks.keys, [LandmarkType.rightEar]);
    });
  });

  group('refusals (fail closed)', () {
    test('no landmarks', () async {
      final r = await service.blur(photo: _striped(64, 96), landmarks: const []);
      expect(r, isA<BlurRefused>());
      expect((r as BlurRefused).reason, BlurRefusal.noLandmarks);
    });

    test('bytes that are not an image', () async {
      final r = await service.blur(
          photo: Uint8List.fromList([1, 2, 3, 4, 5]), landmarks: _head);
      expect((r as BlurRefused).reason, BlurRefusal.undecodable);
    });

    test('landmarks that cannot size a head box', () async {
      final r = await service.blur(
          photo: _striped(64, 96), landmarks: [_l('leftWrist', 0.5, 0.5)]);
      expect((r as BlurRefused).reason, BlurRefusal.cannotSize);
    });

    test('low-likelihood head landmarks are unusable', () async {
      final r = await service.blur(
          photo: _striped(64, 96),
          landmarks: [_l('nose', 0.5, 0.15, 0.1)]);
      expect(r, isA<BlurRefused>());
    });
  });

  group('success', () {
    late img.Image out;
    late Uint8List jpeg;

    setUpAll(() async {
      final r = await service.blur(
          photo: _striped(1200, 1600, exif: true), landmarks: _head);
      expect(r, isA<BlurSuccess>());
      jpeg = (r as BlurSuccess).jpeg;
      out = img.decodeJpg(jpeg)!;
    });

    test('a JPEG within the size cap', () {
      expect(jpeg[0], 0xFF);
      expect(jpeg[1], 0xD8);
      expect(jpeg.length, lessThanOrEqualTo(kBlurMaxBytes));
    });

    test('the long edge is resized to 1280 keeping the aspect ratio', () {
      expect(out.height, kBlurLongEdge);
      expect(out.width, 960);
    });

    test('no EXIF block survives the re-encode', () {
      final s = String.fromCharCodes(jpeg);
      expect(s.contains('SECRET-CAMERA-MAKE'), isFalse);
      expect(s.contains('Exif'), isFalse);
    });

    test('the head window loses its detail while the body keeps it', () {
      final headDetail = _detail(out, (0.5 * 1280 * 0.75).round(), (0.15 * 1280).round());
      final bodyDetail = _detail(out, 480, (0.75 * 1280).round());
      expect(bodyDetail, greaterThan(60), reason: 'control: stripes survive');
      expect(headDetail, lessThan(bodyDetail * 0.25),
          reason: 'head $headDetail vs body $bodyDetail');
    });

    test('a photo already smaller than the grid is not upscaled', () async {
      final r = await service.blur(photo: _striped(400, 600), landmarks: _head);
      final o = img.decodeJpg((r as BlurSuccess).jpeg)!;
      expect([o.width, o.height], [400, 600]);
    });
  });
}
