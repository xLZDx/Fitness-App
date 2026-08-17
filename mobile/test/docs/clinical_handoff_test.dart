import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The clinical handoff quotes numbers. This is what stops them going stale.
///
/// A clinician's review is bound to the catalogue it was performed against —
/// that is the mechanism by which "validated once" does not silently become
/// "validated forever". If the document says 1,887 rows and the catalogue has
/// moved to 1,912, then either the handoff is describing a version nobody can
/// obtain, or a returned review is being applied to rows it never covered.
/// Both are worse than having no document.
///
/// So the counts in `core/review/CLINICAL_VALIDATION_HANDOFF.md` are asserted
/// against the shipped catalogue, and a change to either forces a change to the
/// other.
void main() {
  final handoff = File('../core/review/CLINICAL_VALIDATION_HANDOFF.md');

  late String doc;
  late int total;
  late int tagged;
  late int untagged;

  setUpAll(() {
    expect(handoff.existsSync(), isTrue,
        reason: 'the clinical handoff is missing: ${handoff.path}');
    doc = handoff.readAsStringSync();

    final rows = <Map<String, dynamic>>[];
    void walk(Object? node) {
      if (node is Map) {
        if (node.containsKey('id') && node.containsKey('steps')) {
          rows.add(Map<String, dynamic>.from(node));
        }
        node.values.forEach(walk);
      } else if (node is List) {
        node.forEach(walk);
      }
    }

    walk(jsonDecode(
        File('assets/data/exercises_vendor.json').readAsStringSync()));

    total = rows.length;
    tagged = rows
        .where((r) => (r['contraindications'] as List?)?.isNotEmpty ?? false)
        .length;
    untagged = total - tagged;
  });

  /// Comma-formatted as the numbers appear in the prose, because that is the
  /// form a reader checks. A test matching the raw integer would pass while
  /// the rendered table said something else — and my first version of this
  /// file did exactly that, asserting `1,887` in one place and `1887` in
  /// another, so the two halves disagreed about what they were checking.
  String pretty(int n) => n >= 1000
      ? '${n ~/ 1000},${(n % 1000).toString().padLeft(3, '0')}'
      : '$n';

  test('the quoted catalogue counts are the real ones', () {
    expect(doc, contains('**${pretty(total)}**'),
        reason: 'the handoff does not quote the measured row count ($total). '
            'A clinician cannot bind a review to a version that does not '
            'exist');
    expect(doc, contains('**${pretty(tagged)}**'), reason: 'tagged = $tagged');
    expect(doc, contains('**$untagged**'), reason: 'untagged = $untagged');
  });

  test('the version-binding section repeats the same counts', () {
    // Section 8 is the part a returned review is stapled to. If it drifts from
    // section 2, the document contradicts itself about what was reviewed.
    final binding = doc.substring(doc.indexOf('## 8. Version binding'));
    expect(binding, contains(pretty(total)));
    expect(binding, contains(pretty(tagged)));
    expect(binding, contains(pretty(untagged)));
  });

  test('the review flag it depends on is still false, and still exists', () {
    // The whole document is addressed to the question this constant asks. If
    // it is flipped without a review coming back, the handoff is describing a
    // state the product has left.
    final src = File(
      'lib/features/equipment/state/safety_coverage_providers.dart',
    ).readAsStringSync();
    expect(src, contains('const bool kSafetyTagsClinicallyReviewed = false'),
        reason: 'either the flag moved, or it was flipped. If flipped, the '
            'returned clinical review must be committed alongside it and this '
            'handoff updated to match');
  });

  test('it asks bounded questions, not "is the app safe"', () {
    // The instruction that shaped it. A vague question returns a vague answer,
    // and a vague answer cannot close D1.
    for (final q in const ['Q1', 'Q2', 'Q3', 'Q4', 'Q5', 'Q6', 'Q7']) {
      expect(doc, contains('### $q'), reason: 'missing $q');
    }
    expect(doc.toLowerCase(), isNot(contains('is sptr safe?')));
  });

  test('it demands a structured result rather than an opinion', () {
    // "Looks good" is not validation evidence, and the document has to say so
    // in a way that survives someone skimming it.
    for (final field in const [
      'reviewer',
      'credentials',
      'scope',
      'catalogue_version',
      'approved_mappings',
      'rejected_mappings',
      'unknown_mappings',
      'limitations',
      'approval_boundary',
    ]) {
      expect(doc, contains('`$field`'), reason: 'missing required field: $field');
    }
  });

  test('it does not claim validation has occurred', () {
    // The one way this document could do harm: read as evidence of the thing
    // it exists to request.
    final lower = doc.toLowerCase();
    for (final banned in const [
      'clinically validated',
      'has been reviewed by a clinician',
      'clinician approved',
    ]) {
      expect(lower, isNot(contains(banned)), reason: '"$banned"');
    }
    expect(doc, contains('EXTERNAL_CLINICAL_VALIDATION_REQUIRED'));
    expect(doc, contains('HOLD'));
  });
}
