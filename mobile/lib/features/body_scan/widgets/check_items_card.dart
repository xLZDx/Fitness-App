/// The "check these" card of the result (design s12.7, D-85). Each item is a
/// chip with icon + text + an explicit state label ("needs checking" /
/// "resolved"), never colour alone. "N items to check" is announced once when
/// the card appears; resolving a chip moves focus to the next unresolved chip,
/// or to the card heading when none is left.
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../shared/widgets/glass.dart';
import '../data/check_items.dart';

/// The localized text of a closed check code. Provider free text never reaches
/// the screen.
String checkCodeText(AppLocalizations l10n, CheckCode code) => switch (code) {
      CheckCode.provisionalEstimator => l10n.checkCodeProvisionalEstimator,
      CheckCode.manualCapture => l10n.checkCodeManualCapture,
      CheckCode.poorLighting => l10n.checkCodePoorLighting,
      CheckCode.partialBody => l10n.checkCodePartialBody,
      CheckCode.looseClothing => l10n.checkCodeLooseClothing,
      CheckCode.poseMismatch => l10n.checkCodePoseMismatch,
      CheckCode.weightMissing => l10n.checkCodeWeightMissing,
      CheckCode.weightStale => l10n.checkCodeWeightStale,
      CheckCode.weightJump => l10n.checkCodeWeightJump,
      CheckCode.wideRange => l10n.checkCodeWideRange,
      CheckCode.estimateFarFromProfile => l10n.checkCodeEstimateFarFromProfile,
      CheckCode.largeJumpVsTrend => l10n.checkCodeLargeJumpVsTrend,
      CheckCode.blurUnavailable => l10n.checkCodeBlurUnavailable,
    };

String checkActionLabel(AppLocalizations l10n, CheckAction a) => switch (a) {
      CheckAction.none => '',
      CheckAction.retakeLighting ||
      CheckAction.retakeFraming ||
      CheckAction.retakePose =>
        l10n.bodyScanActionRetake,
      CheckAction.logWeight => l10n.bodyScanActionLogWeight,
      CheckAction.confirmWeight => l10n.bodyScanActionConfirmWeight,
    };

class CheckItemsCard extends StatefulWidget {
  const CheckItemsCard({
    super.key,
    required this.items,
    this.onAction,
  });

  final List<CheckCode> items;

  /// Called for an item that has an action (retake, log weight, ...).
  final void Function(CheckAction action)? onAction;

  @override
  State<CheckItemsCard> createState() => _CheckItemsCardState();
}

class _CheckItemsCardState extends State<CheckItemsCard> {
  final Set<CheckCode> _resolved = {};
  final FocusNode _headingFocus = FocusNode();
  late final Map<CheckCode, FocusNode> _chipFocus = {
    for (final c in widget.items) c: FocusNode(),
  };

  @override
  void dispose() {
    _headingFocus.dispose();
    for (final f in _chipFocus.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _resolve(CheckCode code) {
    setState(() => _resolved.add(code));
    CheckCode? next;
    for (final c in widget.items) {
      if (!_resolved.contains(c)) {
        next = c;
        break;
      }
    }
    final target = next == null ? _headingFocus : _chipFocus[next];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) target?.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hud = context.hud;
    final open = widget.items.where((c) => !_resolved.contains(c)).length;
    final heading = open == 0
        ? l10n.bodyScanChecksAllResolved
        : l10n.bodyScanChecksCount(open);
    return GlassCard(
      key: const Key('bodyScan.checks.card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Focus(
            focusNode: _headingFocus,
            child: Semantics(
              header: true,
              // Announced once when the card appears; later changes are
              // conveyed by focus moves, not by repeated announcements.
              liveRegion: _resolved.isEmpty,
              child: Text(
                '${l10n.bodyScanChecksTitle}: $heading',
                key: const Key('bodyScan.checks.heading'),
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: hud.textPrimary),
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final code in widget.items)
            _Chip(
              code: code,
              resolved: _resolved.contains(code),
              focusNode: _chipFocus[code]!,
              onResolve: () => _resolve(code),
              onAction: widget.onAction,
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.code,
    required this.resolved,
    required this.focusNode,
    required this.onResolve,
    required this.onAction,
  });

  final CheckCode code;
  final bool resolved;
  final FocusNode focusNode;
  final VoidCallback onResolve;
  final void Function(CheckAction action)? onAction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hud = context.hud;
    final text = checkCodeText(l10n, code);
    final state = resolved ? l10n.bodyScanChipResolved : l10n.bodyScanChipNeeds;
    final actionLabel = checkActionLabel(l10n, code.action);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            container: true,
            button: !resolved,
            label: l10n.bodyScanChipItem(text, state),
            hint: resolved ? null : l10n.bodyScanChipMarkResolved,
            excludeSemantics: true,
            onTap: resolved ? null : onResolve,
            child: InkWell(
              key: Key('bodyScan.checks.chip.${code.name}'),
              focusNode: focusNode,
              borderRadius: BorderRadius.circular(HudTokens.radiusChip),
              onTap: resolved ? null : onResolve,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        resolved
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        color: resolved ? hud.success : hud.warning,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(text,
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(color: hud.textPrimary)),
                            Text(state,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: hud.textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (actionLabel.isNotEmpty && !resolved && onAction != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: Key('bodyScan.checks.action.${code.name}'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => onAction!(code.action),
                child: Text(actionLabel),
              ),
            ),
        ],
      ),
    );
  }
}
