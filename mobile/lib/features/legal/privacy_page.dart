import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../shared/widgets/glass.dart';
import 'legal_body.dart';
import 'terms_page.dart' show TermsPage;
import '../../core/theme/app_semantic_colors.dart';

/// Privacy Policy. Same history as [TermsPage] — see its doc comment for how
/// both pages went from an openly-flagged placeholder to real text.
///
/// A privacy policy for this specific app could never have been boilerplate.
/// Three facts about the code rule a template out on their own, and all three
/// are now stated plainly in the text:
///
///   - `HealthHistory` (conditions, allergies, medications, injuries,
///     surgeries) is health data under the GDPR's special categories;
///   - the gym-machine scanner sends the photo to Google's Gemini
///     (`gemini_equipment_service.dart:37-48`), which a generic "we may use
///     third-party services" clause would bury rather than disclose — a gym
///     frame can contain people who never installed this app;
///   - `donor_wall` is genuinely public, by the user's own opt-in, with a
///     60/200-character limit enforced server-side (`index.ts:741-756`).
///
/// The favourable facts are stated just as plainly, because they are equally
/// checkable: health answers never reach an AI model (the coach's whole prompt
/// is a machine name and a language, `ai_coach_service.dart:33-40`), progress
/// photos never leave the device (`progress_photos_providers.dart:13`), and
/// there is no advertising or analytics SDK in `pubspec.yaml` at all.
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return FrostedScaffold(
      appBar: GlassAppBar(title: l10n.legalPrivacyPolicy),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 40),
        children: [
          Text(
            l10n.legalLastUpdated,
            key: const Key('privacy-last-updated'),
            style: (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
              color: theme.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          GlassCard(child: LegalBody(l10n.legalPrivacyBody)),
        ],
      ),
    );
  }
}
