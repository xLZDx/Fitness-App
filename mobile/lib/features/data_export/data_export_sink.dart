import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Where an export's JSON text goes once it is built.
///
/// Same shape as every other device-action boundary in this app
/// (`NotificationService`, `EquipmentReportService`): an abstract interface,
/// a mock default so widget tests never touch a platform channel, and
/// `main.dart` overrides with the real implementation. `share_plus` and
/// `path_provider` are plugins with native platform code; `flutter test` runs
/// in a bare Dart VM with no platform channels registered for either, so a
/// test that reached the real sink would hang or throw
/// `MissingPluginException`, not fail the assertion it was written to check.
abstract class DataExportSink {
  Future<void> deliver({required String filename, required String contents});

  /// Delivers a file that is too large to hold as one String: [write] streams
  /// the text into the target the sink provides (a temp file for the share
  /// sheet), in chunks. If [write] throws, nothing is delivered and the partial
  /// file is deleted.
  Future<void> deliverStreamed({
    required String filename,
    required Future<void> Function(ExportTextSink out) write,
  });
}

/// A chunked text target. Writes are awaited so a file-backed target applies
/// back-pressure instead of buffering the whole export.
abstract class ExportTextSink {
  Future<void> write(String chunk);
}

class StringBufferExportTextSink implements ExportTextSink {
  final StringBuffer buffer = StringBuffer();

  @override
  Future<void> write(String chunk) async => buffer.write(chunk);
}

/// Appends to a file, flushing every ~256 KB so memory stays bounded.
class FileExportTextSink implements ExportTextSink {
  FileExportTextSink(this._io);
  final IOSink _io;
  int _pending = 0;

  @override
  Future<void> write(String chunk) async {
    _io.write(chunk);
    _pending += chunk.length;
    if (_pending >= 256 * 1024) {
      _pending = 0;
      await _io.flush();
    }
  }

  Future<void> close() async {
    await _io.flush();
    await _io.close();
  }
}

class MockDataExportSink implements DataExportSink {
  /// Every delivery, in order, for assertion.
  final delivered = <({String filename, String contents})>[];

  @override
  Future<void> deliverStreamed({
    required String filename,
    required Future<void> Function(ExportTextSink out) write,
  }) async {
    final out = StringBufferExportTextSink();
    await write(out);
    delivered.add((filename: filename, contents: out.buffer.toString()));
  }

  @override
  Future<void> deliver({
    required String filename,
    required String contents,
  }) async {
    delivered.add((filename: filename, contents: contents));
  }
}

/// Writes to a temp file, then opens the OS share sheet on it.
///
/// A file rather than `Share.share(text: ...)` with the JSON inline: a
/// multi-year workout history is easily hundreds of KB, past what a share
/// sheet's text payload is meant to carry, and a file is the form every
/// receiving app (Files, email, cloud storage) expects for "here is your
/// data" anyway.
class ShareDataExportSink implements DataExportSink {
  @override
  Future<void> deliverStreamed({
    required String filename,
    required Future<void> Function(ExportTextSink out) write,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    try {
      final out = FileExportTextSink(file.openWrite());
      try {
        await write(out);
        await out.close();
      } catch (_) {
        try {
          await out.close();
        } catch (_) {}
        rethrow;
      }
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
      );
    } finally {
      // The plaintext copy never outlives the call, also after a failure.
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  @override
  Future<void> deliver({
    required String filename,
    required String contents,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(contents);
    try {
      // `Share.shareXFiles` (static), matching share_plus 10.1.4's actual API
      // -- verified against the package source rather than assumed from a
      // newer major version's `SharePlus.instance.share(ShareParams(...))`
      // shape, which does not exist at this pin.
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
      );
    } finally {
      // Without this, every export left an unencrypted copy of the user's
      // own health data -- injuries, medications, workout history -- sitting
      // in app cache indefinitely. `finally` rather than only after a
      // successful share: a thrown PlatformException must not leave the file
      // behind either. share_plus's share sheet has already read the file by
      // the time its Future completes (the OS hands it to the receiving app
      // during the sheet interaction, not after), so deleting here does not
      // race the share itself.
      if (await file.exists()) {
        await file.delete();
      }
    }
  }
}

final dataExportSinkProvider =
    Provider<DataExportSink>((_) => MockDataExportSink());
