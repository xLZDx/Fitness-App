import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../health_models.dart';
import '../health_service.dart';

final healthServiceProvider = Provider<HealthService>((ref) {
  // Default = mock so widget tests don't need to stub the platform.
  // main.dart overrides with PlatformHealthService for production.
  return MockHealthService();
});

final healthAuthStatusProvider = FutureProvider<HealthAuthStatus>((ref) {
  return ref.watch(healthServiceProvider).currentAuthStatus();
});

/// Failure reason from the most recent authorization attempt, or null
/// when it succeeded / was a clean user-denied. The sync card shows it
/// so a platform failure isn't a silent "does not work".
final healthAuthErrorProvider = StateProvider<String?>((ref) => null);

final todayHealthProvider = FutureProvider<HealthSnapshot?>((ref) {
  return ref.watch(healthServiceProvider).readTodaySnapshot();
});

final last7DaysHealthProvider =
    FutureProvider<List<HealthSnapshot>>((ref) {
  final now = DateTime.now();
  final start = now.subtract(const Duration(days: 7));
  return ref
      .watch(healthServiceProvider)
      .readSnapshots(from: start, to: now);
});

class HealthAuthAction extends Notifier<AsyncValue<HealthAuthStatus>> {
  @override
  AsyncValue<HealthAuthStatus> build() =>
      const AsyncValue.data(HealthAuthStatus.notDetermined);

  Future<void> request() async {
    state = const AsyncValue.loading();
    try {
      final service = ref.read(healthServiceProvider);
      final s = await service.requestAuthorization();
      state = AsyncValue.data(s);
      // Surface the platform failure (if any) behind a non-granted result.
      ref.read(healthAuthErrorProvider.notifier).state =
          s == HealthAuthStatus.granted ? null : service.lastErrorMessage;
      // Invalidate the auth-status read so dependent FutureProviders rebuild.
      ref.invalidate(healthAuthStatusProvider);
      ref.invalidate(todayHealthProvider);
      ref.invalidate(last7DaysHealthProvider);
    } catch (e, st) {
      ref.read(healthAuthErrorProvider.notifier).state = e.toString();
      state = AsyncValue.error(e, st);
    }
  }
}

final healthAuthActionProvider =
    NotifierProvider<HealthAuthAction, AsyncValue<HealthAuthStatus>>(
        HealthAuthAction.new);
