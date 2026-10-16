/// Local export hook: reads the [ActivityJournal] and encodes activities as
/// GPX, FIT or JSON on the device (S02 design 7, 3.5; GPS-PRIV-051). No UI, no
/// file writing, no sharing: it returns bytes and a suggested file name; the UI
/// story saves or shares them. It is also the export the sign-out warning
/// offers before a wipe (`ActivitySignOutHooks.offerExport`).
///
/// The owner's own device export is the FULL series (no route trimming) and
/// includes heart rate when present locally. Nothing here touches the network.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../data/activity_session.dart';
import '../data/fit_encoder.dart';
import '../data/gpx_encoder.dart';
import 'activity_journal.dart';
import 'journal_errors.dart';
import 'journal_models.dart';
import 'uid_scoped_activity_journal.dart' show AccountScopedJournal;

enum ActivityExportFormat {
  gpx('gpx', 'application/gpx+xml'),
  fit('fit', 'application/vnd.ant.fit'),
  json('json', 'application/json');

  const ActivityExportFormat(this.extension, this.mimeType);

  final String extension;
  final String mimeType;
}

/// Typed outcome of exporting one activity.
sealed class ActivityExportResult {
  const ActivityExportResult(this.activityId);

  final String activityId;
}

/// The encoded file.
class ActivityExportFile extends ActivityExportResult {
  const ActivityExportFile(
    super.activityId, {
    required this.format,
    required this.fileName,
    required this.bytes,
  });

  final ActivityExportFormat format;
  final String fileName;
  final Uint8List bytes;
}

/// GPX requested for a session with no GPS geometry (design DQ-3): nothing was
/// produced. FIT and JSON of the same session still work.
class ActivityExportNoGeometry extends ActivityExportResult {
  const ActivityExportNoGeometry(super.activityId);
}

/// The id is unknown, deleted or unreadable.
class ActivityExportNotFound extends ActivityExportResult {
  const ActivityExportNotFound(super.activityId);
}

/// The entry exists but could not be read because of a local I/O error; the
/// export can be retried (nothing was changed or dropped).
class ActivityExportUnavailable extends ActivityExportResult {
  const ActivityExportUnavailable(super.activityId);
}

/// The record is readable but its streams were lost (key loss); only the JSON
/// summary record can be exported, GPX and FIT would silently lack data.
class ActivityExportStreamLost extends ActivityExportResult {
  const ActivityExportStreamLost(super.activityId);
}

/// The bound account changed while an export of the whole journal ran: the
/// export was abandoned, nothing of it may be used (remediation H8). It is the
/// only element of the list [ActivityLocalExport.exportAll] returns then.
class ActivityExportAccountChanged extends ActivityExportResult {
  const ActivityExportAccountChanged() : super('');
}

/// What a UI or the sign-out flow needs.
abstract class ActivityLocalExport {
  /// Exports one activity.
  Future<ActivityExportResult> exportActivity(
    String activityId,
    ActivityExportFormat format,
  );

  /// Exports every live activity of the journal in [format], in journal order.
  /// A per-activity problem is a typed result in the list, never an exception.
  Future<List<ActivityExportResult>> exportAll(ActivityExportFormat format);
}

class JournalActivityLocalExport implements ActivityLocalExport {
  JournalActivityLocalExport(this._journal);

  final ActivityJournal _journal;

  @override
  Future<ActivityExportResult> exportActivity(
    String activityId,
    ActivityExportFormat format,
  ) async {
    final JournalEntry? entry;
    try {
      entry = await _journal.read(activityId);
    } on JournalIoException {
      // A read I/O error is transient: the entry still exists, retry later.
      return ActivityExportUnavailable(activityId);
    }
    if (entry == null) return ActivityExportNotFound(activityId);
    return encodeEntry(entry, format);
  }

  /// Account-bound (remediation H8): the bound uid of an account-scoped
  /// journal is captured before listing and re-checked after the listing and
  /// after every per-activity read. If it changed anywhere, the WHOLE export is
  /// abandoned: the result is a single [ActivityExportAccountChanged] and no
  /// file of either account is returned, so one export never mixes two
  /// accounts. (The listing carries no streams, so each entry is read by id for
  /// the full series; the check after each read covers that read.)
  @override
  Future<List<ActivityExportResult>> exportAll(ActivityExportFormat format) async {
    final uid = _boundUid();
    final entries = await _journal.list();
    if (!_stillBound(uid)) return const [ActivityExportAccountChanged()];
    final out = <ActivityExportResult>[];
    for (final e in entries) {
      final r = await exportActivity(e.session.id, format);
      if (!_stillBound(uid)) return const [ActivityExportAccountChanged()];
      out.add(r);
    }
    return out;
  }

  /// The uid an account-scoped journal is bound to now (null for a plain
  /// journal or while nothing is bound).
  String? _boundUid() {
    if (_journal case final AccountScopedJournal s) {
      return s.isBound ? s.boundUid : null;
    }
    return null;
  }

  bool _stillBound(String? uid) {
    if (_journal is! AccountScopedJournal) return true;
    return _boundUid() == uid;
  }

  /// Pure encoding of one already-read entry (exposed for tests).
  static ActivityExportResult encodeEntry(
    JournalEntry entry,
    ActivityExportFormat format,
  ) {
    final session = entry.session;
    if (entry.state.streamLost && format != ActivityExportFormat.json) {
      return ActivityExportStreamLost(session.id);
    }
    switch (format) {
      case ActivityExportFormat.gpx:
        final r = GpxEncoder.encode(session);
        return switch (r) {
          GpxDocument() => ActivityExportFile(
              session.id,
              format: format,
              fileName: fileNameFor(session, format),
              bytes: Uint8List.fromList(utf8.encode(r.xml)),
            ),
          GpxNoGeometry() => ActivityExportNoGeometry(session.id),
        };
      case ActivityExportFormat.fit:
        return ActivityExportFile(
          session.id,
          format: format,
          fileName: fileNameFor(session, format),
          bytes: FitEncoder.encode(session),
        );
      case ActivityExportFormat.json:
        return ActivityExportFile(
          session.id,
          format: format,
          fileName: fileNameFor(session, format),
          bytes: Uint8List.fromList(
              utf8.encode(const JsonEncoder.withIndent('  ').convert(session.toJson()))),
        );
    }
  }

  /// `<sport>_<yyyyMMddTHHmmssZ>_<last 8 id chars>.<ext>`: only characters
  /// from the sport enum name, digits and hex, so it is a safe file name.
  static String fileNameFor(ActivitySession s, ActivityExportFormat format) {
    final t = s.startUtc.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${t.year.toString().padLeft(4, '0')}${two(t.month)}${two(t.day)}'
        'T${two(t.hour)}${two(t.minute)}${two(t.second)}Z';
    final id = s.id.replaceAll(RegExp(r'[^0-9a-zA-Z]'), '');
    final tail = id.length > 8 ? id.substring(id.length - 8) : id;
    return '${s.sport.name}_${stamp}_$tail.${format.extension}';
  }
}
