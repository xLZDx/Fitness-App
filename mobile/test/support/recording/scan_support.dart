// Source-scan helper for the S04 K rows. Resolves one scan set from the
// package root (flutter test runs with cwd = mobile/) and refuses an empty or
// anchor-less set, so a scan cannot go green by scanning nothing.
import 'dart:io';

class SourceFile {
  SourceFile(this.path, this.text);
  final String path;
  final String text;

  /// Lines with // comments removed (string-unaware, adequate for imports and
  /// identifiers).
  late final String code = text
      .split('\n')
      .map((l) {
        final i = l.indexOf('//');
        return i < 0 ? l : l.substring(0, i);
      })
      .join('\n');

  List<String> get importLines => text
      .split('\n')
      .where((l) => l.trimLeft().startsWith('import ') ||
          l.trimLeft().startsWith('export '))
      .toList();
}

List<SourceFile> dartFilesUnder(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) {
    throw StateError('scan directory missing: $dir');
  }
  final out = <SourceFile>[];
  for (final e in d.listSync(recursive: true, followLinks: false)) {
    if (e is File && e.path.endsWith('.dart')) {
      final p = e.path.replaceAll('\\', '/');
      out.add(SourceFile(p, e.readAsStringSync()));
    }
  }
  out.sort((a, b) => a.path.compareTo(b.path));
  return out;
}

/// The recording feature's production sources, with a sanity check.
List<SourceFile> recordingSources() {
  final files = dartFilesUnder('lib/features/recording');
  if (files.length < 40) {
    throw StateError('recording scan set too small: ${files.length}');
  }
  const anchors = [
    'lib/features/recording/location/geolocator_location_source.dart',
    'lib/features/recording/location/location_source.dart',
    'lib/features/recording/state/recorder_controller.dart',
    'lib/features/recording/pipeline/recorder_pipeline.dart',
    'lib/features/recording/permissions/permission_service.dart',
  ];
  for (final a in anchors) {
    if (!files.any((f) => f.path.endsWith(a))) {
      throw StateError('anchor missing from scan set: $a');
    }
  }
  return files;
}

/// Every production source of the app (for "outside the seam" scans).
List<SourceFile> allLibSources() {
  final files = dartFilesUnder('lib');
  if (files.length < 200) {
    throw StateError('lib scan set too small: ${files.length}');
  }
  return files;
}
