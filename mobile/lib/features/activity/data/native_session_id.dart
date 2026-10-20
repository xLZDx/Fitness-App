/// The native-session id rule (S02 design 9). Pure Dart, no Flutter imports.
///
/// A native recording (the app's own GPS recording, S04) gets its id from the
/// recording uuid generated ONCE at recording start, never from the clock or
/// the stored data. A re-sync, a re-upload or a replay of the same recording
/// therefore produces the same id, the journal upserts that id and the merger
/// collapses repeats (rule 0 / rule 1): one recording, one session.
///
/// This is the ONLY dedup S02 promises. Matching a native session with a
/// platform-health, BLE or vendor session is NOT promised (design 9); no copy
/// or API in S02 may claim it.
library;

import 'activity_session.dart';
import 'source_kind.dart';
import 'source_record.dart';

/// The source id of the app's own recordings.
const String kNativeSourceId = 'app';

/// `activityIdFor(sourceId: "app", externalId: recordingUuid)`.
///
/// [recordingUuid] must be the value generated at recording start and stored
/// in the provenance record; an empty value is rejected because every empty
/// recording would collapse into one session.
String nativeActivityId(String recordingUuid) {
  if (recordingUuid.isEmpty) {
    throw ArgumentError.value(recordingUuid, 'recordingUuid', 'must not be empty');
  }
  return activityIdFor(
    sourceId: kNativeSourceId,
    externalId: recordingUuid,
    // Unused when an external id is given; a fixed value keeps the call pure.
    startUtc: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
}

/// The provenance record of a native recording: the same `sourceId|externalId`
/// key as [nativeActivityId], so merger rule 1 recognises a replay as well.
SourceRecord nativeSourceRecord({
  required String recordingUuid,
  required DateTime importedAt,
  String? deviceModel,
  List<String> fieldsContributed = const [],
}) {
  if (recordingUuid.isEmpty) {
    throw ArgumentError.value(recordingUuid, 'recordingUuid', 'must not be empty');
  }
  return SourceRecord(
    sourceId: kNativeSourceId,
    sourceKind: SourceKind.companionApp,
    importedAt: importedAt.toUtc(),
    deviceModel: deviceModel,
    externalId: recordingUuid,
    fieldsContributed: fieldsContributed,
  );
}
