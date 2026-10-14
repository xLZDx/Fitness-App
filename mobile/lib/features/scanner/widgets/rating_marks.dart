import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/app_semantic_colors.dart';
import '../history/scan_record.dart';
import 'zoom_controls.dart' show kScanTouchTarget;

/// Two small optional marks for a candidate: OK (check) and NOT OK (cross).
///
/// Operator order 2026-10-14 (C). The rating is the user's own verdict on a
/// candidate, kept in the on-phone scan history to compare the model with
/// reality. It is OPTIONAL and never blocks anything: tapping the active mark
/// again clears it, and opening the machine works the same with or without it.
/// The marks swallow their own taps, so rating a row does not open the row.
///
/// Keys: `<scope>-rate-ok-<id>` and `<scope>-rate-notok-<id>`.
class RatingMarks extends StatelessWidget {
  const RatingMarks({
    super.key,
    required this.equipmentId,
    required this.rating,
    required this.onChanged,
    this.scope = 'scan',
  });

  final String equipmentId;
  final CandidateRating? rating;

  /// Called with the NEW rating: the tapped one, or null when the tapped mark
  /// was already active (clears it).
  final ValueChanged<CandidateRating?> onChanged;

  /// Key prefix, so the Scan list and the history detail can both be on a
  /// screen in a test without clashing.
  final String scope;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _Mark(
          key: Key('$scope-rate-ok-$equipmentId'),
          icon: Icons.check_circle_rounded,
          outline: Icons.check_circle_outline_rounded,
          active: rating == CandidateRating.ok,
          color: context.colors.success,
          label: l10n.scanRateOk,
          onTap: () => onChanged(
              rating == CandidateRating.ok ? null : CandidateRating.ok),
        ),
        _Mark(
          key: Key('$scope-rate-notok-$equipmentId'),
          icon: Icons.cancel_rounded,
          outline: Icons.cancel_outlined,
          active: rating == CandidateRating.notOk,
          color: context.colors.danger,
          label: l10n.scanRateNotOk,
          onTap: () => onChanged(
              rating == CandidateRating.notOk ? null : CandidateRating.notOk),
        ),
      ],
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark({
    super.key,
    required this.icon,
    required this.outline,
    required this.active,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final IconData outline;
  final bool active;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // A 44px target around a 22px glyph: small on screen, a full-size
        // touch target.
        child: SizedBox(
          width: kScanTouchTarget,
          height: kScanTouchTarget,
          child: Icon(
            active ? icon : outline,
            size: 22,
            color: active ? color : context.colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
