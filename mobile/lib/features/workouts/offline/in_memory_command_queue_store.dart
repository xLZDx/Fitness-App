/// In-memory [CommandQueueStore] for tests. It shares every rule of the file
/// store (unique indexes, cap, transitions, pruning) through
/// `BaseCommandQueueStore`; only durability is absent.
library;

import 'command_queue_store.dart';
import 'command_queue_store_base.dart';
import 'command_record.dart';

class InMemoryCommandQueueStore extends BaseCommandQueueStore {
  InMemoryCommandQueueStore({required super.uid, super.nowMs});

  @override
  Future<void> persistRecord(CommandRecord record) async {}

  @override
  Future<void> persistSeqCounters(Map<String, int> counters) async {}

  @override
  Future<void> removeRecordFromDisk(String operationId) async {}

  @override
  Future<void> persistLogicalSetMarkers(
      Map<String, LogicalSetMarker> markers) async {}
}
