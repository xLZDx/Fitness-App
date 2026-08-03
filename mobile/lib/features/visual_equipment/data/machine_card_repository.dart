import 'dart:async';

import 'machine_card.dart';

/// Where photographed-but-missing machines are kept.
///
/// Two audiences, one row. The user opens "мои тренажёры" and sees the machine
/// they scanned with an honest «контент готовится» — operator: *"пользователю
/// тоже видна как «контент готовится»"*. We read the same rows to learn what
/// people actually stand in front of — operator: *"надо добавить механизм
/// отслеживания что фоткают люди и что им определяет АИ"* — because
/// [MachineCard.timesSeen] across users is the only honest answer to "which
/// missing clip do we film first".
///
/// Keyed by [MachineCard.id], never appended: scanning the same machine on
/// Monday and Thursday is one card with a count of two, not two cards.
abstract class MachineCardRepository {
  /// Saves a sighting, folding it into any card already held for the same
  /// machine per [MachineCardMerge].
  Future<void> save(MachineCard card);

  /// Streams the user's machines, newest sighting first. Emits the empty list
  /// when there are none and when nobody is signed in.
  Stream<List<MachineCard>> watch();

  Future<List<MachineCard>> list();

  /// Removes one card — the user's own "I don't need this" on their list.
  Future<void> remove(String id);

  Future<void> clear();
}

/// The single home of "what happens when the same machine is scanned twice".
///
/// Both the in-memory and the Firestore store route every write through here,
/// exactly as [RecognitionDedup] does for recognised catalog machines, so the
/// two backends cannot answer the question differently.
class MachineCardMerge {
  const MachineCardMerge._();

  /// Two photos of one machine closer together than this are one sighting.
  ///
  /// A photo scan is a deliberate act, unlike the live camera's frame-rate
  /// stream, so this is not about flooding. It is about the count meaning
  /// something: tapping the shutter twice because the first shot was blurry is
  /// one encounter with one machine, and if it read as two it would out-vote a
  /// machine that two different people actually went looking for.
  static const Duration window = Duration(minutes: 5);

  static MachineCard fold(MachineCard previous, MachineCard incoming) {
    assert(previous.id == incoming.id,
        'fold() is only defined for two sightings of the same machine');
    final at = incoming.lastSeenAt ?? incoming.firstSeenAt;
    final last = previous.lastSeenAt ?? previous.firstSeenAt;
    final sameSighting = at.difference(last).abs() <= window;

    return MachineCard(
      id: previous.id,
      // The first name recorded wins. Renaming the card under the user because
      // the model phrased it differently on a second photo is churn, and it
      // would split our own reading of what is being asked for.
      name: previous.name,
      // A better description does win: the first answer can be thin, and there
      // is no cost to keeping the fuller one.
      summary: previous.summary.isEmpty ? incoming.summary : previous.summary,
      uses: previous.uses.isEmpty ? incoming.uses : previous.uses,
      firstSeenAt: previous.firstSeenAt.isBefore(incoming.firstSeenAt)
          ? previous.firstSeenAt
          : incoming.firstSeenAt,
      lastSeenAt: at.isAfter(last) ? at : last,
      timesSeen:
          sameSighting ? previous.timesSeen : previous.timesSeen + incoming.timesSeen,
      photoPath: incoming.photoPath ?? previous.photoPath,
      // A decision already taken about this machine survives a new photo.
      // Someone marked it `inCatalog` after adding the clip, or `declined`
      // after looking at it; a fresh sighting is not a reason to re-open either
      // — it would put a machine we already shipped back under «готовится».
      status: previous.status == MachineCardStatus.preparing
          ? incoming.status
          : previous.status,
      recognisedAs: incoming.recognisedAs ?? previous.recognisedAs,
      confidence: incoming.confidence ?? previous.confidence,
    );
  }

  /// Applies [incoming] to a whole list, newest sighting first.
  static List<MachineCard> apply(
    Iterable<MachineCard> existing,
    MachineCard incoming,
  ) {
    final next = <MachineCard>[];
    var merged = false;
    for (final c in existing) {
      if (c.id == incoming.id) {
        next.add(fold(c, incoming));
        merged = true;
      } else {
        next.add(c);
      }
    }
    if (!merged) next.add(incoming);
    return sortNewestFirst(next);
  }

  /// Newest first, ties broken by id so the order is total and two stores
  /// holding the same data emit the same list.
  static List<MachineCard> sortNewestFirst(Iterable<MachineCard> cards) {
    final sorted = [...cards]..sort((a, b) {
        final at = a.lastSeenAt ?? a.firstSeenAt;
        final bt = b.lastSeenAt ?? b.firstSeenAt;
        final byTime = bt.compareTo(at);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    return List.unmodifiable(sorted);
  }
}

/// In-memory [MachineCardRepository] — the default binding and what tests run
/// against.
class MockMachineCardRepository implements MachineCardRepository {
  final List<MachineCard> _store = [];
  final StreamController<List<MachineCard>> _ctrl =
      StreamController<List<MachineCard>>.broadcast();

  List<MachineCard> get _snapshot => MachineCardMerge.sortNewestFirst(_store);

  @override
  Stream<List<MachineCard>> watch() {
    late StreamController<List<MachineCard>> replay;
    StreamSubscription<List<MachineCard>>? sub;
    replay = StreamController<List<MachineCard>>(
      onListen: () {
        replay.add(_snapshot);
        sub = _ctrl.stream
            .listen(replay.add, onError: replay.addError, onDone: replay.close);
      },
      onCancel: () async {
        await sub?.cancel();
      },
    );
    return replay.stream;
  }

  @override
  Future<void> save(MachineCard card) async {
    final next = MachineCardMerge.apply(_store, card);
    _store
      ..clear()
      ..addAll(next);
    _ctrl.add(_snapshot);
  }

  @override
  Future<List<MachineCard>> list() async => _snapshot;

  @override
  Future<void> remove(String id) async {
    _store.removeWhere((c) => c.id == id);
    _ctrl.add(_snapshot);
  }

  @override
  Future<void> clear() async {
    _store.clear();
    _ctrl.add(const []);
  }

  void dispose() => _ctrl.close();
}
