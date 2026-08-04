import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../shared/widgets/glass.dart';
import 'terms_page.dart' show TermsPage;

/// Privacy Policy. Same reasoning as [TermsPage] — see its doc comment for
/// why the route exists now and the legal text does not.
///
/// A privacy policy for this specific app has to be honest about what is
/// actually true of the code, not generic boilerplate: `HealthHistory`
/// (injuries, conditions, medications) is health data under most privacy
/// regimes, `aboutNoDataResaleEver` is a claim already made on `/about` that
/// the policy has to be consistent with, and `donor_wall` is genuinely
/// public by the user's own opt-in — those three facts alone rule out a
/// copy-pasted template.
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  /// See [TermsPage.kIsPlaceholderContent] — same meaning, same reason.
  static const bool kIsPlaceholderContent = true;

  static const List<String> _body = [
    'This is placeholder text. Replace it with the operator\'s reviewed '
        'Privacy Policy before this app is submitted to any app store or '
        'used by anyone other than the operator.',
    'A real Privacy Policy for this app should address at least: that '
        'health data (injuries, conditions, medications) is collected via '
        'the onboarding questionnaire and used to filter exercise '
        'recommendations; that this data is never sold, matching the claim '
        'already made on the About page; what is stored in Firestore and '
        'for how long; that the donor wall is public by explicit user opt-in '
        'only; third-party processors (Firebase, Stripe); data export and '
        'deletion rights; and the age/consent basis for use by minors, if '
        'any.',
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return FrostedScaffold(
      appBar: GlassAppBar(title: l10n.legalPrivacyPolicy),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 40),
        children: [
          if (kIsPlaceholderContent)
            GlassCard(
              key: const Key('privacy-placeholder-notice'),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: theme.colorScheme.error),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.legalPlaceholderNotice,
                      // Explicit fallback, not `?.copyWith`. `bodyMedium` is
                      // never null under this app's own theme, but this is the
                      // one line whose entire job is to be visibly red -- a
                      // silently-swallowed null here would render the warning
                      // in default styling with nothing to say it degraded,
                      // which is the exact failure this page exists to avoid.
                      style: (theme.textTheme.bodyMedium ??
                              const TextStyle())
                          .copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final paragraph in _body) ...[
                  Text(paragraph, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
