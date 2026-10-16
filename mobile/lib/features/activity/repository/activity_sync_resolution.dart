/// The user-facing operations of the sync layer (S02 design 3.2 "Rev conflict
/// handling", "Summary overrides", the ATOMIC candidate resolution paragraph).
/// Each operation commits its local change in ONE journal generation BEFORE any
/// network write, so a kill or a lost acknowledgement leaves a durable choice
/// and a repeated call is a no-op.
part of 'activity_sync_repository.dart';

extension ActivitySyncResolution on ActivitySyncRepository {
  /// Resolves a `sync_conflict` with "keep this device" or "keep cloud".
  ///
  /// - keep device: an older override of each conflicting field is removed (the
  ///   local value is the recomputation) and the local values are written with
  ///   `rev = max(local, server) + 1`;
  /// - keep cloud: each conflicting field gets an override with the server
  ///   value (`atComputed` = the value the device holds); streams, laps,
  ///   provenance and explicit values are never touched; nothing is written
  ///   when the values already equal the server.
  ///
  /// The choice is first stored (overrides and an adjusted `baseSummary` in one
  /// generation, state still `sync_conflict`); `synced` follows only after the
  /// summary is stored on the server. A repeated call returns
  /// [SyncOutcome.alreadyResolved].
  Future<SyncOutcome> resolveConflict(String id, ConflictChoice choice) =>
      _ops.run(() async {
        final JournalEntry? read;
        try {
          read = await _journal.read(id);
        } on JournalIoException {
          return SyncOutcome.pending; // local read I/O error: retry later
        }
        if (read == null) return SyncOutcome.notFound;
        if (read.session.isReadOnly) return SyncOutcome.readOnly;
        if (read.state.syncState != JournalSyncState.syncConflict) {
          return SyncOutcome.alreadyResolved;
        }
        final entry = await _reconciled(read);
        if (entry == null) return SyncOutcome.pending;

        Map<String, Object?>? server;
        try {
          server = await _backend.readSummary(id);
        } on SummaryBackendUnavailable {
          return SyncOutcome.unavailable; // still sync_conflict, data intact
        } on SummaryCorrupt {
          return SyncOutcome.conflict; // unreadable cloud copy: stays visible
        }
        if (server == null) {
          // No server document: keep device creates it; keep cloud has
          // nothing to keep.
          if (choice == ConflictChoice.keepCloud) return SyncOutcome.conflict;
          return _syncLocked(id, known: const _Server(null));
        }

        final base = decodeSummary(entry.state.baseSummary);
        final local0 = _buildLocal(entry.session, entry.state,
            hasRouteKnown: entry.streamsLoaded);
        final a = _analyze(entry.session, base, local0, server);
        final fields = a.isMerged ? const <String>[] : a.conflicts;
        if (fields.any(kSummaryImmutableKeys.contains)) {
          return SyncOutcome.conflict; // an error, never a merge
        }

        var s = entry.session;
        final serverRev = summaryRev(server);
        final resolvedBase = <String, Object?>{...?base};
        for (final f in fields) {
          if (choice == ConflictChoice.keepDevice) {
            s = s.copyWith(
              summaryOverrides: {...s.summaryOverrides}..remove(f),
            );
            resolvedBase[f] = server[f];
          } else {
            final v = server[f];
            final bound = kSummaryNumericBounds[f];
            if (v is! num || bound == null || !bound.accepts(v)) {
              return SyncOutcome.conflict;
            }
            final adopted = SummaryProjection.adoptServerValue(
                s, f, v.toDouble(), serverRev,
                inForce: _versions());
            s = adopted ??
                s.copyWith(summaryOverrides: {
                  ...s.summaryOverrides,
                  f: SummaryOverride(
                    value: v.toDouble(),
                    atComputed: v.toDouble(),
                    atVersions: _versions(),
                    atRev: serverRev,
                  ),
                });
            resolvedBase[f] = local0[f];
          }
        }

        if (fields.isNotEmpty) {
          final updated = await _journal.updateRecord(
            id,
            s,
            expectedGeneration: entry.generation,
            baseRev: serverRev,
            baseSummary: encodeSummary(resolvedBase),
          );
          if (updated == null) return SyncOutcome.pending;
        }
        _conflictCache.remove(id);
        return _syncLocked(id, known: _Server(server));
      });

