import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_semantic_colors.dart';
import '../scanner_page.dart' show equipmentDisplayName;
import '../widgets/machine_thumb.dart';
import '../widgets/rating_marks.dart';
import 'scan_history_providers.dart';
import 'scan_record.dart';

/// "История сканов": every scan saved on this phone, newest first, with the
/// export and clear actions (operator order 2026-10-14, C).
///
/// Local only: the list is read from app-private storage, and the one way out
/// is the user's own Export, which writes one JSON plus a photos folder and
/// opens the system share sheet.
class ScanHistoryPage extends ConsumerWidget {
  const ScanHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final async = ref.watch(scanHistoryProvider);
    final List<ScanRecord> records = async.valueOrNull ?? const <ScanRecord>[];

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(l10n.scanHistoryTitle),
        actions: <Widget>[
          IconButton(
            key: const Key('scan-history-export'),
            tooltip: l10n.scanHistoryExport,
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: records.isEmpty ? null : () => _export(context, ref),
          ),
          IconButton(
            key: const Key('scan-history-clear'),
            tooltip: l10n.scanHistoryClear,
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: records.isEmpty ? null : () => _confirmClear(context, ref),
          ),
        ],
      ),
      body: async.isLoading && records.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : records.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      l10n.scanHistoryEmpty,
                      key: const Key('scan-history-empty'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                )
              : ListView.builder(
                  key: const Key('scan-history-list'),
                  itemCount: records.length + 1,
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Text(
                          l10n.scanHistoryLocalOnly,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colors.textSecondary),
                        ),
                      );
                    }
                    return _HistoryRow(record: records[i - 1]);
                  },
                ),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    Directory? written;
    try {
      final uid = ref.read(scanHistoryUidProvider);
      if (uid == null) return;
      final dir = await ref.read(scanExportDirProvider)();
      final export =
          await ref.read(scanHistoryStoreProvider).export(uid, dir);
      written = export.directory;
      await ref.read(scanShareProvider)(export.files);
    } catch (e) {
      debugPrint('scan history export failed: ${e.runtimeType}');
      messenger.showSnackBar(SnackBar(content: Text(l10n.scanHistoryExportFailed)));
    } finally {
      // The export copy is plaintext (photos + JSON) in temp storage: it must
      // not outlive the share, whether the share worked or failed. A leftover
      // is still removed by the next export, "Clear history" and the account
      // wipe.
      if (written != null) {
        try {
          if (await written.exists()) await written.delete(recursive: true);
        } catch (e) {
          debugPrint('scan history: export copy not removed (${e.runtimeType})');
        }
      }
    }
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.scanHistoryClearConfirmTitle),
        content: Text(l10n.scanHistoryClearConfirmBody),
        actions: <Widget>[
          TextButton(
            key: const Key('scan-history-clear-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            key: const Key('scan-history-clear-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.scanHistoryClear),
          ),
        ],
      ),
    );
    if (yes == true) await ref.read(scanHistoryRecorderProvider).clear();
  }
}

String _sourceLabel(AppLocalizations l10n, ScanSource s) => switch (s) {
      ScanSource.camera => l10n.scanHistorySourceCamera,
      ScanSource.gallery => l10n.scanHistorySourceGallery,
      ScanSource.live => l10n.scanHistorySourceLive,
    };

String _answeredLabel(AppLocalizations l10n, ScanAnsweredBy a) => switch (a) {
      ScanAnsweredBy.cloud => l10n.scanHistoryAnsweredCloud,
      ScanAnsweredBy.onDevice => l10n.scanHistoryAnsweredOnDevice,
      ScanAnsweredBy.printedText => l10n.scanHistoryAnsweredPrintedText,
      ScanAnsweredBy.none => l10n.scanHistoryAnsweredNone,
    };

String _when(BuildContext context, DateTime t) {
  final local = t.toLocal();
  final m = MaterialLocalizations.of(context);
  return '${m.formatMediumDate(local)} '
      '${m.formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: true)}';
}

class _HistoryRow extends ConsumerWidget {
  const _HistoryRow({required this.record});
  final ScanRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final top = record.top;
    final String title = top == null
        ? _answeredLabel(l10n, record.answeredBy)
        : equipmentDisplayName(ref, top.equipmentId);
    return ListTile(
      key: Key('scan-history-row-${record.id}'),
      leading: _ScanPhoto(record: record, size: 52),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${_when(context, record.timestamp)} · '
        '${_sourceLabel(l10n, record.source)}\n'
        '${_answeredLabel(l10n, record.answeredBy)}',
      ),
      isThreeLine: true,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          for (final c in record.candidates)
            if (c.rating != null)
              Icon(
                c.rating == CandidateRating.ok
                    ? Icons.check_circle_rounded
                    : Icons.cancel_rounded,
                key: Key('scan-history-mark-${record.id}-${c.equipmentId}'),
                size: 14,
                color: c.rating == CandidateRating.ok
                    ? theme.colors.success
                    : theme.colors.danger,
              ),
        ],
      ),
      onTap: () => context.push('/scan-history/${record.id}'),
    );
  }
}

