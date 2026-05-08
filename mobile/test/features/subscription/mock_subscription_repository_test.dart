import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/subscription/data/mock_subscription_repository.dart';
import 'package:fitness_app/features/subscription/data/subscription_models.dart';

Subscription _s(String uid,
        {SubscriptionTier tier = SubscriptionTier.free,
        SubscriptionStatus status = SubscriptionStatus.none}) =>
    Subscription(uid: uid, tier: tier, status: status);

void main() {
  group('MockSubscriptionRepository', () {
    late MockSubscriptionRepository repo;

    setUp(() => repo = MockSubscriptionRepository(latency: Duration.zero));
    tearDown(() => repo.dispose());

    test('save then watch emits the saved record', () async {
      final sub = _s('u', tier: SubscriptionTier.standard,
          status: SubscriptionStatus.trial);
      await repo.save(sub);
      expect(await repo.watch('u').first, sub);
    });

    test('watch emits null when no record exists', () async {
      expect(await repo.watch('nobody').first, isNull);
    });

    test('save replaces the record (one per uid)', () async {
      await repo.save(_s('u', tier: SubscriptionTier.standard,
          status: SubscriptionStatus.trial));
      await repo.save(_s('u', tier: SubscriptionTier.celebrityTrainer,
          status: SubscriptionStatus.active));

      final out = await repo.watch('u').first;
      expect(out!.tier, SubscriptionTier.celebrityTrainer);
      expect(out.status, SubscriptionStatus.active);
    });

    test('cached returns the latest saved record', () async {
      await repo.save(_s('u', tier: SubscriptionTier.standard,
          status: SubscriptionStatus.active));
      expect(repo.cached('u')!.tier, SubscriptionTier.standard);
    });

    test('delete clears the record', () async {
      await repo.save(_s('u', status: SubscriptionStatus.active));
      await repo.delete('u');
      expect(repo.cached('u'), isNull);
    });

    test('watch streams subsequent saves', () async {
      final received = <Subscription?>[];
      final sub = repo.watch('u').listen(received.add);
      await repo.save(_s('u', status: SubscriptionStatus.trial));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(received.length, greaterThanOrEqualTo(2));
      expect(received.last!.status, SubscriptionStatus.trial);
    });
  });
}
