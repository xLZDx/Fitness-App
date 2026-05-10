import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../shared/widgets/glass.dart';
import '../../auth/state/auth_providers.dart';
import '../data/equipment_report.dart';
import '../state/equipment_providers.dart';

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
      gymId: widget.gymId,
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        24,
        16,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: GlassCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Report broken equipment',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(widget.equipmentName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.65),
                )),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in EquipmentFault.values)
                  ChoiceChip(
                    label: Text(_label(f)),
                    selected: _fault == f,
                    onSelected: (_) => setState(() => _fault = f),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _noteCtrl,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Optional note (e.g. "cable frayed near top")',
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
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppPalette.auroraPeach,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Send to maintenance'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Reports are forwarded to the gym\'s maintenance team. Your '
              'identity is shared with the gym only if they ask to follow up.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _label(EquipmentFault f) {
    switch (f) {
      case EquipmentFault.unsafe:
        return 'Unsafe';
      case EquipmentFault.degraded:
        return 'Degraded';
      case EquipmentFault.qrMissing:
        return 'QR missing';
      case EquipmentFault.other:
        return 'Other';
    }
  }
}
