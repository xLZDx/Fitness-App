/// The generation write path of the local journal (S02 design 10 write order,
/// test plan I19, I20, I40).
///
/// One mutation = one NEW generation directory `journal/<id>/g<seq>/`. Nothing
/// confirmed is ever overwritten, renamed over or deleted inside a generation
/// that has a COMMIT marker. Order:
///
///  1. create `g<seq>/`; `streams.bin` then `record.json` (each: temp file,
///     write, flush, fsync, close, rename inside the new directory);
///  2. read both back and verify `streamHash` against the bytes on disk;
///  3. COMMIT marker (temp, write, flush, fsync, close, atomic rename) with the
///     `seq` and two separate checksums. THIS RENAME IS THE COMMIT POINT;
///  4. `CURRENT` pointer (same atomic write), a fast pointer only;
///  5. `index.jsonl` append + fsync.
///
/// There is NO directory fsync (Dart has none): rename atomicity is the stated
/// limit. The old generation is NOT deleted here; the repository deletes it
/// after the next verified read.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'journal_file_system.dart';
import 'journal_layout.dart';
import 'journal_models.dart';

class JournalPaths {
  const JournalPaths(this.root);

  /// The app support directory the journal lives under.
  final String root;

  String get journalDir => '$root/$kJournalDirName';
  String get sourcesDir => '$root/$kSourcesDirName';
  String get quarantineDir => '$root/$kQuarantineDirName';

  /// S04 recording journal directory (fourth child of the scope root).
  String get recordingDir => '$root/$kRecordingDirName';
  String get indexFile => '$journalDir/$kIndexFileName';
  String activityDir(String id) => '$journalDir/$id';
  String genName(int seq) => '$kGenerationPrefix$seq';
  String genDir(String id, int seq) => '${activityDir(id)}/${genName(seq)}';
  String currentFile(String id) => '${activityDir(id)}/$kCurrentFileName';

  /// Parses `g<seq>`; null for any other name.
  static int? parseGeneration(String name) {
    final m = RegExp(r'^g([0-9]{1,15})$').firstMatch(name);
    return m == null ? null : int.parse(m.group(1)!);
  }
}

/// What a successful generation write produced.
class WrittenGeneration {
  const WrittenGeneration(this.seq, this.commit);

  final int seq;
  final CommitMarker commit;
}

/// A write failed BEFORE the COMMIT rename took effect: the mutation did not
/// happen and the previous committed state is intact.
class GenerationAborted implements Exception {
  const GenerationAborted(this.cause);

  final FileSystemException cause;
}

class JournalGenerationWriter {
  JournalGenerationWriter(this.fs, this.paths);

  final JournalFileSystem fs;
  final JournalPaths paths;

  /// temp file, write, flush, fsync, close, rename.
  Future<void> atomicWrite(String path, Uint8List bytes) async {
    final tmp = '$path$kTempSuffix';
    JournalWriteHandle? handle;
    try {
      handle = await fs.openWrite(tmp);
      await handle.write(bytes);
      await handle.flush();
      await handle.fsync();
      await handle.close();
      handle = null;
      await fs.rename(tmp, path);
    } catch (_) {
      if (handle != null) {
        try {
          await handle.close();
        } catch (_) {}
      }
      try {
        await fs.deleteFile(tmp);
      } catch (_) {}
      rethrow;
    }
  }

