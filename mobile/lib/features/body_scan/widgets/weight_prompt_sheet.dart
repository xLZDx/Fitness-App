/// Modal sheet that asks for a current weight before the capture starts
/// (design s10: latest weight missing or >= 3 days old). Framework modal route:
/// outside semantics are blocked while open and focus returns to the trigger on
/// close (D-85). Initial focus goes to the heading.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/hud_tokens.dart';

/// Outcome of the sheet. A dismissal returns null from [WeightPromptSheet.show].
class WeightPromptResult {
  const WeightPromptResult.logged(double this.kg);
  const WeightPromptResult.skipped() : kg = null;

  /// The logged weight; null when the user skipped.
  final double? kg;
  bool get skipped => kg == null;
}

const double kBodyScanMinWeightKg = 20;
const double kBodyScanMaxWeightKg = 400;

/// Parses a typed weight accepting a comma or a point; null when invalid.
double? parseBodyScanWeight(String raw) {
  final v = double.tryParse(raw.trim().replaceAll(',', '.'));
  if (v == null || !v.isFinite) return null;
  if (v < kBodyScanMinWeightKg || v > kBodyScanMaxWeightKg) return null;
  return v;
}

class WeightPromptSheet extends StatefulWidget {
  const WeightPromptSheet({super.key, this.staleDays});

  /// Age of the latest weight in whole days; null = none on file.
  final int? staleDays;

  static Future<WeightPromptResult?> show(BuildContext context,
      {int? staleDays}) {
    return showModalBottomSheet<WeightPromptResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => WeightPromptSheet(staleDays: staleDays),
    );
  }

  @override
  State<WeightPromptSheet> createState() => _WeightPromptSheetState();
}

class _WeightPromptSheetState extends State<WeightPromptSheet> {
  final _controller = TextEditingController();
  bool _invalid = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final v = parseBodyScanWeight(_controller.text);
    if (v == null) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.of(context).pop(WeightPromptResult.logged(v));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hud = context.hud;
    final days = widget.staleDays;
    return Padding(
      padding: EdgeInsets.fromLTRB(HudTokens.screenGutter, 16,
          HudTokens.screenGutter, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Focus(
              autofocus: true,
              child: Semantics(
                header: true,
                focusable: true,
                child: Text(l10n.bodyScanWeightTitle,
                    key: const Key('bodyScan.weight.title'),
                    style: theme.textTheme.titleLarge
                        ?.copyWith(color: hud.textPrimary)),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              days == null
                  ? l10n.bodyScanWeightBodyMissing
                  : l10n.bodyScanWeightBodyStale(days),
              style:
                  theme.textTheme.bodyMedium?.copyWith(color: hud.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('bodyScan.weight.field'),
              controller: _controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                labelText: l10n.bodyScanWeightLabel,
                errorText: _invalid ? l10n.bodyScanWeightInvalid : null,
              ),
              onChanged: (_) {
                if (_invalid) setState(() => _invalid = false);
              },
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('bodyScan.weight.save'),
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: _save,
              child: Text(l10n.bodyScanWeightSave),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const Key('bodyScan.weight.skip'),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () =>
                  Navigator.of(context).pop(const WeightPromptResult.skipped()),
              child: Text(l10n.bodyScanWeightSkip),
            ),
          ],
        ),
      ),
    );
  }
}
