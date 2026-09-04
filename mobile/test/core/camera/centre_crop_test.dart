import 'dart:io';
import 'dart:ui' show Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:fitness_app/core/camera/centre_crop.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A 100x80 image, red in the exact centre, blue elsewhere.
  File makeJpeg(Directory dir) {
    final canvas = img.Image(width: 100, height: 80);
    img.fill(canvas, color: img.ColorRgb8(0, 0, 255));
    img.fillRect(canvas, x1: 48, y1: 38, x2: 52, y2: 42,
        color: img.ColorRgb8(255, 0, 0));
    final f = File('${dir.path}/shot.jpg');
    f.writeAsBytesSync(img.encodeJpg(canvas, quality: 95));
    return f;
  }

  test('crops to the central 75% and keeps the centre content', () async {
    final dir = Directory.systemTemp.createTempSync('crop');
    addTearDown(() => dir.deleteSync(recursive: true));
    final src = makeJpeg(dir);

    final outPath = await centreCropForClassification(src.path);
    expect(outPath, isNot(src.path), reason: 'a new cropped file is written');

    final out = img.decodeImage(File(outPath).readAsBytesSync())!;
    expect(out.width, 75);
    expect(out.height, 60);
    final centre = out.getPixel(out.width ~/ 2, out.height ~/ 2);
    expect(centre.r, greaterThan(150),
        reason: 'the red centre of the original stays the centre of the crop');
    expect(centre.b, lessThan(100));
  });

  test('unreadable input degrades to the original path, not a throw', () async {
    final dir = Directory.systemTemp.createTempSync('crop');
    addTearDown(() => dir.deleteSync(recursive: true));
    final junk = File('${dir.path}/junk.jpg')..writeAsBytesSync([1, 2, 3]);

    expect(await centreCropForClassification(junk.path), junk.path);
  });

  test('a missing file degrades to the original path', () async {
    expect(await centreCropForClassification('Z:/no/such/file.jpg'),
        'Z:/no/such/file.jpg');
  });

  // SCAN-G1 (core/SCAN_G1_SCOPE.md, R3): the bracket window of the reference
  // card -- 358x230 with a 20px inset (`Sunset.dc.html:186-190`), or 328x230
  // on a 360-wide phone -- mapped back into a phone photo through the cover
  // fit `LiveEquipmentPreview` applies. Every expected number below was
  // computed by hand from scale = max(vw/iw, vh/ih), the centred offset
  // (vw - iw*scale)/2, and the inverse, NOT by calling the function.
  group('viewfinderSourceRect', () {
    const Rect window358 = Rect.fromLTRB(20 / 358, 20 / 230, 338 / 358, 210 / 230);
    const Rect window328 = Rect.fromLTRB(20 / 328, 20 / 230, 308 / 328, 210 / 230);

    void expectRect(Rect actual, double l, double t, double r, double b) {
      expect(actual.left, closeTo(l, 0.05));
      expect(actual.top, closeTo(t, 0.05));
      expect(actual.right, closeTo(r, 0.05));
      expect(actual.bottom, closeTo(b, 0.05));
    }

    test('358x230 card, 4032x3024 landscape photo', () {
      // scale = max(358/4032, 230/3024) = 0.088790; shown height 268.5,
      // dy = -19.25; x: 20/0.088790, 338/0.088790; y: (20+19.25)/0.088790 ...
      expectRect(
        viewfinderSourceRect(
            const Size(4032, 3024), const Size(358, 230), window358),
        225.251, 442.056, 3806.749, 2581.944,
      );
    });

    test('358x230 card, 3024x4032 portrait photo', () {
      // scale = max(358/3024, 230/4032) = 0.118386; shown height 477.3,
      // dy = -123.667.
      expectRect(
        viewfinderSourceRect(
            const Size(3024, 4032), const Size(358, 230), window358),
        168.939, 1213.542, 2855.061, 2818.458,
      );
    });

    test('328x230 card, 4032x3024 landscape photo', () {
      // scale = 328/4032 = 0.081349; shown height 246, dy = -8.
      expectRect(
        viewfinderSourceRect(
            const Size(4032, 3024), const Size(328, 230), window328),
        245.854, 344.195, 3786.146, 2679.805,
      );
    });

    test('328x230 card, 3024x4032 portrait photo', () {
      // scale = 328/3024 = 0.108466; shown height 437.3, dy = -103.667.
      expectRect(
        viewfinderSourceRect(
            const Size(3024, 4032), const Size(328, 230), window328),
        184.390, 1140.146, 2839.610, 2891.854,
      );
    });

    test('a window past the shown region is clamped to the photo', () {
      final r = viewfinderSourceRect(
        const Size(400, 300),
        const Size(358, 230),
        const Rect.fromLTRB(-1, -1, 2, 2),
      );
      expect(r, const Rect.fromLTRB(0, 0, 400, 300));
    });

    test('an empty photo or viewport maps to the whole (empty) photo', () {
      expect(
        viewfinderSourceRect(Size.zero, const Size(358, 230), window358),
        Rect.zero,
      );
      expect(
        viewfinderSourceRect(const Size(400, 300), Size.zero, window358),
        const Rect.fromLTRB(0, 0, 400, 300),
      );
    });
  });

  group('cropToViewfinder', () {
    const Rect window = Rect.fromLTRB(20 / 358, 20 / 230, 338 / 358, 210 / 230);

    /// A 400x300 photo with a distinct 6x6 marker just inside each corner of
    /// where the bracket window lands on it, computed by hand: scale =
    /// max(358/400, 230/300) = 0.895, dy = (230 - 268.5)/2 = -19.25, so the
    /// window is x 22.35..377.65, y 43.85..256.15 -- rounded 22..378, 44..256.
    File makeMarked(Directory dir, {int orientation = 1}) {
      final canvas = img.Image(width: 400, height: 300);
      img.fill(canvas, color: img.ColorRgb8(40, 40, 40));
      void mark(int x, int y, img.Color c) =>
          img.fillRect(canvas, x1: x, y1: y, x2: x + 5, y2: y + 5, color: c);
      mark(22, 44, img.ColorRgb8(255, 0, 0)); // top-left
      mark(372, 44, img.ColorRgb8(0, 255, 0)); // top-right
      mark(22, 250, img.ColorRgb8(0, 0, 255)); // bottom-left
      mark(372, 250, img.ColorRgb8(255, 255, 0)); // bottom-right
      // A marker OUTSIDE the window (above it) that must not survive.
      mark(200, 10, img.ColorRgb8(255, 0, 255));
      if (orientation != 1) {
        canvas.exif.imageIfd['Orientation'] = orientation;
      }
      final f = File('${dir.path}/shot.jpg');
      f.writeAsBytesSync(img.encodeJpg(canvas, quality: 100));
      return f;
    }

    test('the hand-computed window for 400x300 in 358x230', () {
      final r = viewfinderSourceRect(
          const Size(400, 300), const Size(358, 230), window);
      expect(r.left, closeTo(22.35, 0.05));
      expect(r.top, closeTo(43.85, 0.05));
      expect(r.right, closeTo(377.65, 0.05));
      expect(r.bottom, closeTo(256.15, 0.05));
    });

    test('the crop is exactly the bracket window, corner markers survive',
        () async {
      final dir = Directory.systemTemp.createTempSync('vfcrop');
      addTearDown(() => dir.deleteSync(recursive: true));
      final src = makeMarked(dir);

      final outPath = await cropToViewfinder(src.path,
          viewport: const Size(358, 230), windowNormalized: window);
      expect(outPath, endsWith('.viewfinder.jpg'));

      final out = img.decodeImage(File(outPath).readAsBytesSync())!;
      // 378 - 22 = 356 wide, 256 - 44 = 212 tall.
      expect(out.width, 356);
      expect(out.height, 212);
      bool isRed(img.Pixel p) => p.r > 180 && p.g < 90 && p.b < 90;
      bool isGreen(img.Pixel p) => p.g > 180 && p.r < 90 && p.b < 90;
      bool isBlue(img.Pixel p) => p.b > 180 && p.r < 90 && p.g < 90;
      bool isYellow(img.Pixel p) => p.r > 180 && p.g > 180 && p.b < 90;
      expect(isRed(out.getPixel(2, 2)), isTrue, reason: 'top-left marker');
      expect(isGreen(out.getPixel(out.width - 3, 2)), isTrue,
          reason: 'top-right marker');
      expect(isBlue(out.getPixel(2, out.height - 3)), isTrue,
          reason: 'bottom-left marker');
      expect(isYellow(out.getPixel(out.width - 3, out.height - 3)), isTrue,
          reason: 'bottom-right marker');
      // Nothing magenta anywhere: the marker above the window is gone.
      var magenta = 0;
      for (final p in out) {
        if (p.r > 180 && p.b > 180 && p.g < 90) magenta++;
      }
      expect(magenta, 0, reason: 'pixels outside the window are cropped away');
    });

    test('EXIF orientation is baked in before the window is applied',
        () async {
      final dir = Directory.systemTemp.createTempSync('vfcrop');
      addTearDown(() => dir.deleteSync(recursive: true));
      // Orientation 6 = rotate 90 CW on display: the 400x300 bytes show as
      // 300x400. In 358x230 that is scale = max(358/300, 230/400) = 1.19333,
      // dy = (230 - 477.33)/2 = -123.667: x 16.76..283.24, y 120.39..279.61
      // -> 17..283 (266 wide), 120..280 (160 tall).
      final src = makeMarked(dir, orientation: 6);
      // The fixture really carries the tag: baked on its own, the 400x300
      // bytes come out 300x400. (Asserted through `bakeOrientation` rather
      // than by reading the IFD back -- package:image's decoder files the
      // tag where its own baker finds it, not under `imageIfd['Orientation']`.)
      final decoded = img.decodeImage(src.readAsBytesSync())!;
      final baked = img.bakeOrientation(decoded);
      expect((baked.width, baked.height), (300, 400),
          reason: 'the fixture carries the orientation tag it claims to');

      final outPath = await cropToViewfinder(src.path,
          viewport: const Size(358, 230), windowNormalized: window);
      final out = img.decodeImage(File(outPath).readAsBytesSync())!;
      expect(out.width, 266);
      expect(out.height, 160);
    });

    test('unreadable input degrades to the original path', () async {
      final dir = Directory.systemTemp.createTempSync('vfcrop');
      addTearDown(() => dir.deleteSync(recursive: true));
      final junk = File('${dir.path}/junk.jpg')..writeAsBytesSync([1, 2, 3]);
      expect(
        await cropToViewfinder(junk.path,
            viewport: const Size(358, 230), windowNormalized: window),
        junk.path,
      );
    });

    test('a missing file degrades to the original path', () async {
      expect(
        await cropToViewfinder('Z:/no/such/file.jpg',
            viewport: const Size(358, 230), windowNormalized: window),
        'Z:/no/such/file.jpg',
      );
    });
  });
}