  /// Resolves the candidate of [field] as ONE atomic operation: the explicit
  /// value, the override and the candidate change together in one generation
  /// (design 3.2, GPT-PM round 9 MAJOR-01L). The chosen value is then compared
  /// against the CURRENT `baseSummary` and server summary: written when the
  /// server still holds the base, kept in `sync_conflict` when it changed
  /// again. Returns [SyncOutcome.alreadyResolved] when no candidate exists
  /// (idempotent after a restart or a replayed call). Throws [ArgumentError]
  /// for a choice that is not offered.
  Future<SyncOutcome> resolveCandidate(
    String id,
    String field,
    CandidateChoice choice,
  ) =>
      _ops.run(() async {
        final JournalEntry? entry;
        try {
          entry = await _journal.read(id);
        } on JournalIoException {
          return SyncOutcome.pending; // local read I/O error: retry later
        }
        if (entry == null) return SyncOutcome.notFound;
        if (entry.session.isReadOnly) return SyncOutcome.readOnly;
        final session =
            SummaryProjection.reconcile(entry.session, inForce: _versions());
        if (SummaryProjection.offeredChoices(session, field).isEmpty) {
          return SyncOutcome.alreadyResolved;
        }
        final base = decodeSummary(entry.state.baseSummary) ?? const {};
        Map<String, Object?>? server;
        var serverKnown = true;
        try {
          server = await _backend.readSummary(id);
        } on SummaryBackendUnavailable {
          serverKnown = false;
        } on SummaryCorrupt {
          serverKnown = false;
        }
        final res = SummaryProjection.resolveCandidate(
          session,
          field,
          choice,
          baseSummary: base,
          serverSummary: server ?? base,
        );
        final next = res.record;
        var newState = entry.state.syncState;
        var changed = false;
        if (res.merge == ResolutionMerge.conflict) {
          newState = JournalSyncState.syncConflict;
        } else {
          final local = _buildLocal(next, entry.state,
              hasRouteKnown: entry.streamsLoaded);
          changed = decodeSummary(entry.state.baseSummary) == null ||
              !summariesEqual(local, base);
          if (changed &&
              newState != JournalSyncState.syncConflict) {
            newState = JournalSyncState.pending;
          }
        }
        final updated = await _journal.updateRecord(
          id,
          next,
          syncState: newState,
          expectedGeneration: entry.generation,
        );
        if (updated == null) return SyncOutcome.pending;
        _conflictCache.remove(id);
        _publish();
        if (res.merge == ResolutionMerge.conflict) return SyncOutcome.conflict;
        if (!changed) return SyncOutcome.synced;
        return _syncLocked(id,
            known: serverKnown && server != null ? _Server(server) : null);
      });

  /// The field-naming explicit user edit (design 3.2 rule 2 (ii)): drops the
  /// override of each named field in the same generation, counts once, then
  /// syncs. Throws [ArgumentError] for an empty or invalid edit; nothing
  /// changes in that case.
  Future<SyncOutcome> applyExplicitEdit(
          String id, Map<String, double> edits) =>
      _ops.run(() async {
        final JournalEntry? entry;
        try {
          entry = await _journal.read(id);
        } on JournalIoException {
          return SyncOutcome.pending; // local read I/O error: retry later
        }
        if (entry == null) return SyncOutcome.notFound;
        if (entry.session.isReadOnly) return SyncOutcome.readOnly;
        final session =
            SummaryProjection.reconcile(entry.session, inForce: _versions());
        final next = SummaryProjection.applyExplicitEdit(session, edits);
        final conflict =
            entry.state.syncState == JournalSyncState.syncConflict;
        final updated = await _journal.updateRecord(
          id,
          next,
          syncState: conflict ? null : JournalSyncState.pending,
          expectedGeneration: entry.generation,
        );
        if (updated == null) return SyncOutcome.pending;
        _conflictCache.remove(id);
        _publish();
        return _syncLocked(id);
      });
}
