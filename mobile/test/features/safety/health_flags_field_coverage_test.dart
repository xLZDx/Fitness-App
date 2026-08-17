import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A field added to [HealthFlags] must reach every method that enumerates its
/// fields — checked against the source, because the compiler does not check it.
///
/// This bug has now happened three times in one class, each time in a different
/// method, each time invisibly:
///
/// ```text
/// F014 shipped   -> field in toJson/copyWith, absent from fromJson
///                   (the block evaporated on the next app launch)
/// F014 shipped   -> field in fromJson, absent from operator ==
///                   (HealthFlags(reported) == HealthFlags.empty, so the merge
///                    treated the answer as "nothing stored" and dropped it)
/// N03 rule       -> field serialised into `health`, absent from the Firestore
///                   rule that is supposed to reject health content
/// ```
///
/// Every one of those passed the analyzer, passed the suite, and passed review.
/// Dart has no exhaustiveness check for "did you list the field again", so the
/// only thing that can catch the fourth instance is a test that reads the file.
///
/// It deliberately checks the SOURCE rather than behaviour. A behavioural test
/// has to be written per field, which means remembering — the exact thing that
/// failed three times.
void main() {
  final file = File('lib/features/safety/data/health_flags.dart');
  final source = file.readAsStringSync();

  /// The class body, so an identically named member of another class in the
  /// same file cannot satisfy a check by accident.
  // These helpers run at collection time as well as inside tests, so they
  // throw rather than call `expect`, which is only legal inside a test body.
  String classBody() {
    final start = source.indexOf('class HealthFlags {');
    if (start < 0) throw StateError('class HealthFlags not found');
    return source.substring(start);
  }

  /// Members in the order they appear. Slicing between consecutive anchors
  /// gives each member's text without needing to balance braces.
  const anchors = <String>[
    'bool get isUnanswered',
    'bool get isEmpty',
    'Set<MovementRestriction> get unenforceableRestrictions',
    'Set<String> get blockedRegionTags',
    'Map<String, dynamic> toJson()',
    'static HealthFlags fromJson',
    'HealthFlags copyWith({',
    'bool operator ==(',
    'int get hashCode',
    'String toString()',
  ];

  Map<String, String> members() {
    final body = classBody();
    final at = <String, int>{};
    for (final a in anchors) {
      final i = body.indexOf(a);
      if (i < 0) {
        throw StateError(
          'anchor "$a" no longer appears in HealthFlags. If the member was '
          'renamed or removed, update this list deliberately — do not delete '
          'the anchor to make the test pass.',
        );
      }
      at[a] = i;
    }
    final ordered = at.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    final out = <String, String>{};
    for (var i = 0; i < ordered.length; i++) {
      final end =
          i + 1 < ordered.length ? ordered[i + 1].value : body.length;
      out[ordered[i].key] = body.substring(ordered[i].value, end);
    }
    return out;
  }

  /// `final Foo? bar;` / `final Set<Baz> qux;` declared on the class.
  ///
  /// Nullability is read from the declaration rather than hardcoded, because
  /// it is what decides whether a field can be "unanswered": a nullable field
  /// distinguishes "not asked" from "answered", a non-nullable one cannot.
  Map<String, bool> declaredFields() {
    final body = classBody();
    final ctorEnd = body.indexOf('});');
    final afterCtor = body.substring(ctorEnd);
    final re = RegExp(r'^\s*final\s+([\w<>, ]+?)(\?)?\s+(\w+);',
        multiLine: true);
    final out = <String, bool>{};
    for (final m in re.allMatches(afterCtor)) {
      out[m.group(3)!] = m.group(2) == '?';
    }
    return out;
  }

  test('the parser found the fields it is supposed to police', () {
    // A source-scanning test that silently matches nothing is worse than no
    // test, because it reports success. This is the guard on the guard.
    final fields = declaredFields();
    expect(fields, isNotEmpty);
    expect(fields.keys, contains('restrictions'));
    expect(fields.keys, contains('professionalGuidance'));
    expect(fields['professionalGuidance'], isTrue, reason: 'expected nullable');
    expect(fields['restrictions'], isFalse, reason: 'expected non-nullable');
    expect(fields.length, greaterThanOrEqualTo(5));
  });

  test('the anchors sliced into non-trivial member bodies', () {
    final m = members();
    for (final e in m.entries) {
      expect(e.value.length, greaterThan(e.key.length + 10),
          reason: '${e.key} sliced to nothing');
    }
  });

  group('every declared field appears in', () {
    final fields = declaredFields();
    final m = members();

    /// The members that must name every field. `toString` is excluded on
    /// purpose — it is debug output and cannot cause a safety defect.
    const mustNameEveryField = <String>[
      'Map<String, dynamic> toJson()',
      'static HealthFlags fromJson',
      'HealthFlags copyWith({',
      'bool operator ==(',
      'int get hashCode',
    ];

    for (final member in mustNameEveryField) {
      test(member, () {
        for (final f in fields.keys) {
          expect(
            m[member],
            contains(f),
            reason: '$member does not mention "$f". Every field must be '
                'carried by all of: ${mustNameEveryField.join(', ')}. '
                'A field missing from one of them is silently dropped at '
                'exactly one layer, which is how F014 was lost twice.',
          );
        }
      });
    }

    test('bool get isUnanswered — every NULLABLE field', () {
      // `restrictions` is excluded by design: an empty set cannot distinguish
      // "no restrictions" from "not asked", which is why the enums are
      // nullable and it is not. That reasoning is in the class doc.
      for (final e in fields.entries) {
        if (!e.value) continue;
        expect(
          m['bool get isUnanswered'],
          contains(e.key),
          reason: 'isUnanswered ignores nullable field "${e.key}", so a user '
              'who answered only that question reads as never asked.',
        );
      }
    });
  });

  test('HealthHistory.isEmpty does not ask through operator ==', () {
    // The specific regression: `flags == HealthFlags.empty` made a safety
    // decision depend on a hand-written equality that a new field can be
    // added without. It must ask HealthFlags directly instead.
    final profile =
        File('lib/features/profile/data/profile_models.dart').readAsStringSync();
    expect(
      profile,
      isNot(contains('flags == HealthFlags.empty')),
      reason: 'isEmpty decides whether the locally stored health block wins '
          'over the server copy. Routing it through operator == is what threw '
          'the F014 answer away.',
    );
    expect(profile, contains('flags.isEmpty'));
  });
}
