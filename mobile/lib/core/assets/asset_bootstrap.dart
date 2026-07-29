import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// Copies bundled model assets out of the APK into the app's documents
/// directory on first launch (or after an upgrade). ML Kit's
/// `LocalLabelerOptions` needs an absolute file path; assets aren't
/// addressable that way directly.
///
/// Safe to call on every launch — if the file already exists with the
/// same length we skip the copy.
class AssetBootstrap {
  AssetBootstrap();

  /// List of bundled assets to copy. Keep small (each ML model is
  /// 4-15 MB) — bigger blobs go to a separate download-on-demand path.
  static const _models = <String>[
    'assets/models/equipment_v1.tflite',
  ];

  Future<void> ensureBundledAssets() async {
    final dir = await getApplicationDocumentsDirectory();
    for (final asset in _models) {
      try {
        final dest = File('${dir.path}/$asset');
        await dest.parent.create(recursive: true);
        final byteData = await rootBundle.load(asset);
        if (await dest.exists() &&
            await dest.length() == byteData.lengthInBytes) {
          continue; // up to date
        }
        await dest.writeAsBytes(
          byteData.buffer.asUint8List(
            byteData.offsetInBytes,
            byteData.lengthInBytes,
          ),
          flush: true,
        );
      } catch (e, st) {
        // Never block startup on this — but never lose it either. A model
        // that fails to unpack (disk full, interrupted write) makes every
        // later recognition fail, and the services downstream can only
        // report "the labeler failed", not the root cause. This log line is
        // the only place that names it.
        debugPrint('AssetBootstrap: failed to unpack $asset: $e');
        debugPrintStack(stackTrace: st);
      }
    }
  }
}
