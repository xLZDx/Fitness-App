/// Gate LIVE — "remember every recognised gym machine".
///
/// Persistence for the machines a user's camera (or QR scan) has identified.
/// The store is keyed by `equipmentId`: one row per machine, carrying the
/// most recent sighting. It is deliberately NOT an event log — a live camera
/// pointed at one machine produces recognitions at frame rate, and an
/// append-only log would grow without bound for zero extra information.
///
/// The merge rule that keeps it that way lives in [RecognitionDedup] and is
/// shared by every implementation (see [MockRecognitionHistoryRepository] and
/// `FirestoreRecognitionHistoryRepository`), so the in-memory and Firestore
/// stores cannot drift apart.
library;

import 'dart:async';

/// How a machine came to be recognised. Persisted by `.name`.
enum RecognitionSource {
  /// Continuous on-device classification from the live camera preview.
  live,

  /// A single still photo the user captured or picked.
  photo,

  /// A QR code on the machine — the only exact-by-construction source.
  qr,
}

/// One remembered machine: which one, when it was last seen, and how sure
/// the recogniser was.
///
/// [recognisedAt] is normalised to UTC by the constructor. Every instance is
/// therefore directly comparable, sorts correctly, survives a JSON round-trip
/// unchanged, and orders the same way in Firestore as it does in memory —
/// none of which holds if local and UTC timestamps are allowed to mix.
class RecognitionEntry {
  RecognitionEntry({
    required this.equipmentId,
    required DateTime recognisedAt,
    required this.confidence,
    this.source,
  }) : recognisedAt = recognisedAt.toUtc();

  /// Catalog id of the machine, e.g. `lat_pulldown`. Doubles as the storage
  /// key — see the class doc on why the store is keyed rather than appended.
  final String equipmentId;

  /// Instant of the most recent sighting, always UTC.
  final DateTime recognisedAt;

  /// Recogniser confidence in 0..1 for that sighting.
  final double confidence;

  /// Which pipeline produced the sighting. Null for entries written before
  /// the field existed, so readers must tolerate its absence.
  final RecognitionSource? source;

  RecognitionEntry copyWith({
    String? equipmentId,
    DateTime? recognisedAt,
    double? confidence,
    RecognitionSource? source,
  }) =>
      RecognitionEntry(
        equipmentId: equipmentId ?? this.equipmentId,
        recognisedAt: recognisedAt ?? this.recognisedAt,
        confidence: confidence ?? this.confidence,
        source: source ?? this.source,
      );

  Map<String, dynamic> toJson() => {
        'equipmentId': equipmentId,
        'recognisedAt': recognisedAt.toIso8601String(),
        'confidence': confidence,
        if (source != null) 'source': source!.name,
      };

