/// Value types of the summary sync layer and its state stream (S02 design 3.2,
/// 6.2; story S02-12). Summary fields only: nothing here carries coordinates,
/// heart rate or place text.
library;

import '../data/sport_type.dart';
import '../data/summary_projection.dart' show CandidateChoice;

/// What one sync or resolution call ended with.
enum SyncOutcome {
  /// The summary is stored on the server (or already equal to it) and the
  /// entry is marked `synced`.
  synced,

  /// Stored locally; the push is deferred (offline, or the entry moved on
  /// while the call ran). Not `synced`.
  pending,

  /// The entry is (still) `sync_conflict`: local data kept, nothing synced.
  conflict,

  /// The server tombstone exists: the local entry was deleted (delete wins).
  deletedLocal,

  /// The backend could not be reached; local data and the choice are intact.
  unavailable,

  /// Unknown or deleted id.
  notFound,

  /// Nothing to resolve (a repeated call after the resolution was stored).
  alreadyResolved,

  /// A newer-schema record this build must not write.
  readOnly,
}

/// The two choices offered for a field-level `sync_conflict`.
enum ConflictChoice {
  /// Write the local values with the next rev.
  keepDevice,

  /// Replace the local derived values with the server values (overrides).
  keepCloud,
}

/// One summary field changed to different values on two devices.
class FieldConflict {
  const FieldConflict({
    required this.field,
    required this.deviceValue,
    required this.cloudValue,
  });

  final String field;

  /// The value this device would write; null when the device holds none.
  final Object? deviceValue;

  /// The server value; null when unknown (the server could not be read).
  final Object? cloudValue;

  @override
  bool operator ==(Object other) =>
      other is FieldConflict &&
      other.field == field &&
      other.deviceValue == deviceValue &&
      other.cloudValue == cloudValue;

  @override
  int get hashCode => Object.hash(field, deviceValue, cloudValue);
}

/// An activity in `sync_conflict`.
class SyncConflict {
  const SyncConflict({
    required this.id,
    required this.sport,
    required this.startUtc,
    required this.fields,
    required this.cloudKnown,
  });

  final String id;
  final SportType sport;
  final DateTime startUtc;

  /// The conflicting fields with both values. Empty when the conflict comes
  /// from a rejected write that no field explains.
  final List<FieldConflict> fields;

  /// False while the server summary could not be read: "keep cloud" is then
  /// not offered.
  final bool cloudKnown;

  @override
  bool operator ==(Object other) =>
      other is SyncConflict &&
      other.id == id &&
      other.sport == sport &&
      other.startUtc == startUtc &&
      other.cloudKnown == cloudKnown &&
      _listEq(other.fields, fields);

  @override
  int get hashCode => Object.hash(id, sport, startUtc, cloudKnown, fields.length);
}

/// Why a candidate exists (design 3.2: `source` for an explicit value whose raw
/// derivation changed, `recalculation` for the override path).
enum CandidateReason { source, recalculation }

/// A field carrying a `sourceCandidate` or `recalcCandidate`. It is listed
/// although the activity itself may be `synced`.
class SyncCandidate {
  const SyncCandidate({
    required this.id,
    required this.sport,
    required this.startUtc,
    required this.field,
    required this.reason,
    required this.choices,
    required this.computedValue,
    this.explicitValue,
    this.cloudValue,
  });

  final String id;
  final SportType sport;
  final DateTime startUtc;
  final String field;
  final CandidateReason reason;

  /// The actions offered (design 3.2: three with an override and an explicit
  /// value, two otherwise).
  final Set<CandidateChoice> choices;

  /// The newly computed value (the candidate).
  final double computedValue;

  /// The user's explicit value, when one exists.
  final double? explicitValue;

  /// The adopted cloud value, when an override exists.
  final double? cloudValue;

  String get key => '$id/$field';

  @override
  bool operator ==(Object other) =>
      other is SyncCandidate &&
      other.id == id &&
      other.field == field &&
      other.reason == reason &&
      other.computedValue == computedValue &&
      other.explicitValue == explicitValue &&
      other.cloudValue == cloudValue &&
      other.choices.length == choices.length &&
      other.choices.containsAll(choices);

  @override
  int get hashCode =>
      Object.hash(id, field, reason, computedValue, explicitValue, cloudValue);
}

/// What the repository state stream carries: everything that needs the user.
class ActivitySyncState {
  const ActivitySyncState({
    this.conflicts = const [],
    this.candidates = const [],
    this.pendingTombstones = 0,
    this.lastTombstonePushError,
  });

  static const ActivitySyncState empty = ActivitySyncState();

  final List<SyncConflict> conflicts;
  final List<SyncCandidate> candidates;

  /// Local deletions the server has not confirmed yet (S02 design 6.2). Zero
  /// means every local delete has reached the cloud. Not part of [isEmpty]: it
  /// is a progress counter, not something the user must resolve.
  final int pendingTombstones;

  /// Error code of the last failed tombstone push in this process, or null.
  final String? lastTombstonePushError;

  bool get isEmpty => conflicts.isEmpty && candidates.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is ActivitySyncState &&
      other.pendingTombstones == pendingTombstones &&
      other.lastTombstonePushError == lastTombstonePushError &&
      _listEq(other.conflicts, conflicts) &&
      _listEq(other.candidates, candidates);

  @override
  int get hashCode => Object.hash(
      conflicts.length, candidates.length, pendingTombstones, lastTombstonePushError);
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
