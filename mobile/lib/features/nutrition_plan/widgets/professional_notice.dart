/// The one calm, non-diagnostic notice shown instead of any number when the
/// device-local verdict is `referProfessional` (D-55). It never says why.
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../shared/widgets/glass.dart';

class ProfessionalNotice extends StatelessWidget {
  const ProfessionalNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(l10n.nutritionProfessionalTitle,
                style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          Text(l10n.nutritionProfessionalBody,
              style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