  /// Steps 1-3. Throws [GenerationAborted] when the mutation did not commit;
  /// any other error (a simulated crash) propagates untouched. The directory
  /// of an aborted generation is removed best effort (recovery removes it
  /// otherwise).
  Future<WrittenGeneration> write(
    String id,
    int seq,
    JournalRecord record,
    Uint8List streamsBytes,
  ) async {
    final dir = paths.genDir(id, seq);
    try {
      await fs.createDir(dir);
      await atomicWrite('$dir/$kStreamsFileName', streamsBytes);
      final recordBytes = record.encode();
      await atomicWrite('$dir/$kRecordFileName', recordBytes);

      // Read back and verify against the bytes ON DISK, not the bytes in memory.
      final streamsBack = await fs.readBytes('$dir/$kStreamsFileName');
      final recordBack = await fs.readBytes('$dir/$kRecordFileName');
      final streamsSha = sha256Hex(streamsBack);
      if (streamsSha != record.streamHash) {
        throw FileSystemException('read-back stream hash mismatch', dir);
      }
      if (JournalRecord.tryDecode(recordBack) == null) {
        throw FileSystemException('read-back record unreadable', dir);
      }
      final commit = CommitMarker(
        seq: seq,
        recordSha256: sha256Hex(recordBack),
        streamsSha256: streamsSha,
      );
      final commitPath = '$dir/$kCommitFileName';
      try {
        await atomicWrite(commitPath, commit.encode());
      } on FileSystemException {
        // The rename may have happened although it reported an error. If the
        // marker is on disk and valid the mutation IS committed.
        if (await _commitIsValid(dir, seq)) return WrittenGeneration(seq, commit);
        rethrow;
      }
      return WrittenGeneration(seq, commit);
    } on FileSystemException catch (e) {
      try {
        await fs.deleteDir(dir);
      } catch (_) {}
      throw GenerationAborted(e);
    }
  }

  Future<bool> _commitIsValid(String dir, int seq) async {
    try {
      final c = CommitMarker.tryDecode(await fs.readBytes('$dir/$kCommitFileName'));
      return c != null && c.seq == seq;
    } catch (_) {
      return false;
    }
  }

  /// Step 4. Failures are the caller's to swallow: CURRENT is not the truth.
  Future<void> writeCurrent(String id, int seq, String streamHash) =>
      atomicWrite(
        paths.currentFile(id),
        Uint8List.fromList(utf8.encode(jsonEncode({
          'gen': paths.genName(seq),
          'seq': seq,
          'streamHash': streamHash,
        }))),
      );

  /// The generation number CURRENT names, or null when missing or corrupt.
  Future<int?> readCurrent(String id) async {
    try {
      final raw = jsonDecode(utf8.decode(await fs.readBytes(paths.currentFile(id))));
      if (raw is Map && raw['gen'] is String) {
        return JournalPaths.parseGeneration(raw['gen'] as String);
      }
    } catch (_) {}
    return null;
  }

  /// Step 5: one JSON line, append, flush, fsync. [op] is `put`, `delete` or
  /// `synced` (state changes).
  Future<void> appendIndex(String op, String id, int seq) async {
    final h = await fs.openWrite(paths.indexFile, append: true);
    try {
      await h.write(Uint8List.fromList(
          utf8.encode('${jsonEncode({'seq': seq, 'op': op, 'id': id})}\n')));
      await h.flush();
      await h.fsync();
    } finally {
      await h.close();
    }
  }

  /// Rewrites the whole index atomically from [lines] (rebuild / compaction).
  Future<void> rewriteIndex(List<Map<String, Object?>> lines) => atomicWrite(
        paths.indexFile,
        Uint8List.fromList(
            utf8.encode(lines.map((l) => '${jsonEncode(l)}\n').join())),
      );

  /// Reads a whole file. Returns null ONLY when the file genuinely does not
  /// exist; any other read failure (I/O error, locked handle) throws
  /// [JournalUnreadable] so callers never mistake "cannot read now" for
  /// "absent" (a committed generation must survive a transient error).
  Future<Uint8List?> readIfPresent(String path) async {
    try {
      return await fs.readBytes(path);
    } catch (e) {
      var present = true;
      try {
        present = await fs.exists(path);
      } catch (_) {
        // Existence unknown: treat as present, i.e. an I/O error.
      }
      if (!present) return null;
      throw JournalUnreadable(path, e);
    }
  }

  /// Reads a COMMIT marker; null when missing or unparsable (marker invalid).
  /// Throws [JournalUnreadable] on any other I/O error.
  Future<CommitMarker?> readCommit(String id, int seq) async {
    final bytes =
        await readIfPresent('${paths.genDir(id, seq)}/$kCommitFileName');
    if (bytes == null) return null;
    return CommitMarker.tryDecode(bytes);
  }
}

/// A file exists (or may exist) but could not be read because of an I/O error.
/// Distinct from "not found" and from "content invalid".
class JournalUnreadable implements Exception {
  const JournalUnreadable(this.path, this.cause);

  final String path;
  final Object cause;

  @override
  String toString() => 'JournalUnreadable: $path ($cause)';
}
