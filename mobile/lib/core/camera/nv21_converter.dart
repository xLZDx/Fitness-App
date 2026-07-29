import 'dart:typed_data';

import 'package:camera/camera.dart';

/// One plane of a camera frame, reduced to the three fields the conversion
/// needs.
///
/// This exists separately from the plugin's `Plane` for one reason: a test
/// cannot construct a `CameraImage`, so without a plain value type the
/// conversion below could never actually be executed by the suite — which is
/// exactly how the format bug reached a real phone.
class YuvPlane {
  const YuvPlane({
    required this.bytes,
    required this.bytesPerRow,
    this.bytesPerPixel = 1,
  });

  final Uint8List bytes;

  /// Bytes between the start of consecutive rows. Camera hardware pads rows
  /// to alignment boundaries, so this is >= the row's useful width and must
  /// never be assumed equal to it.
  final int bytesPerRow;

  /// Bytes between consecutive samples within a row. 2 on the many devices
  /// whose U and V planes are interleaved views over a single buffer.
  final int bytesPerPixel;
}

/// Packs a YUV_420_888 frame into NV21: the full luma plane, followed by
/// half-resolution chroma interleaved as V,U,V,U.
///
/// Why this is needed at all: on Android the `camera` plugin resolves to
/// `camera_android_camerax`, which states that it ignores `imageFormatGroup`
/// and always delivers YUV_420_888 (`android_camera_camerax.dart:450-453`).
/// ML Kit's Android bridge accepts only NV21 or YV12 byte buffers
/// (`InputImageConverter.java:111`) and answers anything else with
/// "ImageFormat is not supported." Concatenating the three planes raw — the
/// previous approach — produces neither a valid NV21 nor the right length,
/// which is what killed live recognition and the form coach on device.
Uint8List yuv420ToNv21({
  required int width,
  required int height,
  required YuvPlane y,
  required YuvPlane u,
  required YuvPlane v,
}) {
  if (width <= 0 || height <= 0) {
    throw ArgumentError('frame must be non-empty, got $width x $height');
  }
  if (width.isOdd || height.isOdd) {
    // NV21 carries one chroma pair per 2x2 luma block, so odd dimensions
    // have no valid representation. Throwing beats handing ML Kit a buffer
    // it will read past the end of.
    throw ArgumentError('NV21 needs even dimensions, got $width x $height');
  }

  final chromaWidth = width >> 1;
  final chromaHeight = height >> 1;
  final ySize = width * height;
  final out = Uint8List(ySize + chromaWidth * chromaHeight * 2);

  var o = 0;
  if (y.bytesPerPixel == 1 && y.bytesPerRow == width) {
    // Unpadded: the plane is already contiguous, so one bulk copy does it.
    out.setRange(0, ySize, y.bytes);
    o = ySize;
  } else {
    for (var row = 0; row < height; row++) {
      final base = row * y.bytesPerRow;
      if (y.bytesPerPixel == 1) {
        out.setRange(o, o + width, y.bytes, base);
        o += width;
      } else {
        for (var col = 0; col < width; col++) {
          out[o++] = y.bytes[base + col * y.bytesPerPixel];
        }
      }
    }
  }

  // V before U — that ordering is what distinguishes NV21 from NV12.
  for (var row = 0; row < chromaHeight; row++) {
    final vBase = row * v.bytesPerRow;
    final uBase = row * u.bytesPerRow;
    for (var col = 0; col < chromaWidth; col++) {
      out[o++] = v.bytes[vBase + col * v.bytesPerPixel];
      out[o++] = u.bytes[uBase + col * u.bytesPerPixel];
    }
  }
  return out;
}

/// Adapts a plugin [CameraImage] onto [yuv420ToNv21].
///
/// A single-plane frame is already packed (some Android implementations hand
/// back NV21 directly) and is passed through untouched.
Uint8List cameraImageToNv21(CameraImage image) {
  final planes = image.planes;
  if (planes.length == 1) return planes.first.bytes;
  if (planes.length < 3) {
    throw ArgumentError(
      'YUV_420_888 needs 3 planes, frame carried ${planes.length}',
    );
  }
  YuvPlane wrap(Plane p) => YuvPlane(
        bytes: p.bytes,
        bytesPerRow: p.bytesPerRow,
        bytesPerPixel: p.bytesPerPixel ?? 1,
      );
  return yuv420ToNv21(
    width: image.width,
    height: image.height,
    y: wrap(planes[0]),
    u: wrap(planes[1]),
    v: wrap(planes[2]),
  );
}
