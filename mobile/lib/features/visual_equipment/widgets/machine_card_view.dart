import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_semantic_colors.dart';
import '../../../shared/widgets/app_buttons.dart';
import '../../../shared/widgets/glass.dart';
import '../../safety/state/eligibility_providers.dart';
import '../data/machine_card.dart';

/// What the user sees when they photographed a real machine the app has no
/// page for.
///
/// The old answer here was "Не удалось понять, что это" and nothing else,
/// which is both unhelpful and, once the second question exists, untrue — we
/// DID work out what it is, we just have no clip. Operator: *"объяснить
/// человеку, что за железка перед ним и что на нем можно делать"*, and the
/// card is the user's, marked honestly: *"пользователю тоже видна как «контент
/// готовится»"*.
///
/// The button out is the other half of the instruction — *"а клиенту
/// посоветовать ролик на ютюбе или еще где пока мы не добавим новый
/// контент"*. Sending someone to a video that exists beats an empty page.
/// ## Why `uses` is conditional (F016)
///
/// `uses` is free text the model wrote about a machine that is, by
/// definition, not in the catalogue — `MachineDescriber` is asked only after
/// recognition came back empty. It carries no `contraindications` field and
/// nothing can attach one, so `isContraindicated` would return false for
/// every line of it however the user is injured.
///
/// That is the same problem `equipment_providers.dart:481-482` already
/// solved for `ai::` exercises, and it takes the same answer: withheld for a
/// user there is anything to screen against, rather than shown unscreened.
/// Matching each line against the catalogue was considered and rejected — a
/// machine this card exists for has no catalogue entry, so a catalogue match
/// would suppress the list for everybody and delete the feature instead of
/// making it safe.
class MachineCardView extends ConsumerWidget {
  const MachineCardView({
    super.key,
    required this.card,
    this.onWatchElsewhere,
    this.showPhoto = true,
  });

  final MachineCard card;

  /// Injectable so the test does not open a browser. Defaults to a YouTube
  /// search for [MachineCard.searchQuery].
  final Future<bool> Function(Uri uri)? onWatchElsewhere;

  final bool showPhoto;

  Future<void> _watch() async {
    final uri = Uri.https(
      'www.youtube.com',
      '/results',
      {'search_query': card.searchQuery},
    );
    final open = onWatchElsewhere ??
        ((Uri u) => launchUrl(u, mode: LaunchMode.externalApplication));
    await open(uri);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final photo = card.photoPath;

    // Null while the context is still resolving. Withholding until it lands
    // is the safe direction: the list reappears a frame later for a user with
    // nothing to screen, whereas showing first and retracting would put
    // unscreened movements in front of an injured user for exactly as long as
    // it takes them to read one.
    final safety = ref.watch(safetyContextProvider).valueOrNull;
    // `allowsAnyTraining` is deliberately NOT the test. `screen()` is
    // fail-closed, so an un-onboarded user is "blocked" purely for having
    // answered nothing — gating on it would withhold from everyone who has
    // not finished the questionnaire, which is most people who open the
    // scanner, and would delete this feature exactly as a catalogue match
    // would. What matters is whether the user has told us something that
    // screens: an ANSWERED block, an injury, or a movement restriction.
    // Someone who has told us nothing has nothing to screen against, and the
    // app's own disclosure system (SafetyDisclosure) is what states that
    // honestly rather than hiding content over it.
    final blockedByAnAnswer =
        safety?.wholePersonBlocks.any((r) => !r.unanswered) ?? false;
    final showUses = safety != null &&
        !blockedByAnAnswer &&
        safety.injuries.isEmpty &&
        safety.health.restrictions.isEmpty;

    return GlassCard(
      key: const Key('machine-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showPhoto && photo != null && File(photo).existsSync()) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(
                File(photo),
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
                // The photo is a nicety; a file that has since been swept out
                // of the cache must not take the explanation down with it.
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  card.name,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 8),
              _PreparingBadge(label: l.machineCardPreparing),
            ],
          ),
          const SizedBox(height: 6),
          Text(card.summary, style: theme.textTheme.bodyMedium),
          if (card.uses.isNotEmpty && showUses) ...[
            const SizedBox(height: 12),
            Text(
              l.machineCardWhatYouCanDo,
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            for (final use in card.uses)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: theme.textTheme.bodyMedium),
                    Expanded(
                      child: Text(use, style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
          ] else if (card.uses.isNotEmpty) ...[
            // Says why, rather than silently rendering a shorter card. A list
            // that vanishes without explanation reads as the app having
            // nothing to say about the machine, which is a different and
            // untrue claim.
            const SizedBox(height: 12),
            Text(
              l.machineCardUsesWithheld,
              key: const Key('machine-card.uses-withheld'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colors.textSecondary),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: AppSecondaryButton(
              key: const Key('machine-card-watch'),
              onPressed: _watch,
              icon: Icons.play_circle_outline,
              label: l.machineCardWatchElsewhere,
            ),
          ),
        ],
      ),
    );
  }
}

/// The honest label. Not an error, not a promise with a date on it.
class _PreparingBadge extends StatelessWidget {
  const _PreparingBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
