import 'dart:io';

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
}
