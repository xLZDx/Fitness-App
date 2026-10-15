/// Port for getting ONE still image from the camera or the gallery, used by
/// the meal photo and label pages (design s17.2). A port so widget tests use
/// a fake and never touch a platform channel.
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

enum CaptureSource { camera, gallery }

abstract class CaptureImagePort {
  /// Raw image bytes, or null when the user cancelled or the platform refused
  /// (camera permission denied, no camera). Never throws for those cases.
  Future<Uint8List?> pick(CaptureSource source);
}

class ImagePickerCapturePort implements CaptureImagePort {
  ImagePickerCapturePort([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<Uint8List?> pick(CaptureSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source == CaptureSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        // The page re-encodes to the exact long edge; this only bounds memory.
        maxWidth: 2400,
        maxHeight: 2400,
      );
      if (file == null) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }
}

/// Test double: returns [bytes] for every pick and counts calls.
class FakeCaptureImagePort implements CaptureImagePort {
  FakeCaptureImagePort([this.bytes]);

  Uint8List? bytes;
  int picks = 0;
  CaptureSource? lastSource;

  @override
  Future<Uint8List?> pick(CaptureSource source) async {
    picks++;
    lastSource = source;
    return bytes;
  }
}

final captureImagePortProvider =
    Provider<CaptureImagePort>((_) => ImagePickerCapturePort());
