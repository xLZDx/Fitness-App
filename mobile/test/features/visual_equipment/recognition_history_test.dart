import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/visual_equipment/data/recognition_history.dart';

/// Base instant for every test. UTC so the assertions read the same way the
/// model stores them.
final _t0 = DateTime.utc(2026, 7, 29, 10, 0);

RecognitionEntry _entry(
  String id, {
  Duration after = Duration.zero,
  double confidence = 0.5,
  RecognitionSource? source,
}) =>
    RecognitionEntry(
      equipmentId: id,
      recognisedAt: _t0.add(after),
      confidence: confidence,
      source: source,
    );

void main() {
  group('RecognitionEntry', () {
    test('JSON round-trip preserves every field', () {
      final entry = RecognitionEntry(
        equipmentId: 'lat_pulldown',
        recognisedAt: _t0,
        confidence: 0.82,
        source: RecognitionSource.live,
      );

      final restored = RecognitionEntry.fromJson(entry.toJson());

      expect(restored, entry);
      expect(restored.hashCode, entry.hashCode);
      expect(restored.equipmentId, 'lat_pulldown');
      expect(restored.recognisedAt, _t0);
      expect(restored.confidence, 0.82);
      expect(restored.source, RecognitionSource.live);
    });

    test('JSON round-trip works without a source', () {
      final entry = _entry('leg_press', confidence: 0.4);
      final json = entry.toJson();

      expect(json.containsKey('source'), isFalse);
      expect(RecognitionEntry.fromJson(json), entry);
      expect(RecognitionEntry.fromJson(json).source, isNull);
    });

    test('normalises recognisedAt to UTC so equality survives the round-trip',
        () {
      final local = DateTime(2026, 7, 29, 12, 30);
      final entry = _entry('rower').copyWith(recognisedAt: local);

      expect(entry.recognisedAt.isUtc, isTrue);
      expect(entry.recognisedAt, local.toUtc());
      expect(RecognitionEntry.fromJson(entry.toJson()), entry);
    });

    test('an unknown source string decodes to null instead of throwing', () {
      final entry = RecognitionEntry.fromJson({
        'equipmentId': 'smith_machine',
        'recognisedAt': _t0.toIso8601String(),
        'confidence': 0.6,
        'source': 'telepathy',
      });

      expect(entry.source, isNull);
      expect(entry.equipmentId, 'smith_machine');
    });

    test('value equality distinguishes entries that differ in one field', () {
      expect(_entry('a'), _entry('a'));
      expect(_entry('a'), isNot(_entry('b')));
      expect(_entry('a'), isNot(_entry('a', confidence: 0.6)));
      expect(_entry('a'), isNot(_entry('a', after: const Duration(hours: 1))));
      expect(
        _entry('a'),
        isNot(_entry('a', source: RecognitionSource.qr)),
      );
    });

    test('a non-date recognisedAt is rejected loudly', () {
      expect(
        () => RecognitionEntry.fromJson({
          'equipmentId': 'x',
          'recognisedAt': 12345,
          'confidence': 0.5,
        }),
        throwsArgumentError,
      );
    });
  });

  group('RecognitionDedup', () {
    test('the window is 5 minutes', () {
      expect(RecognitionDedup.window, const Duration(minutes: 5));
    });

    test('sightings inside the window are the same sighting', () {
      final first = _entry('bench');
      expect(
        RecognitionDedup.isSameSighting(
            first, _entry('bench', after: const Duration(minutes: 4, seconds: 59))),
        isTrue,
      );
      expect(
        RecognitionDedup.isSameSighting(
            first, _entry('bench', after: RecognitionDedup.window)),
        isTrue,
        reason: 'exactly at the boundary still counts as the same sighting',
      );
      expect(
        RecognitionDedup.isSameSighting(
            first, _entry('bench', after: const Duration(minutes: 5, seconds: 1))),
        isFalse,
      );
    });

    test('an out-of-order write is still matched to the same sighting', () {
      final later = _entry('bench', after: const Duration(minutes: 4));
      expect(RecognitionDedup.isSameSighting(later, _entry('bench')), isTrue);
    });

    test('different machines are never the same sighting', () {
      expect(RecognitionDedup.isSameSighting(_entry('bench'), _entry('squat')),
          isFalse);
    });

    test('merge inside the window keeps the best confidence', () {
      final merged = RecognitionDedup.merge(
        _entry('bench', confidence: 0.9),
        _entry('bench', after: const Duration(minutes: 1), confidence: 0.3),
      );

      expect(merged.confidence, 0.9);
      expect(merged.recognisedAt, _t0.add(const Duration(minutes: 1)),
          reason: 'timestamp always advances to the newest sighting');
    });

    test('merge outside the window adopts the fresh confidence', () {
      final merged = RecognitionDedup.merge(
        _entry('bench', confidence: 0.9),
        _entry('bench', after: const Duration(hours: 2), confidence: 0.3),
      );

      expect(merged.confidence, 0.3);
      expect(merged.recognisedAt, _t0.add(const Duration(hours: 2)));
    });

    test('merge never moves an entry backwards in time', () {
      final merged = RecognitionDedup.merge(
        _entry('bench', after: const Duration(minutes: 4)),
        _entry('bench'),
      );

      expect(merged.recognisedAt, _t0.add(const Duration(minutes: 4)));
    });

    test('merge keeps the previous source when the incoming one is null', () {
      final merged = RecognitionDedup.merge(
        _entry('bench', source: RecognitionSource.qr),
        _entry('bench', after: const Duration(minutes: 1)),
      );

      expect(merged.source, RecognitionSource.qr);
    });

    test('merge prefers the incoming source when it has one', () {
      final merged = RecognitionDedup.merge(
        _entry('bench', source: RecognitionSource.live),
        _entry('bench',
            after: const Duration(minutes: 1), source: RecognitionSource.qr),
      );

      expect(merged.source, RecognitionSource.qr);
    });

    test('apply folds a repeat instead of appending a second row', () {
      var history = <RecognitionEntry>[];
      history = RecognitionDedup.apply(history, _entry('bench'));
      history = RecognitionDedup.apply(
          history, _entry('bench', after: const Duration(minutes: 1)));

      expect(history, hasLength(1));
    });

    test('apply appends a genuinely different machine', () {
      var history = RecognitionDedup.apply(const [], _entry('bench'));
      history = RecognitionDedup.apply(
          history, _entry('squat', after: const Duration(minutes: 1)));

      expect(history.map((e) => e.equipmentId), ['squat', 'bench']);
    });

    test('sortNewestFirst orders by time, breaking ties on equipmentId', () {
      final sorted = RecognitionDedup.sortNewestFirst([
        _entry('b'),
        _entry('z', after: const Duration(hours: 1)),
        _entry('a'),
      ]);

      expect(sorted.map((e) => e.equipmentId), ['z', 'a', 'b']);
    });

    test('the returned list is unmodifiable', () {
      final sorted = RecognitionDedup.sortNewestFirst([_entry('a')]);
      expect(() => sorted.add(_entry('b')), throwsUnsupportedError);
    });
  });

  group('MockRecognitionHistoryRepository', () {
    late MockRecognitionHistoryRepository repo;

    setUp(() => repo = MockRecognitionHistoryRepository());
    tearDown(() => repo.dispose());

    test('starts empty', () async {
      expect(await repo.list(), isEmpty);
    });

    test('records a single sighting', () async {
      await repo.record(_entry('lat_pulldown', confidence: 0.7));

      final history = await repo.list();
      expect(history, hasLength(1));
      expect(history.single.equipmentId, 'lat_pulldown');
      expect(history.single.confidence, 0.7);
    });

    test('50 live frames of one machine leave exactly one row', () async {
      for (var i = 0; i < 50; i++) {
        await repo.record(_entry(
          'lat_pulldown',
          after: Duration(seconds: i * 2),
          confidence: 0.4,
          source: RecognitionSource.live,
        ));
      }

      final history = await repo.list();
      expect(history, hasLength(1),
          reason: 'a burst inside the 5-minute window is one sighting');
      expect(history.single.recognisedAt,
          _t0.add(const Duration(seconds: 98)),
          reason: 'the row carries the latest frame timestamp');
    });

    test('a repeat inside the window updates rather than appends', () async {
      await repo.record(_entry('bench', confidence: 0.9));
      await repo.record(
          _entry('bench', after: const Duration(minutes: 3), confidence: 0.2));

      final history = await repo.list();
      expect(history, hasLength(1));
      expect(history.single.confidence, 0.9, reason: 'best look is kept');
      expect(history.single.recognisedAt, _t0.add(const Duration(minutes: 3)));
    });

    test('a repeat outside the window refreshes the same row', () async {
      await repo.record(_entry('bench', confidence: 0.9));
      await repo.record(
          _entry('bench', after: const Duration(days: 3), confidence: 0.2));

      final history = await repo.list();
      expect(history, hasLength(1),
          reason: 'the store is keyed by machine, never appended');
      expect(history.single.confidence, 0.2,
          reason: 'a new visit re-measures rather than keeping a stale peak');
      expect(history.single.recognisedAt, _t0.add(const Duration(days: 3)));
    });

    test('list returns entries newest first', () async {
      await repo.record(_entry('bench'));
      await repo.record(_entry('squat', after: const Duration(hours: 2)));
      await repo.record(_entry('rower', after: const Duration(hours: 1)));

      final history = await repo.list();
      expect(history.map((e) => e.equipmentId), ['squat', 'rower', 'bench']);
    });

    test('recording an older machine again floats it back to the top',
        () async {
      await repo.record(_entry('bench'));
      await repo.record(_entry('squat', after: const Duration(hours: 1)));
      await repo.record(_entry('bench', after: const Duration(hours: 2)));

      expect((await repo.list()).map((e) => e.equipmentId), ['bench', 'squat']);
    });

    test('watch replays the current history to a new subscriber', () async {
      await repo.record(_entry('bench'));

      final first = await repo.watch().first;
      expect(first.map((e) => e.equipmentId), ['bench']);
    });

    test('watch emits on every record, newest first', () async {
      final emissions = <List<RecognitionEntry>>[];
      final sub = repo.watch().listen(emissions.add);
      await Future<void>.delayed(Duration.zero);

      await repo.record(_entry('bench'));
      await repo.record(_entry('squat', after: const Duration(hours: 1)));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(emissions.first, isEmpty, reason: 'replay of the empty store');
      expect(emissions.last.map((e) => e.equipmentId), ['squat', 'bench']);
    });

    test('watch does not emit an extra row for a de-duped repeat', () async {
      final emissions = <List<RecognitionEntry>>[];
      final sub = repo.watch().listen(emissions.add);
      await Future<void>.delayed(Duration.zero);

      await repo.record(_entry('bench'));
      await repo.record(_entry('bench', after: const Duration(minutes: 2)));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(emissions.last, hasLength(1));
    });

    test('clear empties the history and emits the empty list', () async {
      await repo.record(_entry('bench'));
      await repo.record(_entry('squat', after: const Duration(hours: 1)));
      expect(await repo.list(), hasLength(2));

      final emissions = <List<RecognitionEntry>>[];
      final sub = repo.watch().listen(emissions.add);
      await Future<void>.delayed(Duration.zero);
      await repo.clear();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(await repo.list(), isEmpty);
      expect(emissions.last, isEmpty);
    });

    test('honours a configured latency without changing the result', () async {
      final slow = MockRecognitionHistoryRepository(
        latency: const Duration(milliseconds: 5),
      );
      addTearDown(slow.dispose);

      await slow.record(_entry('bench'));
      expect(await slow.list(), hasLength(1));
    });
  });
}
