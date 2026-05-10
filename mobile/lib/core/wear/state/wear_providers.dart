import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../wear_sync_service.dart';

final wearSyncServiceProvider = Provider<WearSyncService>((ref) {
  return MockWearSyncService();
});

final watchPairedProvider = FutureProvider<bool>((ref) {
  return ref.watch(wearSyncServiceProvider).isWatchPaired();
});

final wearIncomingProvider = StreamProvider<WearMessage>((ref) {
  return ref.watch(wearSyncServiceProvider).incoming();
});
