import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The ML applicability matrix is a partition, and this is what enforces it.
///
/// `core/ML_PLATFORM_ARCHITECTURE.md` §1 classifies every feature module into
/// one of five ML classes. A matrix like that is worth exactly as much as its
/// completeness: the moment a module can be missing from it, "not listed" and
/// "deliberately ML_NOT_JUSTIFIED" become indistinguishable, and the document
/// stops being able to say anything about the modules it does list.
///
/// Writing it correctly once is easy. Keeping it correct across a year of
/// feature work is not, and nobody re-reads a design document when adding a
/// directory. So the check runs in the suite instead.
///
/// This is a documentation test and it is honest about what that means: it
/// proves the matrix COVERS the codebase, not that any classification is
/// right. Whether `recovery` really belongs in ML_OPTIONAL is a judgement no
/// test can hold. Whether `recovery` is in the document at all is exactly the
/// kind of thing a test should hold, because it is the part that rots.
void main() {
  final doc = File('../core/ML_PLATFORM_ARCHITECTURE.md');
  final modulesDir = Directory('lib/features');

  late String matrix;
  late List<String> modules;

  setUpAll(() {
    expect(doc.existsSync(), isTrue,
        reason: 'the ML architecture document moved; re-point this test');
    final src = doc.readAsStringSync();

    // §1 only. §2 is the business-process matrix and names some of the same
    // words in prose, which would make every count below meaningless.
    final start = src.indexOf('## 1. Module applicability matrix');
    final end = src.indexOf('## 2. Business-process matrix');
    expect(start, greaterThan(-1));
    expect(end, greaterThan(start),
        reason: 'the section headings changed; the span below is now wrong');
    matrix = src.substring(start, end);

    modules = modulesDir
        .listSync()
        .whereType<Directory>()
        .map((d) => d.path.replaceAll(r'\', '/').split('/').last)
        .toList()
      ..sort();
  });

  test('every feature module appears in the matrix', () {
    final missing = <String>[];
    for (final m in modules) {
      // Backticked, so `catalog` inside a word like `catalogue` cannot count
      // as a classification. That distinction is not hypothetical here: this
      // document says "catalogue" repeatedly about the exercise data and
      // `catalog` is also a module name.
      if (!matrix.contains('`$m`')) missing.add(m);
    }
    expect(missing, isEmpty,
        reason: 'these feature modules are not classified in '
            'core/ML_PLATFORM_ARCHITECTURE.md §1. An unclassified module is '
            'not the same as one deliberately marked ML_NOT_JUSTIFIED, and '
            'the document cannot tell the reader which it is: $missing');
  });

  test('the stated partition counts sum to the real module count', () {
    // The document asserts its own arithmetic in a "Partition check" line.
    // Left unchecked, that line is the most quietly wrong kind of claim —
    // it reads as verified precisely because it contains numbers.
    // By paragraph, not by line: the document is hard-wrapped at 80 columns,
    // so the claim spans two source lines and a line-based read silently sees
    // only the first four counts.
    final line = matrix
        .split(RegExp(r'\n\s*\n'))
        .firstWhere((p) => p.contains('Partition check'), orElse: () => '')
        .replaceAll('\n', ' ');
    expect(line, isNotEmpty,
        reason: 'the partition-check line was removed from §1');

    final counts = RegExp(r'(\d+)')
        .allMatches(line)
        .map((m) => int.parse(m.group(1)!))
        .toList();
    expect(counts, hasLength(6),
        reason: 'expected five class counts and one total: $line');

    final classes = counts.take(5).toList();
    final stated = counts.last;

    expect(classes.reduce((a, b) => a + b), stated,
        reason: 'the document\'s own five counts do not sum to its stated '
            'total: $line');
    expect(stated, modules.length,
        reason: 'the matrix totals $stated modules but lib/features holds '
            '${modules.length}. Adding a feature module means classifying it, '
            'which is a decision, not bookkeeping — if it needs no ML, say so '
            'under ML_NOT_JUSTIFIED and the count moves with it');
  });

  test('the five class names are all present, so the counts mean something',
      () {
    // Without this, renaming a class heading would leave five integers in the
    // partition line that still sum correctly and no longer label anything.
    for (final cls in const [
      'ML_CORE',
      'ML_AUGMENTED',
      'RULE_BASED_WITH_ML_MONITORING',
      'ML_OPTIONAL',
      'ML_NOT_JUSTIFIED',
    ]) {
      expect(matrix, contains(cls));
    }
  });

  test('the document still refuses ML authority over safety', () {
    // The one line in the architecture that is not a preference. It is
    // restated in §6 as a boundary table, but §1 is where a future editor
    // reclassifying `safety` as ML_AUGMENTED would do the damage, and this is
    // the cheapest place to make that a failing test rather than a diff
    // nobody reviewed.
    final safetyRow = matrix
        .split('\n')
        .firstWhere((l) => l.startsWith('| `safety` |'), orElse: () => '');
    expect(safetyRow, isNotEmpty,
        reason: '`safety` left the RULE_BASED_WITH_ML_MONITORING table');
    expect(safetyRow, contains('never decide'));
  });
}
