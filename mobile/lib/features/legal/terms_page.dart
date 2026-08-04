import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../shared/widgets/glass.dart';

/// Terms of Service.
///
/// ## Why this page exists, and why its body is a placeholder
///
/// `login_page.dart` has said "By continuing you agree to our Terms and
/// Privacy Policy" since the login screen shipped, with no route either word
/// linked to. That is the exact shape of claim S0a spent two gates removing
/// from the injury filter — a sentence asserting something the product does
/// not actually provide. L0a closes the *reachability* gap: a real route,
/// linked from where the claim is made and from Settings.
///
/// The words on this page are NOT written here. Terms of Service is a binding
/// legal document — what data is collected, what liability the operator
/// accepts for exercise guidance, dispute resolution, governing law — and
/// drafting one is a legal decision, not a code change. Writing plausible-
/// sounding legal text and shipping it as the real Terms would be the same
/// failure mode this gate exists to close, aimed at a target with real
/// consequences if it is wrong. `kIsPlaceholderContent` names that state in
/// code so it cannot be shipped by accident, and the page renders a visible
/// notice for the same reason — a placeholder nobody can see is a
/// placeholder that ships.
class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  /// True until the operator replaces [_body] with reviewed legal text.
  ///
  /// Checked by `test/features/legal/legal_pages_test.dart`'s release-readiness
  /// group, which is meant to start failing the day someone flips this to
  /// false without also replacing the body — a stale flag would otherwise say
  /// "reviewed" about placeholder text forever.
  static const bool kIsPlaceholderContent = true;

  static const List<String> _body = [
    'This is placeholder text. Replace it with the operator\'s reviewed '
        'Terms of Service before this app is submitted to any app store or '
        'used by anyone other than the operator.',
    'A real Terms of Service for a fitness app should address at least: '
        'what account and health data is collected and why; that exercise '
        'guidance is not medical advice and carries injury risk the user '
        'accepts; subscription billing terms and cancellation; content '
        'ownership for contributed videos; account termination; dispute '
        'resolution and governing law.',
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return FrostedScaffold(
      appBar: GlassAppBar(title: l10n.legalTermsOfService),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 40),
        children: [
          if (kIsPlaceholderContent)
            GlassCard(
              key: const Key('terms-placeholder-notice'),
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
