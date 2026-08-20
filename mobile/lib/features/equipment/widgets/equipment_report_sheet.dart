import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../shared/widgets/glass.dart';
import '../../../shared/widgets/shell_insets.dart';
import '../../auth/state/auth_providers.dart';
import '../data/equipment_report.dart';
import '../state/equipment_providers.dart';
import '../../../core/theme/app_semantic_colors.dart';
import '../../../shared/widgets/app_buttons.dart';

/// Modal bottom sheet for reporting broken / degraded equipment. Two-tap
/// flow: pick a fault category + optional note → submit. Returns to the
/// caller via Navigator.pop with `true` on success.
class EquipmentReportSheet extends ConsumerStatefulWidget {
  const EquipmentReportSheet({
    super.key,
    required this.equipmentId,
    required this.equipmentName,
    this.gymId = 'unknown',
  });

  final String equipmentId;
  final String equipmentName;
  final String gymId;

  static Future<bool?> show(
    BuildContext context, {
    required String equipmentId,
    required String equipmentName,
    String gymId = 'unknown',
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => EquipmentReportSheet(
        equipmentId: equipmentId,
        equipmentName: equipmentName,
        gymId: gymId,
      ),
    );
  }

  @override
  ConsumerState<EquipmentReportSheet> createState() =>
      _EquipmentReportSheetState();
}

class _EquipmentReportSheetState extends ConsumerState<EquipmentReportSheet> {
  EquipmentFault _fault = EquipmentFault.degraded;
  final _noteCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  /// codex review, round 3, 2026-08-21: `widget.gymId` is the saved gym from
  /// the user's *profile*, not confirmed as the gym this specific report is
  /// about. A report filed while actually at a different gym/branch would
  /// otherwise silently route to the saved one -- misdelivery to a third
  /// party, not just the already-acknowledged nondelivery risk from a
  /// free-text/registry mismatch. Unchecked by default: routing requires an
  /// explicit per-report confirmation, never trust-by-default.
  bool _confirmedGym = false;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final user = ref.read(authUserProvider).valueOrNull;
    if (user == null) {
      setState(() => _error = 'Sign in to submit a report.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final report = EquipmentReport(
      id: '${DateTime.now().microsecondsSinceEpoch}_${widget.equipmentId}',
      equipmentId: widget.equipmentId,
      gymId: _confirmedGym ? widget.gymId : 'unknown',
      fault: _fault,
      note: _noteCtrl.text.trim(),
      reportedAt: DateTime.now(),
      reporterUid: user.uid,
    );
    try {
      await ref.read(equipmentReportServiceProvider).submit(report);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        24,
        16,
        // Keyboard OR gesture indicator, whichever is taller. This handled
        // only the keyboard, so with it down the Send row sat in the system's
        // swipe band.
        sheetBottomInset(context, base: 24),
      ),
      child: GlassCard(
        floating: true,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.of(context).equipmentReportBrokenEquipment,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(widget.equipmentName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colors.textSecondary,
                )),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in EquipmentFault.values)
                  ChoiceChip(
                    label: Text(_label(l10n, f)),
                    selected: _fault == f,
                    onSelected: (_) => setState(() => _fault = f),
                  ),
              ],
            ),
            if (widget.gymId != 'unknown') ...[
              const SizedBox(height: 14),
              InkWell(
                key: const Key('equipment-report-confirm-gym'),
                borderRadius: BorderRadius.circular(10),
                onTap: () =>
                    setState(() => _confirmedGym = !_confirmedGym),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: _confirmedGym,
                        onChanged: (v) =>
                            setState(() => _confirmedGym = v ?? false),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            l10n.equipmentReportConfirmGym(widget.gymId),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _noteCtrl,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)
                    .equipmentOptionalNoteEGCableFrayed,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.32),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.error,
                ),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: AppPrimaryButton(
                tone: AppButtonTone.brand,
                size: AppButtonSize.compact,
                loading: _submitting,
                onPressed: _submit,
                label: AppLocalizations.of(context).equipmentSendToMaintenance,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).equipmentReportsAreForwardedToTheGym,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _label(AppLocalizations l10n, EquipmentFault f) {
    switch (f) {
      case EquipmentFault.unsafe:
        return l10n.equipmentFaultUnsafe;
      case EquipmentFault.degraded:
        return l10n.equipmentFaultDegraded;
      case EquipmentFault.qrMissing:
        return l10n.equipmentFaultQrMissing;
      case EquipmentFault.other:
        return l10n.equipmentFaultOther;
    }
  }
}
