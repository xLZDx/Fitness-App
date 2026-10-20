import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../core/theme/hud_typography.dart';
import '../data/coach_registry.dart';
import '../data/coach_spec.dart';
import '../state/form_check_providers.dart';

/// Whether the registry row coaching [e] is still beta (authored, not measured).
bool isBetaExercise(CoachRegistry? registry, FormExercise e) =>
    coachSpecFor(registry, e)?.provenance.status ==
    CoachProvenanceStatus.beta;

/// A small neutral "Beta" pill. Deliberately not a warning colour: beta here
/// means "ranges are authored, not yet measured", not "dangerous".
class CoachBetaBadge extends StatelessWidget {
  const CoachBetaBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.hud;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.textSecondary.withValues(alpha: 0.6)),
      ),
      child: Text(
        AppLocalizations.of(context).formcheckBetaBadge,
        style: HudType.body(t, size: 11).copyWith(
          fontWeight: FontWeight.w700,
          height: 1.0,
          color: t.textSecondary,
        ),
      ),
    );
  }
}

/// The badge plus the one-line explanation. Shown under the movement chips for
/// a beta movement, on both the picker and the live coaching screen.
class CoachBetaNote extends StatelessWidget {
  const CoachBetaNote({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      key: const Key('form_check.beta_note'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CoachBetaBadge(),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            l10n.formcheckBetaNote,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
