// Shared path and golden-update helpers of the S02 Dart unit tests. Test-only.
import 'dart:io';

/// The repository root: the nearest parent of the working directory that holds
/// `firestore.rules` (works whether `flutter test` runs from `mobile/` or from
/// the root).
Directory repoRoot() {
  var dir = Directory.current.absolute;
  for (var i = 0; i < 8; i++) {
    if (File('${dir.path}/firestore.rules').existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError('repository root (firestore.rules) not found from '
      '${Directory.current.path}');
}

File repoFile(String relative) => File('${repoRoot().path}/$relative');

File supportFile(String name) => repoFile('mobile/test/support/$name');

/// True when the run was started with `S02_UPDATE_GOLDEN=1` (the explicit
/// update flag of plan 2.1; without it every golden is only compared).
bool get updateGolden => Platform.environment['S02_UPDATE_GOLDEN'] == '1';
