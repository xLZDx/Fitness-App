/// Recovery on start (S02 design 10; test plan I03, I04, I22, I35, I36, I40,
/// I41, I46-I49, I54, I55).
///
/// Rule: per activity the truth is the HIGHEST generation with a VALID COMMIT
/// marker (the marker parses, its `seq` equals the directory number and the
/// SHA-256 of `record.json` matches). Everything else follows:
///
///  - a generation without a valid COMMIT is never activated and is deleted at
///    once, newer or not, intact or not, also when no committed generation
///    exists (the activity is then absent);
///  - a mismatch of ONLY the `streams.bin` checksum (or a missing file) does
///    not invalidate the generation: the entry is recovered as `streamLost`
///    with all metadata edits preserved (DQ-30). No new generation is written;
///  - `CURRENT` is only a pointer: rebuilt from the selected generation when
///    missing, corrupt or pointing elsewhere;
///  - older committed generations are removed once the selected one is fully
///    verified; if it is `streamLost` they are kept until [orphanMaxAge] and
///    then pass through `quarantine/` (record only) before deletion;
///  - orphan `*.tmp` files are deleted; a torn or garbage index line is
///    ignored and the index is rebuilt from the records when it disagrees.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'journal_file_system.dart';
import 'journal_generation_writer.dart';
import 'journal_layout.dart';
import 'journal_models.dart';

/// The selected generation of one activity.
class RecoveredEntry {
  RecoveredEntry(this.seq, this.record, this.commit, this.streamLost);

  final int seq;
  final JournalRecord record;
  final CommitMarker commit;

  /// True when `streams.bin` of this COMMITTED generation is damaged or
  /// missing (checksum mismatch against the marker).
  final bool streamLost;
}

class RecoveryResult {
  final JournalRecoveryReport report = JournalRecoveryReport();
  final Map<String, RecoveredEntry> entries = {};

  /// Ids whose `streams.bin` could not be read because of an I/O error: a
  /// transient state, never persisted as streamLost.
  final Set<String> streamsUnavailable = {};

  /// Highest sequence number seen anywhere (records, directories, index).
  int maxSeq = 0;
}

final RegExp kJournalIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

class JournalRecoveryPass {
  JournalRecoveryPass({
    required this.fs,
    required this.paths,
    required this.writer,
    required this.clock,
    this.orphanMaxAge = const Duration(days: 7),
    this.quarantineMaxCount = 20,
    this.indexCompactionThreshold = 1000,
  });

  final JournalFileSystem fs;
  final JournalPaths paths;
  final JournalGenerationWriter writer;
  final DateTime Function() clock;
  final Duration orphanMaxAge;
  final int quarantineMaxCount;
  final int indexCompactionThreshold;

  Future<RecoveryResult> run() async {
    final result = RecoveryResult();
    final report = result.report;
    await fs.createDir(paths.journalDir);
    await fs.createDir(paths.sourcesDir);
    await fs.createDir(paths.quarantineDir);

    report.tempFilesRemoved += await _removeTemps(paths.journalDir);

    final top = await fs.list(paths.journalDir);
    for (final child in top) {
      if (!child.isDirectory) continue;
      final id = child.name;
      if (!kJournalIdPattern.hasMatch(id)) {
        report.diagnostics.add('ignoredDirectory:$id');
        continue;
      }
      await _recoverActivity(id, result);
    }

    await _reconcileIndex(result);
    return result;
  }

  Future<int> _removeTemps(String dir) async {
    var count = 0;
    for (final e in await fs.list(dir)) {
      final path = '$dir/${e.name}';
      if (e.isDirectory) {
        count += await _removeTemps(path);
      } else if (e.name.endsWith(kTempSuffix)) {
        try {
          await fs.deleteFile(path);
          count++;
        } catch (_) {}
      }
    }
    return count;
  }

