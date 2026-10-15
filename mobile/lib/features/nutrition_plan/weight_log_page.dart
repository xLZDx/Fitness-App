/// The weight log `/nutrition/weight` (design s5.3, D-72): add / edit / delete a
/// weigh-in. States when the first plan review can act ("after about 3
/// weigh-ins over 2 weeks"). Every write first passes
/// `ensureDataNoticeAcknowledged`; a declined notice defers the write.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/privacy/data_notice.dart';
import '../../core/theme/hud_tokens.dart';
import '../../shared/widgets/glass.dart';
import 'data/weight_entry.dart';
import 'data/weight_repository.dart';
import 'state/weight_providers.dart';

/// Parses a typed weight accepting a comma or a point; null when invalid
/// (outside 30..300 kg).
double? parseLoggedWeight(String raw) {
  final v = double.tryParse(raw.trim().replaceAll(',', '.'));
  if (v == null || !WeightEntry.isValidKg(v)) return null;
  return v;
}

class WeightLogPage extends ConsumerWidget {
  const WeightLogPage({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref,
      {WeightLogItem? item}) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final result = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _WeightSheet(initialKg: item?.entry.kg),
    );
    if (result == null || !context.mounted) return;
    if (!await ensureDataNoticeAcknowledged(context, ref)) return;
    final actions = ref.read(weightLogActionsProvider);
    final status = item == null
        ? await actions.add(result)
        : await actions.edit(item, kg: result);
    messenger.showSnackBar(SnackBar(
        content: Text(status == WeightWriteStatus.saved
            ? l10n.weightLogSaved
            : l10n.weightLogUnavailable)));
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, WeightLogItem item) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.weightLogDeleteTitle),
        content: Text(l10n.weightLogDeleteBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.weightLogCancel)),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.weightLogDelete)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    if (!await ensureDataNoticeAcknowledged(context, ref)) return;
    final status = await ref.read(weightLogActionsProvider).delete(item);
    messenger.showSnackBar(SnackBar(
        content: Text(status == WeightWriteStatus.saved
            ? l10n.weightLogDeleted
            : l10n.weightLogUnavailable)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hud = context.hud;
    final locale = Localizations.localeOf(context).toString();
    final items = ref.watch(weightLogItemsProvider);
    final nf = NumberFormat('0.0#', locale);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.weightLogTitle)),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('weightLog.add'),
        onPressed: () => _edit(context, ref),
        icon: const Icon(Icons.add),
        label: Text(l10n.weightLogAdd),
      ),
      body: SafeArea(
        child: items.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(child: Text(l10n.weightLogLoadError)),
          data: (list) {
            final newestFirst = list.reversed.toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(
                  HudTokens.screenGutter, HudTokens.screenGutter,
                  HudTokens.screenGutter, 96),
              children: [
                GlassCard(
                  child: Text(l10n.weightLogIntro,
                      style: theme.textTheme.bodyMedium),
                ),
                const SizedBox(height: 12),
                if (newestFirst.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(l10n.weightLogEmpty,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: hud.textSecondary)),
                  ),
                for (final item in newestFirst)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      minVerticalPadding: 12,
                      title: Text(l10n.weightLogValue(
                          nf.format(item.entry.kg))),
                      subtitle: Text(
                        '${DateFormat.yMMMd(locale).format(item.entry.at.toLocal())}'
                        ' - ${item.entry.source == WeightSource.scan ? l10n.weightLogSourceScan : l10n.weightLogSourceManual}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: l10n.weightLogEdit,
                            constraints: const BoxConstraints(
                                minWidth: 48, minHeight: 48),
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _edit(context, ref, item: item),
                          ),
                          IconButton(
                            tooltip: l10n.weightLogDelete,
                            constraints: const BoxConstraints(
                                minWidth: 48, minHeight: 48),
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(context, ref, item),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WeightSheet extends StatefulWidget {
  const _WeightSheet({this.initialKg});

  final double? initialKg;

  @override
  State<_WeightSheet> createState() => _WeightSheetState();
}

class _WeightSheetState extends State<_WeightSheet> {
  late final TextEditingController _controller = TextEditingController(
      text: widget.initialKg == null
          ? ''
          : widget.initialKg!.toStringAsFixed(1));
  bool _invalid = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final v = parseLoggedWeight(_controller.text);
    if (v == null) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
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
                child: Text(
                    widget.initialKg == null
                        ? l10n.weightLogAdd
                        : l10n.weightLogEdit,
                    style: theme.textTheme.titleLarge),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('weightLog.field'),
              controller: _controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                labelText: l10n.weightLogFieldLabel,
                errorText: _invalid ? l10n.weightLogInvalid : null,
              ),
              onChanged: (_) {
                if (_invalid) setState(() => _invalid = false);
              },
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 48)),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.weightLogCancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const Key('weightLog.save'),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 48)),
                    onPressed: _save,
                    child: Text(l10n.weightLogSave),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
