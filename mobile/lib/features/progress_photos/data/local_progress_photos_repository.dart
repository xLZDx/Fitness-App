import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/camera/camera_session.dart';
import '../state/progress_photos_providers.dart';
import 'photo_store.dart';
import 'progress_photo.dart';

/// Where a photo's pixels come from. Split out so the repository can be
/// tested without a camera: a device has [CameraSessionPhotoSource], a test
/// has a fake that returns a fixed byte list.
abstract class PhotoSource {
  /// Returns the captured pixels, or null when the user backed out. Cancelling
  /// is a normal outcome, not an error — modelling it as a throw would make
  /// every call site catch an exception on the happy path.
  Future<Uint8List?> take();
}

/// Captures through the app's own [CameraSession].
///
/// Not `image_picker` with `ImageSource.camera`, which would be two lines
/// shorter. That call launches the system camera as a separate activity, and
/// the app has a standing rule against it — enforced mechanically by
/// `test/features/visual_equipment/live_preview_test.dart`, which greps `lib/`
/// for the symbol. The rule caught this exact import on first run. For a
/// progress photo the reason bites harder than elsewhere: the system camera
/// writes a plaintext JPEG into shared storage on its way back, so the file
/// the gallery indexes is the unencrypted one, and the encryption downstream
/// would be protecting a copy while the original sat in the camera roll.
class CameraSessionPhotoSource implements PhotoSource {
  CameraSessionPhotoSource(this._session);

  final CameraSession _session;

  @override
  Future<Uint8List?> take() async {
    final shot = await _session.captureStill();
    if (shot == null) return null;
    final bytes = await shot.readAsBytes();

    // A2-sec. `CameraController.takePicture()` writes a plaintext JPEG to the
    // app's cache directory and hands back an XFile pointing at it. Everything
    // downstream encrypts the BYTES, so without this delete the encryption was
    // protecting a copy while the original sat on disk unencrypted, in a
    // directory the OS may hand to a backup agent and that nothing else ever
    // cleans up. One capture per session, kept forever, was the actual leak.
    //
    // After the read, never before: losing the shot to a failed cleanup would
    // trade a privacy bug for a data-loss bug.
    try {
      await File(shot.path).delete();
    } catch (e) {
      // The pixels are already in hand and about to be encrypted. A temp file
      // that would not delete is worth a log line, never worth failing a
      // capture the user just posed for.
      debugPrint('progress photo: plaintext temp not deleted: $e');
    }
    return bytes;
  }
}

/// Device-local repository. Photos never leave the phone: [PhotoStore] writes
/// AES-GCM envelopes into the app's private documents directory and nothing
/// in this class talks to the network.
///
/// That is the whole feature as the operator scoped it — capture, timeline,
/// compare, delete. There is deliberately no share and no export: the design
/// had an `ExportScreen`, and building it would put a decrypted JPEG into the
/// system share sheet, which is exactly the moment the "never leaves your
/// phone" promise on the privacy strip stops being true.
class LocalProgressPhotosRepository implements ProgressPhotosRepository {
  LocalProgressPhotosRepository({
    required PhotoStore store,
    required PhotoSource source,
    DateTime Function()? clock,
  })  : _store = store,
        _source = source,
        _clock = clock ?? DateTime.now;

  final PhotoStore _store;
  final PhotoSource _source;
  final DateTime Function() _clock;

  @override
  Stream<List<ProgressPhoto>> watch() async* {
    yield await _store.index();
  }

  @override
  Future<Uint8List?> takeShot() => _source.take();

  /// The clock is read HERE, not when the shutter fired.
  ///
  /// The two are now separated by however long the user spends looking at the
  /// shot and typing a weight, so they are genuinely different times. This one
  /// is the right one to keep: the timeline groups by month and the compare
  /// card measures a span in days, and both of those are answering "when did
  /// this get recorded", which is what a user reading the grid means.
  @override
  Future<ProgressPhoto> save(
    Uint8List bytes, {
    required ProgressPhotoAngle angle,
    double? weightKg,
    String? note,
  }) =>
      _store.put(
        bytes,
        takenAt: _clock(),
        angle: angle,
        weightKg: weightKg,
        note: note,
      );

  @override
  Future<void> delete(String id) => _store.remove(id);

  @override
  Future<Uint8List> bytesOf(ProgressPhoto photo) => _store.read(photo);
}