/// The saved picture of a scan, or a neutral tile (live readings, or a photo
/// that is gone).
class _ScanPhoto extends ConsumerWidget {
  const _ScanPhoto({required this.record, required this.size});
  final ScanRecord record;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final File? file = record.hasPhoto
        ? ref.watch(scanPhotoFileProvider(record.id)).valueOrNull
        : null;
    return ClipRRect(
      key: Key('scan-history-photo-${record.id}'),
      borderRadius: BorderRadius.circular(size * 0.2),
      child: SizedBox(
        width: size,
        height: size,
        child: file == null
            ? ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Icon(
                  record.source == ScanSource.live
                      ? Icons.sensors_rounded
                      : Icons.image_not_supported_outlined,
                  size: size * 0.45,
                ),
              )
            : Image.file(file,
                fit: BoxFit.cover,
                cacheWidth: (size * 2).round(),
                excludeFromSemantics: true,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.broken_image_outlined)),
      ),
    );
  }
}

/// One scan in full: the photo, what the model said, every candidate with
/// editable rating marks, what the user opened, and the build that made it.
class ScanHistoryDetailPage extends ConsumerWidget {
  const ScanHistoryDetailPage({super.key, required this.scanId});

  final String scanId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final records = ref.watch(scanHistoryProvider).valueOrNull;
    final ScanRecord? record =
        records?.where((r) => r.id == scanId).firstOrNull;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(title: Text(l10n.scanHistoryTitle)),
      body: record == null
          ? Center(
              child: records == null
                  ? const CircularProgressIndicator()
                  : Text(l10n.scanHistoryEmpty, textAlign: TextAlign.center))
          : ListView(
              key: const Key('scan-history-detail'),
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                if (record.hasPhoto)
                  _DetailPhoto(scanId: record.id),
                const SizedBox(height: 12),
                Text(
                  '${_when(context, record.timestamp)} · '
                  '${_sourceLabel(l10n, record.source)}',
                  style: theme.textTheme.titleSmall,
                ),
                Text(_answeredLabel(l10n, record.answeredBy),
                    key: const Key('scan-history-detail-answered'),
                    style: theme.textTheme.bodyMedium),
                if (record.openedEquipmentId != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      key: const Key('scan-history-detail-opened'),
                      record.pickedManually
                          ? l10n.scanHistoryPickedManually(equipmentDisplayName(
                              ref, record.openedEquipmentId!))
                          : l10n.scanHistoryOpened(equipmentDisplayName(
                              ref, record.openedEquipmentId!)),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(l10n.scanHistoryCandidates,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                if (record.candidates.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(l10n.scanHistoryNoCandidates),
                  ),
                for (final c in record.candidates)
                  ListTile(
                    key: Key('scan-history-candidate-${c.equipmentId}'),
                    contentPadding: EdgeInsets.zero,
                    leading: MachineThumb(equipmentId: c.equipmentId, size: 48),
                    title: Text(equipmentDisplayName(ref, c.equipmentId)),
                    subtitle: Text(l10n.scannerConfidence(
                        (c.confidence * 100).toStringAsFixed(0))),
                    trailing: RatingMarks(
                      scope: 'scan-history',
                      equipmentId: c.equipmentId,
                      rating: c.rating,
                      onChanged: (r) => ref
                          .read(scanHistoryRecorderProvider)
                          .rate(record.id, c.equipmentId, r),
                    ),
                  ),
                if (record.rawAnswer != null) ...<Widget>[
                  const SizedBox(height: 16),
                  Text(l10n.scanHistoryRawAnswer,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  SelectableText(
                    record.rawAnswer!,
                    key: const Key('scan-history-detail-raw'),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontFamily: 'monospace'),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  l10n.scanHistoryBuild(
                      '${record.appVersion} · ${record.appGitSha}'),
                  key: const Key('scan-history-detail-build'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colors.textSecondary),
                ),
              ],
            ),
    );
  }
}

class _DetailPhoto extends ConsumerWidget {
  const _DetailPhoto({required this.scanId});
  final String scanId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final File? file = ref.watch(scanPhotoFileProvider(scanId)).valueOrNull;
    if (file == null) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 300),
        child: Image.file(file,
            key: const Key('scan-history-detail-photo'),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.broken_image_outlined)),
      ),
    );
  }
}
