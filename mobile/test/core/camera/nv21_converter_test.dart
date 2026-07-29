import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/camera/nv21_converter.dart';

Uint8List bytes(List<int> v) => Uint8List.fromList(v);

void main() {
  group('yuv420ToNv21', () {
    // A 4x2 frame: 8 luma samples, one 2x1 chroma row.
    test('packs an unpadded frame as Y then interleaved V,U', () {
      final out = yuv420ToNv21(
        width: 4,
        height: 2,
        y: YuvPlane(bytes: bytes([1, 2, 3, 4, 5, 6, 7, 8]), bytesPerRow: 4),
        u: YuvPlane(bytes: bytes([100, 101]), bytesPerRow: 2),
        v: YuvPlane(bytes: bytes([200, 201]), bytesPerRow: 2),
      );

      expect(out.sublist(0, 8), [1, 2, 3, 4, 5, 6, 7, 8]);
      // V first, then its U partner — NV21, not NV12.
      expect(out.sublist(8), [200, 100, 201, 101]);
    });

    // Hardware pads rows to alignment boundaries. Reading bytesPerRow as if
    // it were the width is the classic way to get a sheared image.
    test('skips row padding in the luma plane', () {
      final padded = bytes([
        1, 2, 3, 4, 0xFF, 0xFF, // row 0 + 2 bytes of padding
        5, 6, 7, 8, 0xFF, 0xFF, // row 1 + 2 bytes of padding
      ]);
      final out = yuv420ToNv21(
        width: 4,
        height: 2,
        y: YuvPlane(bytes: padded, bytesPerRow: 6),
        u: YuvPlane(bytes: bytes([100, 101]), bytesPerRow: 2),
        v: YuvPlane(bytes: bytes([200, 201]), bytesPerRow: 2),
      );

      expect(out.sublist(0, 8), [1, 2, 3, 4, 5, 6, 7, 8],
          reason: 'padding bytes must not leak into the packed plane');
      expect(out, isNot(contains(0xFF)));
    });

    // The common semi-planar case: U and V are strided views over one buffer,
    // so consecutive samples sit 2 bytes apart.
    test('honours a chroma pixel stride of 2', () {
      final out = yuv420ToNv21(
        width: 4,
        height: 2,
        y: YuvPlane(bytes: bytes([1, 2, 3, 4, 5, 6, 7, 8]), bytesPerRow: 4),
        u: YuvPlane(
            bytes: bytes([100, 0, 101, 0]), bytesPerRow: 4, bytesPerPixel: 2),
        v: YuvPlane(
            bytes: bytes([200, 0, 201, 0]), bytesPerRow: 4, bytesPerPixel: 2),
      );

      expect(out.sublist(8), [200, 100, 201, 101],
          reason: 'interleaving filler must be stepped over, not copied');
    });

    test('honours a luma pixel stride > 1', () {
      final out = yuv420ToNv21(
        width: 2,
        height: 2,
        y: YuvPlane(
          bytes: bytes([1, 0, 2, 0, 3, 0, 4, 0]),
          bytesPerRow: 4,
          bytesPerPixel: 2,
        ),
        u: YuvPlane(bytes: bytes([100]), bytesPerRow: 1),
        v: YuvPlane(bytes: bytes([200]), bytesPerRow: 1),
      );

      expect(out.sublist(0, 4), [1, 2, 3, 4]);
      expect(out.sublist(4), [200, 100]);
    });

    // ML Kit sizes its read off width/height, so a buffer of any other length
    // is either truncated or an out-of-bounds read on the native side.
    test('always produces exactly width * height * 3 / 2 bytes', () {
      for (final dims in const [
        [4, 2],
        [8, 8],
        [64, 48],
        [640, 480],
      ]) {
        final w = dims[0];
        final h = dims[1];
        final out = yuv420ToNv21(
          width: w,
          height: h,
          // Deliberately padded so the fast path is not the one measured.
          y: YuvPlane(bytes: Uint8List(w * h + h * 4), bytesPerRow: w + 4),
          u: YuvPlane(bytes: Uint8List(w * h ~/ 4), bytesPerRow: w ~/ 2),
          v: YuvPlane(bytes: Uint8List(w * h ~/ 4), bytesPerRow: w ~/ 2),
        );
        expect(out.length, w * h * 3 ~/ 2, reason: 'for ${w}x$h');
      }
    });

    test('rejects odd dimensions instead of overrunning the buffer', () {
      expect(
        () => yuv420ToNv21(
          width: 3,
          height: 2,
          y: YuvPlane(bytes: Uint8List(6), bytesPerRow: 3),
          u: YuvPlane(bytes: Uint8List(2), bytesPerRow: 1),
          v: YuvPlane(bytes: Uint8List(2), bytesPerRow: 1),
        ),
        throwsArgumentError,
      );
    });

    test('rejects an empty frame', () {
      expect(
        () => yuv420ToNv21(
          width: 0,
          height: 0,
          y: YuvPlane(bytes: Uint8List(0), bytesPerRow: 0),
          u: YuvPlane(bytes: Uint8List(0), bytesPerRow: 0),
          v: YuvPlane(bytes: Uint8List(0), bytesPerRow: 0),
        ),
        throwsArgumentError,
      );
    });

    // Regression, 2026-07-30. Live recognition and the form coach shipped
    // concatenating the three planes end to end and labelling the result
    // NV21. On a padded frame that is not merely wrong content — it is the
    // wrong LENGTH, so the native side could never have accepted it. This
    // pins the difference so the shortcut cannot come back.
    test('differs in length from a naive three-plane concatenation', () {
      const w = 64;
      const h = 48;
      final yBytes = Uint8List(w * h + h * 4); // 4 bytes of padding per row
      final uBytes = Uint8List(w * h ~/ 4);
      final vBytes = Uint8List(w * h ~/ 4);

      final naive = yBytes.length + uBytes.length + vBytes.length;
      final packed = yuv420ToNv21(
        width: w,
        height: h,
        y: YuvPlane(bytes: yBytes, bytesPerRow: w + 4),
        u: YuvPlane(bytes: uBytes, bytesPerRow: w ~/ 2),
        v: YuvPlane(bytes: vBytes, bytesPerRow: w ~/ 2),
      ).length;

      expect(packed, w * h * 3 ~/ 2);
      expect(naive, isNot(packed),
          reason: 'the old concatenation produced a buffer ML Kit could not '
              'read — this is why "ImageFormat is not supported." appeared');
    });
  });
}