  Future<RecoveredEntry?> _validate(String id, int seq) async {
    final commit = await writer.readCommit(id, seq);
    if (commit == null || commit.seq != seq) return null;
    // Throws JournalUnreadable on an I/O error (never treated as "absent").
    final recordBytes = await writer
        .readIfPresent('${paths.genDir(id, seq)}/$kRecordFileName');
    if (recordBytes == null) return null;
    if (sha256Hex(recordBytes) != commit.recordSha256) return null;
    final record = JournalRecord.tryDecode(recordBytes);
    if (record == null || record.seq != seq || record.id != id) return null;
    return RecoveredEntry(seq, record, commit, false);
  }

  Future<void> _recoverActivity(String id, RecoveryResult result) async {
    final report = result.report;
    final dir = paths.activityDir(id);
    final gens = <int>[
      for (final e in await fs.list(dir))
        if (e.isDirectory && JournalPaths.parseGeneration(e.name) != null)
          JournalPaths.parseGeneration(e.name)!,
    ]..sort((a, b) => b.compareTo(a));
    for (final g in gens) {
      if (g > result.maxSeq) result.maxSeq = g;
    }

    final valid = <int, RecoveredEntry>{};
    RecoveredEntry? selected;
    for (final g in gens) {
      try {
        final v = await _validate(id, g);
        if (v != null) {
          valid[g] = v;
          selected ??= v;
        }
      } on JournalUnreadable {
        // An I/O error is not evidence of an uncommitted generation: keep
        // EVERY generation of this activity untouched and retry at the next
        // start. The activity is neither recovered nor reported absent.
        report.diagnostics.add('unreadable:$id');
        return;
      }
    }

    // Older committed generations are handled below; everything else that is
    // not the selected one (uncommitted, invalid, newer than selected) goes.
    for (final g in gens) {
      if (selected != null && g == selected.seq) continue;
      final isOlderCommitted =
          selected != null && g < selected.seq && valid.containsKey(g);
      if (isOlderCommitted) continue;
      await _deleteGeneration(id, g, report);
    }

    if (selected == null) {
      try {
        await fs.deleteDir(dir);
      } catch (_) {}
      report.absent.add(id);
      return;
    }

    // Stream check: only the streams checksum may differ for a valid entry.
    // A missing file or a checksum mismatch is persisted loss (DQ-30); an I/O
    // error is only a transient "unavailable now" (never persisted).
    var streamLost = false;
    var unavailable = false;
    try {
      final bytes = await writer.readIfPresent(
          '${paths.genDir(id, selected.seq)}/$kStreamsFileName');
      streamLost = bytes == null ||
          sha256Hex(bytes) != selected.commit.streamsSha256 ||
          selected.record.streamHash != selected.commit.streamsSha256;
    } on JournalUnreadable {
      unavailable = true;
      result.streamsUnavailable.add(id);
      report.diagnostics.add('streamsUnreadable:$id');
    }
    final entry =
        RecoveredEntry(selected.seq, selected.record, selected.commit, streamLost);
    result.entries[id] = entry;
    report.selectedGenerations[id] = entry.seq;
    if (streamLost) report.streamLost.add(id);

    // Streams not verifiable right now: keep older generations as a fallback.
    if (unavailable) {
      await _repairCurrent(id, entry, report);
      return;
    }

    // Older committed generations.
    for (final g in gens) {
      if (g >= entry.seq || !valid.containsKey(g)) continue;
      if (!streamLost) {
        await _deleteGeneration(id, g, report);
      } else {
        final modified = await fs.modified(paths.genDir(id, g));
        final aged =
            modified != null && clock().difference(modified) > orphanMaxAge;
        if (aged) {
          await _quarantine(id, g);
          await _deleteGeneration(id, g, report);
        }
      }
    }

    await _repairCurrent(id, entry, report);
  }

