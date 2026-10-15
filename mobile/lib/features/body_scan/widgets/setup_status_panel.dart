/// The four-row setup status panel of the guided scan (design s11): Distance,
/// Lighting, Position and Pose, each with an icon, a label and a state text, so
/// no row relies on colour alone. A failing row shows the specific prompt of
/// the current hint when the hint belongs to that row ("Step back a little"),
/// otherwise the generic "Adjust".
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../progress_photos/scan/readiness_evaluator.dart';
import '../../progress_photos/scan/ui/scan_text.dart';

/// The four rows, in display order.
enum SetupCheck { distance, lighting, position, orientation }

/// Which row a hint belongs to; null for hints that name no single row.
SetupCheck? checkOfHint(ReadinessHint hint) => switch (hint) {
      ReadinessHint.showFullBody ||
      ReadinessHint.stepBack ||
      ReadinessHint.stepCloser =>
        SetupCheck.distance,
      ReadinessHint.moreLight || ReadinessHint.lessLight => SetupCheck.lighting,
      ReadinessHint.centerYourself => SetupCheck.position,
      ReadinessHint.turnSideways ||
      ReadinessHint.turnAround ||
      ReadinessHint.faceCamera =>
        SetupCheck.orientation,
      ReadinessHint.none || ReadinessHint.trackingProblem => null,
    };

CheckStatus? statusOfCheck(ReadinessResult? r, SetupCheck c) {
  if (r == null) return null;
  return switch (c) {
    SetupCheck.distance => r.distance,
    SetupCheck.lighting => r.lighting,
    SetupCheck.position => r.position,
    SetupCheck.orientation => r.orientation,
  };
}

class SetupStatusPanel extends StatelessWidget {
  const SetupStatusPanel({super.key, required this.result});

  final ReadinessResult? result;

  String _label(AppLocalizations l10n, SetupCheck c) => switch (c) {
        SetupCheck.distance => l10n.scanCheckDistance,
        SetupCheck.lighting => l10n.scanCheckLighting,
        SetupCheck.position => l10n.scanCheckPosition,
        SetupCheck.orientation => l10n.scanCheckOrientation,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final r = result;
    return Column(
      key: const Key('scan.statusPanel'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in SetupCheck.values)
          _StatusRow(
            keyName: c.name,
            label: _label(l10n, c),
            status: statusOfCheck(r, c) ?? CheckStatus.unknown,
            failText: r != null && checkOfHint(r.hint) == c
                ? hintText(l10n, r.hint)
                : l10n.scanCheckFix,
          ),
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.keyName,
    required this.label,
    required this.status,
    required this.failText,
  });

  final String keyName;
  final String label;
  final CheckStatus status;
  final String failText;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (color, icon, text) = switch (status) {
      CheckStatus.pass => (Colors.greenAccent, Icons.check_circle, l10n.scanCheckOk),
      CheckStatus.fail => (Colors.orangeAccent, Icons.error_outline, failText),
      CheckStatus.unknown =>
        (Colors.white, Icons.hourglass_empty, l10n.scanCheckWaiting),
    };
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(color: color);
    return Semantics(
      container: true,
      label: '$label: $text',
      child: ExcludeSemantics(
        child: Padding(
          key: Key('scan.check.$keyName.${status.name}'),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('$label: $text', style: style)),
            ],
          ),
        ),
      ),
    );
  }
}
