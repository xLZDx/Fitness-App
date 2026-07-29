import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/recognition_history.dart';

/// Persistence provider — defaults to the in-memory mock; overridden in
/// `main.dart` to use the Firestore-backed implementation.
final recognitionHistoryRepositoryProvider =
    Provider<RecognitionHistoryRepository>((ref) {
  final repo = MockRecognitionHistoryRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

/// Every machine this user has had recognised, newest first. Emits the empty
/// list when nothing has been scanned yet and when there is no signed-in
/// user, so it is safe to render at any router state.
///
/// Deliberately not gated on `authUserProvider` here: the repository owns the
/// signed-out answer (the Firestore implementation follows auth itself and
/// starts streaming on sign-in), so gating again would only give the mock a
/// second, contradictory notion of who is signed in.
final recognitionHistoryProvider =
    StreamProvider<List<RecognitionEntry>>((ref) {
  return ref.watch(recognitionHistoryRepositoryProvider).watch();
});
