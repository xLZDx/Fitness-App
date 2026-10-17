// S02 test epic 10b: remediation D, ActivityFlags. Oracle:
// docs/phase2/s02/S02_REMEDIATION_D_TEST_NOTES.md (first bullet) and design
// 12.1: two independent flags, both OFF by default; journalEnabled is
// localJournal || cloudSync.
import 'package:fitness_app/core/config/activity_flags.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // (cloudSync, localJournal, journalEnabled): the truth table of the notes.
  const table = <(bool, bool, bool)>[
    (false, false, false),
    (false, true, true),
    (true, false, true),
    (true, true, true),
  ];

  final all = [
    for (final (c, l, _) in table) ActivityFlags(cloudSync: c, localJournal: l),
  ];

  test('both flags default to false', () {
    const f = ActivityFlags();
    expect(f.cloudSync, isFalse);
    expect(f.localJournal, isFalse);
    expect(f.journalEnabled, isFalse);
  });

  for (final (c, l, enabled) in table) {
    test('journalEnabled cloudSync=$c localJournal=$l -> $enabled', () {
      expect(ActivityFlags(cloudSync: c, localJournal: l).journalEnabled,
          enabled);
    });
  }

  test('localJournal alone does not turn the cloud on', () {
    expect(const ActivityFlags(localJournal: true).cloudSync, isFalse);
  });

  test('cloudSync alone does not set localJournal but enables the journal',
      () {
    const f = ActivityFlags(cloudSync: true);
    expect(f.localJournal, isFalse);
    expect(f.journalEnabled, isTrue);
  });

  test('== distinguishes all four combinations and equals itself', () {
    for (var i = 0; i < all.length; i++) {
      for (var j = 0; j < all.length; j++) {
        expect(all[i] == all[j], i == j, reason: 'pair $i/$j');
      }
    }
    expect(const ActivityFlags(cloudSync: true, localJournal: true),
        const ActivityFlags(localJournal: true, cloudSync: true));
  });

  test('hashCode distinguishes all four combinations', () {
    expect({for (final f in all) f.hashCode}, hasLength(4));
    expect(const ActivityFlags(localJournal: true).hashCode,
        const ActivityFlags(localJournal: true).hashCode);
  });

  test('toString names both flags and differs for all four combinations',
      () {
    final texts = {for (final f in all) f.toString()};
    expect(texts, hasLength(4));
    expect(const ActivityFlags(cloudSync: true).toString(),
        contains('cloudSync: true'));
    expect(const ActivityFlags(cloudSync: true).toString(),
        contains('localJournal: false'));
    expect(const ActivityFlags(localJournal: true).toString(),
        contains('localJournal: true'));
  });

  test('S03-0: compileTime has the local journal ON and the cloud OFF unless '
      '--dart-define\'d (default build)', () {
    expect(ActivityFlags.compileTime.localJournal, isTrue,
        reason: 'the default build opens the local journal (S03-0)');
    expect(ActivityFlags.compileTime.cloudSync, isFalse,
        reason: 'the cloud stays an operator action');
    expect(ActivityFlags.compileTime.journalEnabled, isTrue);
    // The constructor defaults stay false: explicit values keep their meaning.
    expect(const ActivityFlags().localJournal, isFalse);
  });

  test('activityFlagsProvider defaults to compileTime and can be overridden',
      () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(activityFlagsProvider), ActivityFlags.compileTime);
    final o = ProviderContainer(overrides: [
      activityFlagsProvider
          .overrideWithValue(const ActivityFlags(localJournal: true)),
    ]);
    addTearDown(o.dispose);
    expect(o.read(activityFlagsProvider).localJournal, isTrue);
  });
}
