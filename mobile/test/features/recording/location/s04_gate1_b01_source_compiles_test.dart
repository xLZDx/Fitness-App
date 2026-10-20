// S04 gate 1, finding B-01: geolocator_location_source.dart carried leftover
// junk text ("import a location package ...") and did not compile, so any
// importer of the file failed. The first test imports the file (a compile
// error turns the whole file red); the second scans every production source
// of the recording feature for stray column-0 text.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/features/recording/location/geolocator_location_source.dart';
import 'package:fitness_app/features/recording/location/location_source.dart';

import '../../../support/recording/scan_support.dart';

/// A column-0 line is acceptable when it is a comment, a continuation of a
/// comment/closing token, or starts a declaration / directive / annotation / a
/// type identifier.
final RegExp _allowedColumn0 = RegExp(
  r'^(//|/\*|\*|(import|export)\s+[\x27"]|part\s+([\x27"]|of\b)|library\b|'
  r'class\b|abstract\b|enum\b|typedef\b|mixin\b|extension\b|final\b|'
  r'const\b|var\b|void\b|Future\b|@|\}|\)|\]|\(|'
  r'(sealed|base|interface|late|external|static|int|double|bool|num|dynamic)\b|'
  r'[A-Z][A-Za-z0-9_]*\b)',
);

/// Returns the offending lines (`path:line: text`) of [source].
List<String> junkColumn0Lines(String path, String source) {
  final out = <String>[];
  final lines = source.split('\n');
  var inBlockComment = false;
  for (var i = 0; i < lines.length; i++) {
    final raw = lines[i].replaceAll('\r', '');
    if (raw.isEmpty || raw.trim().isEmpty) continue;
    if (inBlockComment) {
      if (raw.contains('*/')) inBlockComment = false;
      continue;
    }
    if (raw.startsWith(' ') || raw.startsWith('\t')) continue; // not column 0
    if (raw.startsWith('/*')) {
      if (!raw.contains('*/')) inBlockComment = true;
      continue;
    }
    if (!_allowedColumn0.hasMatch(raw)) {
      out.add('$path:${i + 1}: $raw');
    }
  }
  return out;
}

void main() {
  test('B-01: the geolocator adapter imports and constructs (it compiles)', () {
    // A compile error in the adapter would fail loading of this whole file.
    final LocationSource source = GeolocatorLocationSource();
    expect(source, isA<GeolocatorLocationSource>());
  });

  test('B-01: the adapter file has no leftover text between its header comment '
      'and its first import', () {
    final text = File(
            'lib/features/recording/location/geolocator_location_source.dart')
        .readAsStringSync();
    expect(junkColumn0Lines('geolocator_location_source.dart', text), isEmpty);
    // The first non-comment, non-empty line must be the geolocator import.
    final first = text
        .split('\n')
        .map((l) => l.replaceAll('\r', ''))
        .firstWhere((l) => l.trim().isNotEmpty && !l.startsWith('//'));
    expect(first, "import 'package:geolocator/geolocator.dart';");
  });

  test('B-01: no non-comment junk at column 0 anywhere in lib/features/recording',
      () {
    final files = recordingSources();
    final bad = <String>[];
    for (final f in files) {
      bad.addAll(junkColumn0Lines(f.path, f.text));
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('B-01: the scan itself detects the original defect (self-check)', () {
    const broken = '// header\n'
        '//\n'
        'import a location package (S04-R-003). The\n'
        '// extension keeps it out of the Dart analysis until the dependency exists.\n';
    final found = junkColumn0Lines('x.dart', broken);
    expect(found, hasLength(1));
    expect(found.single, contains('import a location package'));

    const alsoJunk = "import 'a.dart';\nfoo bar baz qux\nclass A {}\n";
    // A plain prose line must be flagged.
    expect(junkColumn0Lines('y.dart', alsoJunk), hasLength(1));

    const fine = "// c\n/* block\n   text */\nimport 'a.dart';\n\n"
        'class A {\n  int x = 0;\n}\n'
        '@override\nFuture<void> f() async {}\n'
        'final int z = 1;\nconst k = 2;\nvoid main() {}\n'
        'String get name => "";\nMap<String, int> m = {};\n';
    expect(junkColumn0Lines('z.dart', fine), isEmpty);
  });
}