  Future<void> _repairCurrent(
      String id, RecoveredEntry entry, JournalRecoveryReport report) async {
    final current = await writer.readCurrent(id);
    if (current != entry.seq) {
      try {
        await writer.writeCurrent(id, entry.seq, entry.record.streamHash);
        report.currentRepaired.add(id);
      } on FileSystemException catch (e) {
        report.diagnostics.add('currentNotRepaired:$id:${e.message}');
      }
    }
  }

  Future<void> _deleteGeneration(
      String id, int seq, JournalRecoveryReport report) async {
    try {
      await fs.deleteDir(paths.genDir(id, seq));
      report.deletedGenerations.add('$id/${paths.genName(seq)}');
    } catch (e) {
      report.diagnostics.add('deleteFailed:$id/${paths.genName(seq)}');
    }
  }

  /// Copies the readable `record.json` (never the streams) into
  /// `quarantine/`, keeping at most [quarantineMaxCount] files (oldest by
  /// generation number dropped).
  Future<void> _quarantine(String id, int seq) async {
    try {
      final bytes =
          await fs.readBytes('${paths.genDir(id, seq)}/$kRecordFileName');
      if (JournalRecord.tryDecode(bytes) == null) return;
      await writer.atomicWrite(
          '${paths.quarantineDir}/$id-${paths.genName(seq)}.json', bytes);
      final files = <MapEntry<int, String>>[];
      for (final e in await fs.list(paths.quarantineDir)) {
        final m = RegExp(r'-g([0-9]+)\.json$').firstMatch(e.name);
        if (!e.isDirectory && m != null) {
          files.add(MapEntry(int.parse(m.group(1)!), e.name));
        }
      }
      files.sort((a, b) => a.key.compareTo(b.key));
      while (files.length > quarantineMaxCount) {
        await fs.deleteFile('${paths.quarantineDir}/${files.removeAt(0).value}');
      }
    } catch (_) {
      // Best effort: quarantine never blocks recovery.
    }
  }

  Future<void> _reconcileIndex(RecoveryResult result) async {
    final report = result.report;
    var bad = false;
    final last = <String, Map<String, Object?>>{};
    var lines = 0;
    var missing = false;
    try {
      final text = utf8.decode(await fs.readBytes(paths.indexFile),
          allowMalformed: true);
      final parts = text.split('\n');
      for (var i = 0; i < parts.length; i++) {
        final line = parts[i];
        if (line.isEmpty) continue;
        try {
          final raw = jsonDecode(line);
          if (raw is Map && raw['id'] is String && raw['seq'] is num) {
            lines++;
            final seq = (raw['seq'] as num).toInt();
            if (seq > result.maxSeq) result.maxSeq = seq;
            last[raw['id'] as String] = {
              'seq': seq,
              'op': raw['op'],
            };
            continue;
          }
        } catch (_) {}
        bad = true; // torn or garbage line: ignored, index is rewritten
      }
    } catch (_) {
      missing = true;
    }

    var mismatch = bad || missing;
    final expected = <Map<String, Object?>>[];
    for (final e in result.entries.entries) {
      final tomb = e.value.record.state.tombstone;
      expected.add({
        'seq': e.value.seq,
        'op': tomb ? 'delete' : 'put',
        'id': e.key,
      });
      final seen = last[e.key];
      if (seen == null ||
          seen['seq'] != e.value.seq ||
          ((seen['op'] == 'delete') != tomb)) {
        mismatch = true;
      }
    }
    for (final id in last.keys) {
      if (!result.entries.containsKey(id)) mismatch = true;
    }
    if (lines > indexCompactionThreshold && lines > 4 * result.entries.length) {
      mismatch = true;
    }
    if (!mismatch) return;
    expected.sort((a, b) => (a['seq'] as int).compareTo(b['seq'] as int));
    try {
      await writer.rewriteIndex(expected);
      report.indexRebuilt = true;
    } on FileSystemException catch (e) {
      report.diagnostics.add('indexNotRebuilt:${e.message}');
    }
  }
}
