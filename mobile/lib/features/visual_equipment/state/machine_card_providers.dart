import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/machine_card.dart';
import '../data/machine_card_repository.dart';
import '../data/machine_describer.dart';

/// Asks the model what an unrecognised machine is. Defaults to the mock that
/// says nothing; overridden in `main.dart` with the Gemini implementation.
final machineDescriberProvider = Provider<MachineDescriber>((_) {
  return MockMachineDescriber();
});

/// Where the resulting cards live. In-memory by default, Firestore in
/// `main.dart`.
final machineCardRepositoryProvider = Provider<MachineCardRepository>((ref) {
  final repo = MockMachineCardRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

/// The user's machines that have no page yet, newest sighting first.
///
/// Not gated on the signed-in user here: the repository owns the signed-out
/// answer (the Firestore one follows auth itself), and gating again would give
/// the mock a second, contradictory notion of who is signed in.
final machineCardsProvider = StreamProvider<List<MachineCard>>((ref) {
  return ref.watch(machineCardRepositoryProvider).watch();
});

/// The last card the scanner produced, or null when the last scan matched the
/// catalog (or produced nothing worth showing).
///
/// Held separately from the list because the scan screen shows THIS machine
/// straight after the photo, while the list is everything ever scanned.
class LastMachineCardController extends Notifier<MachineCard?> {
  @override
  MachineCard? build() => null;

  void set(MachineCard? card) => state = card;

  void clear() => state = null;
}

final lastMachineCardProvider =
    NotifierProvider<LastMachineCardController, MachineCard?>(
  LastMachineCardController.new,
);
