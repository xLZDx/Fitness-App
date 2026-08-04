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
}

class MockDataExportSink implements DataExportSink {
  /// Every delivery, in order, for assertion.
  final delivered = <({String filename, String contents})>[];

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
