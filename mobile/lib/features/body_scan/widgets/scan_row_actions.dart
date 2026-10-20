/// The two destructive/editing flows of a scan, usable from the history list
/// and from the result screen (C16): edit the recorded weight and delete the
/// scan's photos. Both use framework dialogs (focus moves in, outside
/// semantics are blocked, focus returns to the trigger, D-85).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/privacy/data_notice.dart';
import '../state/scan_history_actions.dart';
import '../state/scan_history_rows.dart';
import 'weight_prompt_sheet.dart' show parseBodyScanWeight;

/// Asks for a new weight, then writes it everywhere it lives (D-72).
Future<void> editScanWeightFlow(
  BuildContext context,
  WidgetRef ref,
  ScanHistoryRow row,
) async {
  final kg = await showDialog<double>(
    context: context,
    builder: (_) => _EditWeightDialog(initialKg: row.weightKg),
  );
  if (kg == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);
  // The notice is the caller's job: when it is declined the scan weight is
  // still updated and only the weight-log write is deferred.
  final acknowledged = await ensureDataNoticeAcknowledged(context, ref);
  final outcome = await ref
      .read(scanHistoryActionsProvider)
      .editWeight(row, kg, writeDayEntry: acknowledged);
  final text = switch (outcome) {
    EditWeightOutcome.saved => l10n.bodyScanEditWeightSaved,
    EditWeightOutcome.invalid => l10n.bodyScanEditWeightInvalid,
    EditWeightOutcome.failed => l10n.bodyScanEditWeightFailed,
  };
  messenger.showSnackBar(SnackBar(content: Text(text)));
}

class _EditWeightDialog extends StatefulWidget {
  const _EditWeightDialog({this.initialKg});

  final double? initialKg;

  @override
  State<_EditWeightDialog> createState() => _EditWeightDialogState();
}

class _EditWeightDialogState extends State<_EditWeightDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialKg == null
        ? ''
        : widget.initialKg!.toStringAsFixed(1).replaceAll('.0', ''),
  );
  bool _invalid = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final v = parseBodyScanWeight(_controller.text);
    // The weight log accepts 30..300 kg; a value outside it would be saved on
    // the scan but refused by the log, so it is refused here.
    if (v == null || v < 30 || v > 300) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const Key('bodyScan.editWeight.dialog'),
      title: Semantics(
        header: true,
        focusable: true,
        child: Text(l10n.bodyScanEditWeightTitle),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('bodyScan.editWeight.field'),
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: InputDecoration(
              labelText: l10n.bodyScanWeightLabel,
              errorText: _invalid ? l10n.bodyScanEditWeightInvalid : null,
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 8),
          Text(l10n.bodyScanEditWeightHint,
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('bodyScan.editWeight.cancel'),
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.bodyScanCancel),
        ),
        FilledButton(
          key: const Key('bodyScan.editWeight.save'),
          style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: _save,
          child: Text(l10n.bodyScanEditWeightSave),
        ),
      ],
    );
  }
}

/// Confirms, then deletes the scan's photos (cloud copy first, then the phone
/// copy). Offline the delete is owed and finished later (D-78).
Future<void> deleteScanPhotosFlow(
  BuildContext context,
  WidgetRef ref,
  ScanHistoryRow row,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('bodyScan.deletePhotos.dialog'),
      title: Semantics(
        header: true,
        focusable: true,
        child: Text(l10n.bodyScanDeletePhotosTitle),
      ),
      content: Text(l10n.bodyScanDeletePhotosBody),
      actions: [
        TextButton(
          key: const Key('bodyScan.deletePhotos.cancel'),
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.bodyScanCancel),
        ),
        FilledButton(
          key: const Key('bodyScan.deletePhotos.confirm'),
          style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.bodyScanDeletePhotosConfirm),
        ),
      ],
    ),
  );
  if (ok != true) return;
  final outcome = await ref.read(scanHistoryActionsProvider).deletePhotos(row);
  final text = switch (outcome) {
    DeletePhotosOutcome.deleted => l10n.bodyScanDeletePhotosDone,
    DeletePhotosOutcome.queuedOffline => l10n.bodyScanDeletePhotosQueued,
    DeletePhotosOutcome.failed => l10n.bodyScanDeletePhotosFailed,
  };
  messenger.showSnackBar(SnackBar(content: Text(text)));
}
