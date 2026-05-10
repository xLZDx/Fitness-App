import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/donor_wall_entry.dart';
import '../data/donor_wall_repository.dart';

final donorWallRepositoryProvider = Provider<DonorWallRepository>((ref) {
  // Default to mock; real binding happens in main.dart for prod builds.
  return MockDonorWallRepository();
});

/// Live stream of opted-in donors. Sorted by lifetime first, then by
/// most-recent join.
final donorWallProvider =
    StreamProvider<List<DonorWallEntry>>((ref) {
  return ref.watch(donorWallRepositoryProvider).watch();
});
