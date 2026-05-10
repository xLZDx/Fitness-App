import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/injury_coach/data/injury_protocol_repository.dart';

void main() {
  group('MockInjuryProtocolRepository', () {
    test('matchFor returns protocols when injury overlaps', () async {
      final repo = MockInjuryProtocolRepository();
      final hits = await repo.matchFor(['low_back_strain']);
      expect(hits, isNotEmpty);
      expect(hits.first.id, 'low-back-strain-acute');
    });

    test('matchFor returns empty when nothing overlaps', () async {
      final repo = MockInjuryProtocolRepository();
      final hits = await repo.matchFor(['unrelated_condition']);
      expect(hits, isEmpty);
    });

    test('start / end protocol round-trips', () async {
      final repo = MockInjuryProtocolRepository();
      expect(await repo.activeProtocolId('me'), isNull);
      await repo.startProtocol('me', 'low-back-strain-acute');
      expect(await repo.activeProtocolId('me'), 'low-back-strain-acute');
      await repo.endProtocol('me');
      expect(await repo.activeProtocolId('me'), isNull);
    });

    test('byId returns correct protocol', () async {
      final repo = MockInjuryProtocolRepository();
      final p = await repo.byId('shoulder-impingement-mild');
      expect(p, isNotNull);
      expect(p!.targetInjuries, contains('shoulder_impingement'));
    });
  });
}
