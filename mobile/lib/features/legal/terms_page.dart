import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../shared/widgets/glass.dart';
import 'legal_body.dart';

/// Terms of Service.
///
/// ## How this page stopped being a placeholder
///
/// `login_page.dart` has said "By continuing you agree to our Terms and
/// Privacy Policy" since the login screen shipped, with no route either word
/// linked to. L0a closed the *reachability* gap with a real route whose body
/// was openly marked as placeholder text, behind a `kIsPlaceholderContent`
/// flag and a red in-page warning — because writing plausible-sounding legal
/// text and shipping it as the real Terms would have been the same failure
/// mode S0a spent two gates removing from the injury filter, aimed at a target
/// with real consequences.
///
/// P0 closed the *content* gap. The text is now real, and every factual claim
/// in it was verified against this repo rather than copied from a template —
/// the prices against `subscription_page.dart:960-977`, the 15% coach fee
/// against `functions/src/index.ts:985`, the "not reviewed by a
/// physiotherapist" line against the same fact S0b established, and the "not
/// tax-deductible" line against there being no nonprofit status at all.
///
/// The flag and the warning card are gone rather than flipped to `false`: a
/// boolean nothing reads is the stale flag its own doc comment warned about.
/// What replaced it is `test/features/legal/legal_pages_test.dart`, which
/// asserts against the rendered text itself — including the two claims S0b
/// removed, so a regression that re-introduces them fails a test instead of
/// reaching a store listing.
///
/// The words live in `scripts/legal/legal_text.py`, which also generates
/// `public/terms.html` — the URL Google Play requires. See [LegalBody].
class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return FrostedScaffold(
      appBar: GlassAppBar(title: l10n.legalTermsOfService),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 40),
        children: [
          Text(
            l10n.legalLastUpdated,
            key: const Key('terms-last-updated'),
            style: (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 16),
          GlassCard(child: LegalBody(l10n.legalTermsBody)),
        ],
      ),
    );
  }
}
