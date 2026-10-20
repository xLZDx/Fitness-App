/// Names of the on-disk layout of the local journal (S02 design 3.4) and the
/// backup-exclusion constants derived from them (GPS-PRIV-083).
///
/// The production journal tree lives under the app SUPPORT directory (Android
/// `getFilesDir()`, which is `domain="file"` in the backup XML files; the photo
/// store uses the documents directory `app_flutter` instead, see
/// `backup_rules.xml`), inside the per-account scoped root
/// `<support>/activity_journal/<scopeId>` (see `fileActivityJournalFactory`).
/// The directories below (`journal`, `sources`, `quarantine`) are the children
/// of that scope root, or of the support directory itself for
/// `FileActivityJournal.openDefault`. Excluding [kScopedJournalRootDirName]
/// excludes every scope id beneath it.
library;

/// The scoped root directory directly under the app support directory; each
/// account's journal is `<support>/activity_journal/<scopeId>`. Used by
/// `fileActivityJournalFactory` and listed in [kActivityBackupExcludedDirs].
const String kScopedJournalRootDirName = 'activity_journal';

/// Top-level directories of a journal root.
const String kJournalDirName = 'journal';
const String kSourcesDirName = 'sources';
const String kQuarantineDirName = 'quarantine';

/// S04: the crash-safe recording journal lives in a fourth child of the scope
/// root: `<scope root>/recording/<recordingUuid>/` (S04 design 4.2). The account
/// wipe deletes it with the other three.
const String kRecordingDirName = 'recording';

/// S04 design 4.7: the durable wiped-uid marker is a content-free FILE beside
/// the scope directory (`<scopes root>/<scopeId>.wiped`), outside every
/// directory the wipe deletes. Content is [kWipeMarkerWiping] while the wipe
/// runs and [kWipeMarkerWiped] once it completed.
const String kWipedMarkerSuffix = '.wiped';
const String kWipeMarkerWiping = 'wiping';
const String kWipeMarkerWiped = 'wiped';

/// Files.
const String kIndexFileName = 'index.jsonl';
const String kCurrentFileName = 'CURRENT';
const String kCommitFileName = 'COMMIT';
const String kRecordFileName = 'record.json';
const String kStreamsFileName = 'streams.bin';
const String kTempSuffix = '.tmp';

/// Generation directory name prefix: `g<seq>`.
const String kGenerationPrefix = 'g';

/// The directories directly under the app support directory that hold activity
/// data and must never be backed up or transferred. One list drives the Android
/// XML files, the checker and the iOS marking. The three legacy names cover
/// `FileActivityJournal.openDefault`; [kScopedJournalRootDirName] covers the
/// production per-account tree.
const List<String> kActivityBackupExcludedDirs = [
  kJournalDirName,
  kSourcesDirName,
  kQuarantineDirName,
  kScopedJournalRootDirName,
];

/// Android `<exclude domain=... path=.../>` entries for the journal, as
/// `domain|path` strings in the form the existing backup test uses.
const String kAndroidBackupDomain = 'file';

List<String> androidBackupExclusions() => [
      for (final d in kActivityBackupExcludedDirs) '$kAndroidBackupDomain|$d',
    ];

/// The `<exclude>` lines to place in both `backup_rules.xml` and
/// `data_extraction_rules.xml` sections.
List<String> androidBackupExcludeElements() => [
      for (final d in kActivityBackupExcludedDirs)
        '<exclude domain="$kAndroidBackupDomain" path="$d" />',
    ];

/// iOS: files under Application Support are included in iCloud and iTunes
/// backups unless each directory carries the `isExcludedFromBackup` resource
/// value. The iOS project is not generated yet (`mobile/IOS_PERMISSIONS_TODO.md`),
/// so the native side is a recorded follow-up; this interface is the Dart seam
/// the repository calls after creating the directories.
abstract class BackupExclusionMarker {
  /// Marks [absolutePath] as excluded from device backups. Returns false when
  /// the platform cannot do it (never throws).
  Future<bool> markExcluded(String absolutePath);
}

/// A marker that does nothing (Android, where the XML files do the work, and
/// tests).
class NoopBackupExclusionMarker implements BackupExclusionMarker {
  const NoopBackupExclusionMarker();

  @override
  Future<bool> markExcluded(String absolutePath) async => true;
}

/// Checker used by tests and tooling: true when [xml] (comments stripped)
/// excludes every journal directory in each of [sectionTags]. Pass
/// `['full-backup-content']` for `backup_rules.xml` and
/// `['cloud-backup', 'device-transfer']` for `data_extraction_rules.xml`.
bool backupXmlExcludesJournal(String xml, List<String> sectionTags) {
  final clean = xml.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
  for (final tag in sectionTags) {
    final m = RegExp('<$tag>(.*?)</$tag>', dotAll: true).firstMatch(clean);
    if (m == null) return false;
    final found = <String>{};
    for (final e in RegExp(r'<exclude\b([^>]*?)/?>').allMatches(m.group(1)!)) {
      final attrs = e.group(1)!;
      final domain = RegExp(r'domain="([^"]*)"').firstMatch(attrs)?.group(1);
      final path = RegExp(r'path="([^"]*)"').firstMatch(attrs)?.group(1);
      found.add('$domain|$path');
    }
    if (!found.containsAll(androidBackupExclusions())) return false;
  }
  return true;
}