  factory RecognitionEntry.fromJson(Map<String, dynamic> j) {
    final raw = j['recognisedAt'];
    DateTime recognisedAt;
    if (raw is String) {
      recognisedAt = DateTime.parse(raw);
    } else if (raw is DateTime) {
      recognisedAt = raw;
    } else {
      // Firestore Timestamp; not imported here so the data layer stays free
      // of Firebase deps. Repos convert before calling.
      throw ArgumentError(
          'recognisedAt must be ISO-8601 string or DateTime, got ${raw.runtimeType}');
    }
    return RecognitionEntry(
      equipmentId: j['equipmentId'] as String,
      recognisedAt: recognisedAt,
      confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
      source: recognitionSourceByName(j['source']),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecognitionEntry &&
          other.equipmentId == equipmentId &&
          other.recognisedAt == recognisedAt &&
          other.confidence == confidence &&
          other.source == source;

  @override
  int get hashCode =>
      Object.hash(equipmentId, recognisedAt, confidence, source);

  @override
  String toString() => 'RecognitionEntry($equipmentId, '
      '${recognisedAt.toIso8601String()}, $confidence, ${source?.name})';
}

/// Resolves a persisted `source` string. Returns null for null, an unknown
/// value, or a non-string — an entry written by a newer build must not crash
/// an older one.
RecognitionSource? recognitionSourceByName(dynamic name) {
  if (name is! String) return null;
  for (final s in RecognitionSource.values) {
    if (s.name == name) return s;
  }
  return null;
}

/// The single home of the de-duplication rule.
///
/// Both the in-memory and the Firestore repository route every write through
/// here, so "what happens when the same machine is recognised twice" has one
/// answer rather than one per backend.
///
/// The store holds at most one entry per `equipmentId`; [window] decides how
/// the incoming sighting is folded into the one already there:
///
///  * **Within the window** — the same continuous sighting (a live camera
///    holding on one machine). Per-frame confidence jitters, so the entry
///    keeps the *best* look it got. Recording 50 frames of `lat_pulldown`
///    leaves exactly one row, not 50.
///  * **Outside the window** — a genuinely new visit. The fresh confidence
///    replaces the old one, which would otherwise be pinned forever at the
///    high-water mark of some sighting weeks ago.
///
/// The timestamp always advances to the later of the two, so out-of-order
/// writes cannot move a machine backwards in the list.
class RecognitionDedup {
  const RecognitionDedup._();

  /// Two sightings of one machine closer together than this are treated as
  /// the same sighting.
  static const Duration window = Duration(minutes: 5);

  /// Whether [incoming] belongs to the same sighting as [previous].
  ///
  /// Compares the absolute gap, so a write that arrives with an older
  /// timestamp (clock skew, a queued offline write) is still recognised as
  /// part of the same burst instead of silently resetting the confidence.
  static bool isSameSighting(
    RecognitionEntry previous,
    RecognitionEntry incoming,
  ) =>
      previous.equipmentId == incoming.equipmentId &&
      previous.recognisedAt.difference(incoming.recognisedAt).abs() <= window;

  /// Folds [incoming] into [previous], returning the entry that should
  /// replace it. Both must be for the same machine.
  static RecognitionEntry merge(
    RecognitionEntry previous,
    RecognitionEntry incoming,
  ) {
    assert(previous.equipmentId == incoming.equipmentId,
        'merge() is only defined for two sightings of the same machine');
    final sameSighting = isSameSighting(previous, incoming);
    return RecognitionEntry(
      equipmentId: incoming.equipmentId,
      recognisedAt: incoming.recognisedAt.isAfter(previous.recognisedAt)
          ? incoming.recognisedAt
          : previous.recognisedAt,
      confidence: sameSighting
          ? (incoming.confidence > previous.confidence
              ? incoming.confidence
              : previous.confidence)
          : incoming.confidence,
      source: incoming.source ?? previous.source,
    );
  }

  /// Applies [incoming] to a whole history, returning the new list ordered
  /// newest first. Used by list-shaped stores; the Firestore repository
  /// reaches for [merge] directly because it addresses one document.
  static List<RecognitionEntry> apply(
    Iterable<RecognitionEntry> existing,
    RecognitionEntry incoming,
  ) {
    final next = <RecognitionEntry>[];
    var merged = false;
    for (final e in existing) {
      if (e.equipmentId == incoming.equipmentId) {
        next.add(merge(e, incoming));
        merged = true;
      } else {
        next.add(e);
      }
    }
    if (!merged) next.add(incoming);
    return sortNewestFirst(next);
  }

  /// Newest first, ties broken by `equipmentId` so the order is total and
  /// two stores holding the same data emit the same list.
  static List<RecognitionEntry> sortNewestFirst(
    Iterable<RecognitionEntry> entries,
  ) {
    final sorted = [...entries]..sort((a, b) {
        final byTime = b.recognisedAt.compareTo(a.recognisedAt);
        return byTime != 0 ? byTime : a.equipmentId.compareTo(b.equipmentId);
      });
    return List.unmodifiable(sorted);
  }
}

/// Persistence interface for recognised-machine history. The default
/// implementation is in-memory ([MockRecognitionHistoryRepository]);
/// production uses `FirestoreRecognitionHistoryRepository`, writing under
/// `users/{uid}/recognised_equipment/{equipmentId}`.
abstract class RecognitionHistoryRepository {
  /// Remembers a sighting, folding it into any existing entry for the same
  /// machine per [RecognitionDedup]. Safe to call at camera frame rate.
  Future<void> record(RecognitionEntry entry);

  /// Streams the full history, newest first. Emits an empty list when
  /// nothing has been recognised, or when there is no signed-in user.
  Stream<List<RecognitionEntry>> watch();

  /// One-shot read of the history, newest first.
  Future<List<RecognitionEntry>> list();

  /// Wipes the history. Used by the "reset progress" / GDPR flows.
  Future<void> clear();
}

/// In-memory [RecognitionHistoryRepository] — the default binding and the
/// one tests run against.
class MockRecognitionHistoryRepository implements RecognitionHistoryRepository {
  /// [latency] mirrors the other mocks in this codebase, but defaults to
  /// zero here: `record()` sits on the live-recognition hot path, and an
  /// artificial delay there would misrepresent how the real store behaves.
  MockRecognitionHistoryRepository({Duration latency = Duration.zero})
      : _latency = latency;

  final Duration _latency;
  final List<RecognitionEntry> _store = [];
  final StreamController<List<RecognitionEntry>> _ctrl =
      StreamController<List<RecognitionEntry>>.broadcast();

  List<RecognitionEntry> get _snapshot =>
      RecognitionDedup.sortNewestFirst(_store);

  @override
  Stream<List<RecognitionEntry>> watch() {
    late StreamController<List<RecognitionEntry>> replay;
    StreamSubscription<List<RecognitionEntry>>? sub;
    replay = StreamController<List<RecognitionEntry>>(
      onListen: () {
        replay.add(_snapshot);
        sub = _ctrl.stream.listen(replay.add,
            onError: replay.addError, onDone: replay.close);
      },
      onCancel: () async {
        await sub?.cancel();
      },
    );
    return replay.stream;
  }

  @override
  Future<void> record(RecognitionEntry entry) async {
    if (_latency > Duration.zero) await Future<void>.delayed(_latency);
    final next = RecognitionDedup.apply(_store, entry);
    _store
      ..clear()
      ..addAll(next);
    _ctrl.add(_snapshot);
  }

  @override
  Future<List<RecognitionEntry>> list() async {
    if (_latency > Duration.zero) await Future<void>.delayed(_latency);
    return _snapshot;
  }

  @override
  Future<void> clear() async {
    if (_latency > Duration.zero) await Future<void>.delayed(_latency);
    _store.clear();
    _ctrl.add(const []);
  }

  void dispose() {
    _ctrl.close();
  }
}
