/// Storage of weigh-ins `users/{uid}/weight_entries/{yyyy-MM-dd}` (design s5.3,
/// D-72). No Flutter imports.
///
/// Day-keyed: a second weigh-in on the same local day overwrites the first (an
/// idempotent edit, the last writer's `source` wins). The maths reads `at`, not
/// the key, so the key is only an id; the log keeps the id with each entry so a
/// delete or edit always hits the document that was actually shown, even when
/// the user changed time zone since it was written.
library;

import 'weight_entry.dart';

/// One stored weigh-in with its document id.
class WeightLogItem {
  const WeightLogItem({required this.id, required this.entry});

  /// The document id (`yyyy-MM-dd`).
  final String id;
  final WeightEntry entry;
}

abstract class WeightEntriesRepository {
  /// Entries of the last [days] days, oldest first (the plan reads 60 days).
  /// Unreadable documents are skipped. Replays the latest value.
  Stream<List<WeightLogItem>> watchLog(String uid, {int days = 60});

  Future<List<WeightLogItem>> loadLog(String uid, {int days = 60});

  /// The entry stored under [dayKey], or null.
  Future<WeightLogItem?> entryForDay(String uid, String dayKey);

  /// Writes [entry] under its own local day key; an existing entry of that day
  /// is overwritten. Throws [ArgumentError] for a weight outside 30..300 kg.
  Future<void> put(String uid, WeightEntry entry);

  /// Edit: writes [entry] under its day key and removes [oldId] when the day
  /// changed, in ONE batch (never leaves both or neither).
  Future<void> replace(String uid, {required String oldId, required WeightEntry entry});

  /// Removes the entry stored under [id].
  Future<void> delete(String uid, String id);
}
