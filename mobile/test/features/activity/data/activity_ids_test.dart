// S02 test epic 3, U10: the native-session id is deterministic (design 9).
//
// Oracle: the id is `act_` + the lowercase hex SHA-1 of the text
// `<sourceId>|<externalId>`. The expected digests below are literals computed
// outside the production code (sha1 of the ASCII key), so a changed key format
// or hash fails here.
import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/data/native_session_id.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/synthetic_activity_corpus.dart';

final RegExp _idPattern = RegExp(r'^act_[0-9a-f]{40}$');

void main() {
  final corpus = SyntheticCorpus.build();

  group('U10 native dedup: deterministic id', () {
    test('literal vectors: id = act_ + sha1 of the key text', () {
      // Digests computed with `sha1sum` over the exact ASCII text.
      expect(nativeActivityId('3f2b8c1e-5d4a-4e0b-9a77-0c1d2e3f4a5b'),
          'act_c8fdc580f75c9b601f8008d07a3c7de3f398552e');
      expect(
          activityIdFor(
              sourceId: 'garmin', externalId: '42', startUtc: DateTime.utc(2026)),
          'act_2f4e2b8e455ddca992d2d3f09de8f97ca183cc26');
      // No external id: the key is `<sourceId>|start:<epoch ms>`.
      expect(activityIdFor(sourceId: 'garmin', startUtc: DateTime.utc(2026)),
          'act_287347b933da75d07dfd55c9a6e7a30446623d52');
    });

    test('the same sourceId|externalId gives the same id, any number of times',
        () {
      final ids = {
        for (var i = 0; i < 50; i++) nativeActivityId(kFixedNativeUuid),
      };
      expect(ids, hasLength(1));
      // The generic function agrees with the native helper (same key).
      expect(
        activityIdFor(
          sourceId: 'app',
          externalId: kFixedNativeUuid,
          startUtc: DateTime.utc(2030, 1, 1),
        ),
        nativeActivityId(kFixedNativeUuid),
      );
    });

    test('the id does not depend on the start time when an external id exists',
        () {
      final a = activityIdFor(
          sourceId: 'garmin', externalId: 'x1', startUtc: DateTime.utc(2020));
      final b = activityIdFor(
          sourceId: 'garmin', externalId: 'x1', startUtc: DateTime.utc(2031, 6, 7, 8));
      expect(a, b);
    });

    test('without an external id the start time IS the key (control)', () {
      final a = activityIdFor(sourceId: 'garmin', startUtc: DateTime.utc(2020));
      final b = activityIdFor(sourceId: 'garmin', startUtc: DateTime.utc(2021));
      expect(a, isNot(b));
      expect(
          activityIdFor(sourceId: 'garmin', startUtc: DateTime.utc(2020)), a);
    });

    test('1000 different recording uuids give 1000 different ids, all well formed',
        () {
      final r = SplitMix64(7);
      final ids = <String>{};
      for (var i = 0; i < 1000; i++) {
        final uuid = '${r.nextU64().toRadixString(16)}-$i';
        final id = nativeActivityId(uuid);
        expect(id, matches(_idPattern), reason: uuid);
        ids.add(id);
      }
      expect(ids, hasLength(1000), reason: 'two different externalIds collided');
    });

    test('two different externalIds that differ in one character differ', () {
      expect(nativeActivityId('abc'), isNot(nativeActivityId('abd')));
      expect(nativeActivityId('abc'), isNot(nativeActivityId('ABC')));
      expect(nativeActivityId('abc'), isNot(nativeActivityId('abc ')));
    });

    test('the same externalId under two source ids gives two ids', () {
      final a = activityIdFor(
          sourceId: 'garmin', externalId: '42', startUtc: DateTime.utc(2026));
      final b = activityIdFor(
          sourceId: 'strava', externalId: '42', startUtc: DateTime.utc(2026));
      expect(a, isNot(b));
    });

    test('every one of the 100 valid corpus ids matches ^act_[0-9a-f]{40}\$', () {
      expect(corpus.valid, hasLength(100));
      for (final s in corpus.valid) {
        expect(s.id, matches(_idPattern), reason: s.id);
      }
      expect({for (final s in corpus.valid) s.id}, hasLength(100));
    });

    test('the pattern itself rejects bad ids (the instrument can fail)', () {
      for (final bad in [
        'act_${'A' * 40}', // upper case
        'act_${'a' * 39}', // short
        'act_${'a' * 41}', // long
        'ACT_${'a' * 40}',
        'act-${'a' * 40}',
        'act_${'g' * 40}', // not hex
        ' act_${'a' * 40}',
      ]) {
        expect(_idPattern.hasMatch(bad), isFalse, reason: bad);
      }
    });

    test('an empty recording uuid is refused (all empty ones would collapse)', () {
      expect(() => nativeActivityId(''), throwsArgumentError);
      expect(
        () => nativeSourceRecord(
            recordingUuid: '', importedAt: DateTime.utc(2026)),
        throwsArgumentError,
      );
    });

    test('the native provenance record carries the same key as the id', () {
      final rec = nativeSourceRecord(
          recordingUuid: kFixedNativeUuid, importedAt: DateTime.utc(2026, 1, 1));
      expect(rec.sourceId, kNativeSourceId);
      expect(rec.externalId, kFixedNativeUuid);
      expect(rec.dedupKey, 'app|$kFixedNativeUuid');
      expect(
        activityIdFor(
            sourceId: rec.sourceId,
            externalId: rec.externalId,
            startUtc: DateTime.utc(1999)),
        nativeActivityId(kFixedNativeUuid),
      );
    });

    test('the fixed-uuid corpus record uses exactly this id', () {
      final id = corpus.edgeCases['E-13'];
      expect(id, isNotNull, reason: 'the corpus must hold the fixed-uuid recording');
      final s = corpus.byId(id!);
      expect(s.provenance.first.externalId, kFixedNativeUuid);
      expect(s.id,
          activityIdFor(
              sourceId: s.provenance.first.sourceId,
              externalId: kFixedNativeUuid,
              startUtc: s.startUtc));
    });
  });
}
